// Read-only sensor bridge. SMC/HID ABI adapted from macmon (MIT).
// See THIRD_PARTY_NOTICES.md. No SMC writes, fan control, or privilege escalation.
#include "SensorBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <IOKit/storage/IOStorageProtocolCharacteristics.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t major, minor, build, reserved;
    uint16_t release;
} SMCVersion;
typedef struct {
    uint16_t version, length;
    uint32_t cpu, gpu, memory;
} SMCLimit;
typedef struct {
    uint32_t size, type;
    uint8_t attributes;
} SMCInfo;
typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCLimit limit;
    SMCInfo info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCRequest;
_Static_assert(sizeof(SMCRequest) == 80, "SMC ABI size changed");
_Static_assert(offsetof(SMCRequest, bytes) == 48, "SMC ABI layout changed");

static int32_t smc_call(uint32_t connection, SMCRequest *input, SMCRequest *output) {
    size_t size = sizeof(*output);
    IOReturn status = IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size);
    if (status) {
        return status;
    }
    if (size != sizeof(*output)) {
        return kIOReturnUnderrun;
    }
    return output->result ? 0x10000 + output->result : 0;
}

int32_t sp_smc_open(uint32_t *connection) {
    *connection = 0;
    io_iterator_t iterator = 0;
    IOReturn status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator);
    if (status) {
        return status;
    }
    io_service_t service;
    status = kIOReturnNotFound;
    while ((service = IOIteratorNext(iterator))) {
        io_name_t name = {0};
        IORegistryEntryGetName(service, name);
        if (strcmp(name, "AppleSMCKeysEndpoint") == 0) {
            status = IOServiceOpen(service, mach_task_self(), 0, connection);
            IOObjectRelease(service);
            break;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return status;
}

void sp_smc_close(uint32_t connection) {
    if (connection) {
        IOServiceClose(connection);
    }
}

int32_t sp_smc_key(uint32_t connection, uint32_t index, uint32_t *key) {
    SMCRequest input = {.command = 8, .index = index};
    SMCRequest output = {0};
    int32_t status = smc_call(connection, &input, &output);
    if (!status) {
        *key = output.key;
    }
    return status;
}

int32_t sp_smc_read(uint32_t connection, uint32_t key, SPValue *value) {
    memset(value, 0, sizeof(*value));
    SMCRequest input = {.key = key, .command = 9};
    SMCRequest output = {0};
    int32_t status = smc_call(connection, &input, &output);
    if (status) {
        return status;
    }
    value->size = output.info.size;
    value->type = output.info.type;
    if (value->size > sizeof(value->bytes)) {
        return kIOReturnOverrun;
    }
    input.command = 5;
    input.info = output.info;
    memset(&output, 0, sizeof(output));
    status = smc_call(connection, &input, &output);
    if (!status) {
        memcpy(value->bytes, output.bytes, value->size);
    }
    return status;
}

struct SPHID {
    void *library;
    CFTypeRef client;
    CFArrayRef services;
    CFTypeRef (*copyProperty)(CFTypeRef, CFStringRef);
    CFTypeRef (*copyEvent)(CFTypeRef, int64_t, int32_t, int64_t);
    double (*floatValue)(CFTypeRef, int64_t);
};

SPHID *sp_hid_open(int32_t *status) {
    *status = kIOReturnNoResources;
    SPHID *probe = calloc(1, sizeof(*probe));
    if (!probe) {
        return NULL;
    }
    probe->library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!probe->library) {
        sp_hid_close(probe);
        return NULL;
    }
    CFTypeRef (*create)(CFAllocatorRef) = dlsym(probe->library, "IOHIDEventSystemClientCreate");
    void (*matching)(CFTypeRef, CFDictionaryRef) = dlsym(probe->library, "IOHIDEventSystemClientSetMatching");
    CFArrayRef (*services)(CFTypeRef) = dlsym(probe->library, "IOHIDEventSystemClientCopyServices");
    probe->copyProperty = dlsym(probe->library, "IOHIDServiceClientCopyProperty");
    probe->copyEvent = dlsym(probe->library, "IOHIDServiceClientCopyEvent");
    probe->floatValue = dlsym(probe->library, "IOHIDEventGetFloatValue");
    if (!create || !matching || !services || !probe->copyProperty || !probe->copyEvent || !probe->floatValue) {
        *status = kIOReturnUnsupported;
        sp_hid_close(probe);
        return NULL;
    }
    probe->client = create(kCFAllocatorDefault);
    if (!probe->client) {
        sp_hid_close(probe);
        return NULL;
    }
    int page = 0xff00;
    int usage = 5;
    CFNumberRef pageNumber = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef usageNumber = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *values[] = {pageNumber, usageNumber};
    CFDictionaryRef filter = CFDictionaryCreate(
        NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    matching(probe->client, filter);
    probe->services = services(probe->client);
    CFRelease(filter);
    CFRelease(pageNumber);
    CFRelease(usageNumber);
    if (!probe->services) {
        *status = kIOReturnNotFound;
        sp_hid_close(probe);
        return NULL;
    }
    *status = 0;
    return probe;
}

int32_t sp_hid_count(SPHID *probe) {
    return probe && probe->services ? (int32_t)CFArrayGetCount(probe->services) : 0;
}

void sp_hid_name(SPHID *probe, int32_t index, char *name, size_t size) {
    if (!size) {
        return;
    }
    name[0] = 0;
    if (index < 0 || index >= sp_hid_count(probe)) {
        return;
    }
    CFTypeRef property = probe->copyProperty(CFArrayGetValueAtIndex(probe->services, index), CFSTR("Product"));
    if (property) {
        if (CFGetTypeID(property) == CFStringGetTypeID()) {
            CFStringGetCString(property, name, size, kCFStringEncodingUTF8);
        }
        CFRelease(property);
    }
}

int32_t sp_hid_read(SPHID *probe, int32_t index, double *value) {
    if (index < 0 || index >= sp_hid_count(probe)) {
        return kIOReturnBadArgument;
    }
    CFTypeRef event = probe->copyEvent(CFArrayGetValueAtIndex(probe->services, index), 15, 0, 0);
    if (!event) {
        return kIOReturnNotFound;
    }
    *value = probe->floatValue(event, 15 << 16);
    CFRelease(event);
    return 0;
}

void sp_hid_close(SPHID *probe) {
    if (!probe) {
        return;
    }
    if (probe->services) {
        CFRelease(probe->services);
    }
    if (probe->client) {
        CFRelease(probe->client);
    }
    if (probe->library) {
        dlclose(probe->library);
    }
    free(probe);
}

_Static_assert(sizeof(NVMeSMARTData) == 512, "NVMe SMART ABI size changed");
_Static_assert(offsetof(NVMeSMARTData, TEMPERATURE) == 1, "NVMe temperature ABI offset changed");

// Original, bounded, read-only ancestor walk. Every retained object is released.
static int32_t nvme_interconnect_location(io_registry_entry_t service, char *location, size_t size) {
    uint64_t visited[16] = {0};
    size_t visited_count = 0;
    io_registry_entry_t current = service;
    location[0] = 0;
    if (IOObjectRetain(current) != kIOReturnSuccess) {
        return SP_NVME_LOCATION_LOOKUP_FAILED;
    }
    int32_t result = SP_NVME_LOCATION_LOOKUP_FAILED;
    while (visited_count < 16) {
        uint64_t identity = 0;
        if (IORegistryEntryGetRegistryEntryID(current, &identity) != kIOReturnSuccess || !identity) {
            break;
        }
        for (size_t i = 0; i < visited_count; i++) {
            if (visited[i] == identity) {
                goto done;
            }
        }
        visited[visited_count++] = identity;
        CFTypeRef property = IORegistryEntryCreateCFProperty(
            current, CFSTR(kIOPropertyProtocolCharacteristicsKey), NULL, 0);
        if (property) {
            if (CFGetTypeID(property) != CFDictionaryGetTypeID()) {
                CFRelease(property);
                break;
            }
            CFTypeRef value = CFDictionaryGetValue(
                (CFDictionaryRef)property, CFSTR(kIOPropertyPhysicalInterconnectLocationKey));
            if (value) {
                if (CFGetTypeID(value) == CFStringGetTypeID()
                    && CFStringGetLength((CFStringRef)value) > 0
                    && CFStringGetCString((CFStringRef)value, location, size, kCFStringEncodingUTF8)
                    && location[0]) {
                    result = SP_NVME_LOCATION_FOUND;
                }
                CFRelease(property);
                break;
            }
            CFRelease(property);
        }
        io_registry_entry_t parent = 0;
        IOReturn status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
        if (status != kIOReturnSuccess || !parent) {
            if (status == kIOReturnNotFound || status == kIOReturnNoDevice) {
                result = SP_NVME_LOCATION_MISSING_PROPERTY;
            }
            if (parent) {
                IOObjectRelease(parent);
            }
            break;
        }
        IOObjectRelease(current);
        current = parent;
    }
done:
    IOObjectRelease(current);
    if (result != SP_NVME_LOCATION_FOUND) {
        location[0] = 0;
    }
    return result;
}

struct SPNVMe {
    int32_t count;
    IONVMeSMARTInterface **interfaces[16];
    IOCFPlugInInterface **plugins[16];
    int32_t status[16];
    uint64_t registry_ids[16];
    int32_t identity_status[16];
    char locations[16][256];
    int32_t location_status[16];
};

SPNVMe *sp_nvme_open(int32_t *status) {
    SPNVMe *probe = calloc(1, sizeof(*probe));
    if (!probe) {
        *status = kIOReturnNoResources;
        return NULL;
    }
    io_iterator_t iterator = 0;
    *status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator);
    if (*status) {
        free(probe);
        return NULL;
    }
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef capable = IORegistryEntryCreateCFProperty(service, CFSTR("NVMe SMART Capable"), NULL, 0);
        if (capable && CFEqual(capable, kCFBooleanTrue)) {
            if (probe->count == 16) {
                *status = kIOReturnOverrun;
                CFRelease(capable);
                IOObjectRelease(service);
                break;
            }
            int index = probe->count++;
            probe->identity_status[index] = IORegistryEntryGetRegistryEntryID(service, &probe->registry_ids[index]);
            if (!probe->identity_status[index] && !probe->registry_ids[index]) {
                probe->identity_status[index] = kIOReturnNotFound;
            }
            probe->location_status[index] = nvme_interconnect_location(
                service, probe->locations[index], sizeof(probe->locations[index]));
            IOCFPlugInInterface **plugin = NULL;
            SInt32 score = 0;
            probe->status[index] = IOCreatePlugInInterfaceForService(
                service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
            if (!probe->status[index] && plugin) {
                probe->status[index] = (*plugin)->QueryInterface(
                    plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (void **)&probe->interfaces[index]);
            } else if (!probe->status[index]) {
                probe->status[index] = kIOReturnNotFound;
            }
            probe->plugins[index] = plugin;
        }
        if (capable) {
            CFRelease(capable);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return probe;
}

int32_t sp_nvme_count(SPNVMe *probe) {
    return probe ? probe->count : 0;
}

int32_t sp_nvme_identity(SPNVMe *probe, int32_t index, uint64_t *registry_id) {
    if (registry_id) {
        *registry_id = 0;
    }
    if (!probe || !registry_id || index < 0 || index >= probe->count) {
        return kIOReturnBadArgument;
    }
    if (probe->identity_status[index]) {
        return probe->identity_status[index];
    }
    *registry_id = probe->registry_ids[index];
    return kIOReturnSuccess;
}

int32_t sp_nvme_location(SPNVMe *probe, int32_t index, char *location,
                         size_t size, int32_t *lookup_status) {
    if (location && size) {
        location[0] = 0;
    }
    if (lookup_status) {
        *lookup_status = SP_NVME_LOCATION_LOOKUP_FAILED;
    }
    if (!probe || !location || !size || !lookup_status || index < 0 || index >= probe->count) {
        return kIOReturnBadArgument;
    }
    *lookup_status = probe->location_status[index];
    if (*lookup_status == SP_NVME_LOCATION_FOUND) {
        size_t length = strlen(probe->locations[index]);
        if (length >= size) {
            *lookup_status = SP_NVME_LOCATION_LOOKUP_FAILED;
            return kIOReturnOverrun;
        }
        memcpy(location, probe->locations[index], length + 1);
    }
    return kIOReturnSuccess;
}

int32_t sp_nvme_read(SPNVMe *probe, int32_t index, uint16_t *kelvin) {
    if (!probe || index < 0 || index >= probe->count) {
        return kIOReturnBadArgument;
    }
    if (probe->status[index]) {
        return probe->status[index];
    }
    IONVMeSMARTInterface **interface = probe->interfaces[index];
    if (!interface || !(*interface)->SMARTReadData) {
        return kIOReturnUnsupported;
    }
    NVMeSMARTData data = {0};
    int32_t readStatus = (*interface)->SMARTReadData(interface, &data);
    if (!readStatus) {
        *kelvin = CFSwapInt16LittleToHost(data.TEMPERATURE);
    }
    return readStatus;
}

void sp_nvme_close(SPNVMe *probe) {
    if (!probe) {
        return;
    }
    for (int i = 0; i < probe->count; i++) {
        if (probe->interfaces[i]) {
            (*probe->interfaces[i])->Release(probe->interfaces[i]);
        }
        if (probe->plugins[i]) {
            IODestroyPlugInInterface(probe->plugins[i]);
        }
    }
    free(probe);
}

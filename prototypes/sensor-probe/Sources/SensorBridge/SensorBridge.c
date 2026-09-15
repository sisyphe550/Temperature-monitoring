// Exploratory read-only bridge. SMC/HID ABI adapted from macmon (MIT).
// See THIRD_PARTY_NOTICES.md. No SMC writes or device configuration calls.
#include "SensorBridge.h"
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCLimit;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCInfo;
typedef struct {
    uint32_t key; SMCVersion version; SMCLimit limit; SMCInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} SMCRequest;
_Static_assert(sizeof(SMCRequest) == 80, "SMC ABI size changed");
_Static_assert(offsetof(SMCRequest, bytes) == 48, "SMC ABI layout changed");

static int32_t smc_call(uint32_t connection, SMCRequest *input, SMCRequest *output) {
    size_t size = sizeof(*output);
    IOReturn status = IOConnectCallStructMethod(connection, 2, input, sizeof(*input), output, &size);
    if (status) return status;
    if (size != sizeof(*output)) return kIOReturnUnderrun;
    return output->result ? 0x10000 + output->result : 0;
}

int32_t sp_smc_open(uint32_t *connection) {
    *connection = 0;
    io_iterator_t iterator = 0;
    IOReturn status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator);
    if (status) return status;
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

void sp_smc_close(uint32_t connection) { if (connection) IOServiceClose(connection); }

int32_t sp_smc_key(uint32_t connection, uint32_t index, uint32_t *key) {
    SMCRequest input = {.command = 8, .index = index}, output = {0};
    int32_t status = smc_call(connection, &input, &output);
    if (!status) *key = output.key;
    return status;
}

int32_t sp_smc_read(uint32_t connection, uint32_t key, SPValue *value) {
    memset(value, 0, sizeof(*value));
    SMCRequest input = {.key = key, .command = 9}, output = {0};
    int32_t status = smc_call(connection, &input, &output);
    if (status) return status;
    value->size = output.info.size;
    value->type = output.info.type;
    if (value->size > sizeof(value->bytes)) return kIOReturnOverrun;
    input.command = 5;
    input.info = output.info;
    memset(&output, 0, sizeof(output));
    status = smc_call(connection, &input, &output);
    if (!status) memcpy(value->bytes, output.bytes, value->size);
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
    if (!probe) return NULL;
    probe->library = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!probe->library) { sp_hid_close(probe); return NULL; }
    CFTypeRef (*create)(CFAllocatorRef) = dlsym(probe->library, "IOHIDEventSystemClientCreate");
    void (*matching)(CFTypeRef, CFDictionaryRef) = dlsym(probe->library, "IOHIDEventSystemClientSetMatching");
    CFArrayRef (*services)(CFTypeRef) = dlsym(probe->library, "IOHIDEventSystemClientCopyServices");
    probe->copyProperty = dlsym(probe->library, "IOHIDServiceClientCopyProperty");
    probe->copyEvent = dlsym(probe->library, "IOHIDServiceClientCopyEvent");
    probe->floatValue = dlsym(probe->library, "IOHIDEventGetFloatValue");
    if (!create || !matching || !services || !probe->copyProperty || !probe->copyEvent || !probe->floatValue) {
        *status = kIOReturnUnsupported; sp_hid_close(probe); return NULL;
    }
    probe->client = create(kCFAllocatorDefault);
    if (!probe->client) { sp_hid_close(probe); return NULL; }
    int page = 0xff00, usage = 5;
    CFNumberRef pageNumber = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef usageNumber = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *values[] = {pageNumber, usageNumber};
    CFDictionaryRef filter = CFDictionaryCreate(NULL, keys, values, 2, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    matching(probe->client, filter);
    probe->services = services(probe->client);
    CFRelease(filter); CFRelease(pageNumber); CFRelease(usageNumber);
    if (!probe->services) { *status = kIOReturnNotFound; sp_hid_close(probe); return NULL; }
    *status = 0;
    return probe;
}

int32_t sp_hid_count(SPHID *probe) { return probe && probe->services ? (int32_t)CFArrayGetCount(probe->services) : 0; }
void sp_hid_name(SPHID *probe, int32_t index, char *name, size_t size) {
    if (!size) return;
    name[0] = 0;
    if (index < 0 || index >= sp_hid_count(probe)) return;
    CFTypeRef property = probe->copyProperty(CFArrayGetValueAtIndex(probe->services, index), CFSTR("Product"));
    if (property) {
        if (CFGetTypeID(property) == CFStringGetTypeID()) CFStringGetCString(property, name, size, kCFStringEncodingUTF8);
        CFRelease(property);
    }
}
int32_t sp_hid_read(SPHID *probe, int32_t index, double *value) {
    if (index < 0 || index >= sp_hid_count(probe)) return kIOReturnBadArgument;
    CFTypeRef event = probe->copyEvent(CFArrayGetValueAtIndex(probe->services, index), 15, 0, 0);
    if (!event) return kIOReturnNotFound;
    *value = probe->floatValue(event, 15 << 16);
    CFRelease(event);
    return 0;
}
void sp_hid_close(SPHID *probe) {
    if (!probe) return;
    if (probe->services) CFRelease(probe->services);
    if (probe->client) CFRelease(probe->client);
    if (probe->library) dlclose(probe->library);
    free(probe);
}

// Keep each discovered SMART-capable service, including failures. No identify data
// or disk serial number is read. Discovery is bounded to 16 devices for this spike.
struct SPNVMe {
    int32_t count;
    IONVMeSMARTInterface **interfaces[16];
    IOCFPlugInInterface **plugins[16];
    int32_t status[16];
};
SPNVMe *sp_nvme_open(int32_t *status) {
    SPNVMe *probe = calloc(1, sizeof(*probe));
    if (!probe) { *status = kIOReturnNoResources; return NULL; }
    io_iterator_t iterator = 0;
    *status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDevice"), &iterator);
    if (*status) { free(probe); return NULL; }
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        CFTypeRef capable = IORegistryEntryCreateCFProperty(service, CFSTR("NVMe SMART Capable"), NULL, 0);
        if (capable && CFEqual(capable, kCFBooleanTrue)) {
            if (probe->count == 16) {
                *status = kIOReturnOverrun;
                CFRelease(capable); IOObjectRelease(service); break;
            }
            int index = probe->count++;
            IOCFPlugInInterface **plugin = NULL;
            SInt32 score = 0;
            probe->status[index] = IOCreatePlugInInterfaceForService(service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
            if (!probe->status[index] && plugin) {
                probe->status[index] = (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (void **)&probe->interfaces[index]);
            } else if (!probe->status[index]) {
                probe->status[index] = kIOReturnNotFound;
            }
            // Destroying the plugin here stops the connection still needed by
            // SMARTReadData (MACH_SEND_INVALID_DEST on the test M4 Air; issue #2).
            probe->plugins[index] = plugin;
        }
        if (capable) CFRelease(capable);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return probe;
}
int32_t sp_nvme_count(SPNVMe *probe) { return probe ? probe->count : 0; }
int32_t sp_nvme_read(SPNVMe *probe, int32_t index, uint16_t *kelvin) {
    if (!probe || index < 0 || index >= probe->count) return kIOReturnBadArgument;
    if (probe->status[index]) return probe->status[index];
    IONVMeSMARTInterface **interface = probe->interfaces[index];
    if (!interface || !(*interface)->SMARTReadData) return kIOReturnUnsupported;
    NVMeSMARTData data = {0};
    int32_t status = (*interface)->SMARTReadData(interface, &data);
    if (!status) *kelvin = CFSwapInt16LittleToHost(data.TEMPERATURE);
    return status;
}
void sp_nvme_close(SPNVMe *probe) {
    if (!probe) return;
    for (int i = 0; i < probe->count; i++) {
        if (probe->interfaces[i]) (*probe->interfaces[i])->Release(probe->interfaces[i]);
        if (probe->plugins[i]) IODestroyPlugInInterface(probe->plugins[i]);
    }
    free(probe);
}

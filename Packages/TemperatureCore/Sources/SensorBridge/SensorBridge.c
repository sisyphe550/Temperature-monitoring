// Read-only Apple SMC bridge. SMC ABI adapted from macmon (MIT).
// See THIRD_PARTY_NOTICES.md. No SMC writes, fan control, or privilege escalation.
#include "SensorBridge.h"
#include <IOKit/IOKitLib.h>
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

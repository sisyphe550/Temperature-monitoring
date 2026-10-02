#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t type;
    uint32_t size;
    uint8_t bytes[32];
} SPValue;

int32_t sp_smc_open(uint32_t *connection);
void sp_smc_close(uint32_t connection);
int32_t sp_smc_key(uint32_t connection, uint32_t index, uint32_t *key);
int32_t sp_smc_read(uint32_t connection, uint32_t key, SPValue *value);

typedef struct SPHID SPHID;
SPHID *sp_hid_open(int32_t *status);
int32_t sp_hid_count(SPHID *probe);
void sp_hid_name(SPHID *probe, int32_t index, char *name, size_t size);
int32_t sp_hid_read(SPHID *probe, int32_t index, double *value);
void sp_hid_close(SPHID *probe);

typedef struct SPNVMe SPNVMe;
SPNVMe *sp_nvme_open(int32_t *status);
int32_t sp_nvme_count(SPNVMe *probe);
// Observable IORegistry facts; no provider/physical semantic classification.
#define SP_NVME_LOCATION_FOUND ((int32_t)0)
#define SP_NVME_LOCATION_MISSING_PROPERTY ((int32_t)1)
#define SP_NVME_LOCATION_LOOKUP_FAILED ((int32_t)2)
int32_t sp_nvme_identity(SPNVMe *probe, int32_t index, uint64_t *registry_id);
int32_t sp_nvme_location(SPNVMe *probe, int32_t index, char *location,
                         size_t size, int32_t *lookup_status);
int32_t sp_nvme_read(SPNVMe *probe, int32_t index, uint16_t *kelvin);
void sp_nvme_close(SPNVMe *probe);

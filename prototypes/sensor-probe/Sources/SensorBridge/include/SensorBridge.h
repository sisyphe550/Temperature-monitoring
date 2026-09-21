#pragma once
#include <stdint.h>
#include <stddef.h>

typedef struct { uint32_t type, size; uint8_t bytes[32]; } SPValue;
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
int32_t sp_nvme_read(SPNVMe *probe, int32_t index, uint16_t *kelvin);
void sp_nvme_close(SPNVMe *probe);

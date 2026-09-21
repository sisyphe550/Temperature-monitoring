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

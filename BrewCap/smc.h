//
//  smc.h
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

#ifndef smc_h
#define smc_h

#include <stdint.h>

// Open/close connection to AppleSMC
int smc_open(void);
void smc_close(void);

// Read/write SMC keys
int smc_read_key(const char *key, uint8_t *out_bytes, uint32_t *out_size);
int smc_write_key(const char *key, const uint8_t *bytes, uint32_t size);

// Charging control
int smc_disable_charging(void);
int smc_enable_charging(void);

// Battery Charge Level Max
int smc_set_bclm(uint8_t percentage);
int smc_get_bclm(uint8_t *out_percentage);

#endif

//
//  smc.c
//  BrewCap
//
//  Copyright (c) 2026 NorthStars Industries. All rights reserved.
//

#include "smc.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <string.h>

// ============================================================
// Method 1: IORegistry property writes on AppleSmartBattery
// This is the Apple Silicon-compatible approach.
// ============================================================

static io_service_t get_battery_service(void) {
  return IOServiceGetMatchingService(kIOMainPortDefault,
                                     IOServiceMatching("AppleSmartBattery"));
}

static int set_battery_property(const char *key, CFTypeRef value) {
  io_service_t service = get_battery_service();
  if (service == IO_OBJECT_NULL) {
    fprintf(stderr, "battery: AppleSmartBattery service not found\n");
    return -1;
  }

  CFStringRef cfKey = CFStringCreateWithCString(kCFAllocatorDefault, key,
                                                kCFStringEncodingUTF8);
  kern_return_t result = IORegistryEntrySetCFProperty(service, cfKey, value);
  CFRelease(cfKey);
  IOObjectRelease(service);

  if (result != KERN_SUCCESS) {
    fprintf(stderr, "battery: set property '%s' failed: 0x%x\n", key, result);
    return -1;
  }
  fprintf(stdout, "battery: set property '%s' succeeded\n", key);
  return 0;
}

// ============================================================
// Method 2: SMC direct access (Intel Macs)
// Falls back to this if IORegistry approach doesn't work.
// ============================================================

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
  unsigned char major;
  unsigned char minor;
  unsigned char build;
  unsigned char reserved;
  unsigned short release;
} SMCKeyVersion;

typedef struct {
  uint16_t version;
  uint16_t length;
  uint32_t cpuPLimit;
  uint32_t gpuPLimit;
  uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
  uint32_t dataSize;
  uint32_t dataType;
  uint8_t dataAttributes;
} SMCKeyInfoData;

typedef struct {
  uint32_t key;
  SMCKeyVersion vers;
  SMCPLimitData pLimitData;
  SMCKeyInfoData keyInfo;
  uint16_t padding;
  uint8_t result;
  uint8_t status;
  uint8_t data8;
  uint32_t data32;
  uint8_t bytes[32];
} SMCParamStruct;

static io_connect_t g_smc_conn = 0;

static uint32_t four_char_code(const char *key) {
  uint32_t result = 0;
  for (int i = 0; i < 4 && key[i]; i++) {
    result = (result << 8) | (uint8_t)key[i];
  }
  return result;
}

static kern_return_t smc_call(SMCParamStruct *in_struct,
                              SMCParamStruct *out_struct) {
  size_t in_size = sizeof(SMCParamStruct);
  size_t out_size = sizeof(SMCParamStruct);
  return IOConnectCallStructMethod(g_smc_conn, KERNEL_INDEX_SMC, in_struct,
                                   in_size, out_struct, &out_size);
}

static int smc_read_key_info(uint32_t key, SMCKeyInfoData *info) {
  SMCParamStruct in_s, out_s;
  memset(&in_s, 0, sizeof(in_s));
  memset(&out_s, 0, sizeof(out_s));
  in_s.key = key;
  in_s.data8 = SMC_CMD_READ_KEYINFO;

  kern_return_t result = smc_call(&in_s, &out_s);
  if (result != KERN_SUCCESS) {
    fprintf(stderr, "smc: read_key_info failed: 0x%x\n", result);
    return -1;
  }
  *info = out_s.keyInfo;
  return 0;
}

// ============================================================
// Public API
// ============================================================

int smc_open(void) {
  io_service_t service = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("AppleSMC"));
  if (service == IO_OBJECT_NULL) {
    fprintf(stderr, "smc: AppleSMC service not found\n");
    return -1;
  }
  kern_return_t result =
      IOServiceOpen(service, mach_task_self(), 0, &g_smc_conn);
  IOObjectRelease(service);
  if (result != KERN_SUCCESS) {
    fprintf(stderr, "smc: IOServiceOpen failed: 0x%x\n", result);
    return -1;
  }
  return 0;
}

void smc_close(void) {
  if (g_smc_conn) {
    IOServiceClose(g_smc_conn);
    g_smc_conn = 0;
  }
}

int smc_read_key(const char *key, uint8_t *out_bytes, uint32_t *out_size) {
  uint32_t k = four_char_code(key);
  SMCKeyInfoData info;
  if (smc_read_key_info(k, &info) != 0)
    return -1;

  SMCParamStruct in_s, out_s;
  memset(&in_s, 0, sizeof(in_s));
  memset(&out_s, 0, sizeof(out_s));
  in_s.key = k;
  in_s.keyInfo = info;
  in_s.data8 = SMC_CMD_READ_BYTES;

  kern_return_t result = smc_call(&in_s, &out_s);
  if (result != KERN_SUCCESS)
    return -1;

  uint32_t size = info.dataSize;
  if (size > 32)
    size = 32;
  memcpy(out_bytes, out_s.bytes, size);
  *out_size = size;
  return 0;
}

int smc_write_key(const char *key, const uint8_t *bytes, uint32_t size) {
  uint32_t k = four_char_code(key);
  SMCKeyInfoData info;
  if (smc_read_key_info(k, &info) != 0)
    return -1;

  SMCParamStruct in_s, out_s;
  memset(&in_s, 0, sizeof(in_s));
  memset(&out_s, 0, sizeof(out_s));
  in_s.key = k;
  in_s.keyInfo = info;
  in_s.data8 = SMC_CMD_WRITE_BYTES;
  if (size > 32)
    size = 32;
  memcpy(in_s.bytes, bytes, size);

  kern_return_t result = smc_call(&in_s, &out_s);
  if (result != KERN_SUCCESS) {
    fprintf(stderr, "smc: write_key '%s' failed: 0x%x\n", key, result);
    return -1;
  }
  fprintf(stdout, "smc: write_key '%s' succeeded\n", key);
  return 0;
}

// ============================================================
// Charging Control — tries multiple methods
// ============================================================

int smc_disable_charging(void) {
  int success = 0;

  // Method 1: IORegistry — set ChargeInhibit on AppleSmartBattery
  fprintf(stdout, "Trying IORegistry ChargeInhibit...\n");
  if (set_battery_property("ChargeInhibit", kCFBooleanTrue) == 0) {
    success = 1;
  }

  // Method 1b: Also try setting a charge rate of 0
  int32_t zero = 0;
  CFNumberRef cfZero =
      CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &zero);
  if (set_battery_property("ChargeRate", cfZero) == 0) {
    success = 1;
  }
  CFRelease(cfZero);

  // Method 2: SMC CH0B (works on Intel Macs)
  fprintf(stdout, "Trying SMC CH0B...\n");
  uint8_t val = 0x02;
  if (smc_write_key("CH0B", &val, 1) == 0) {
    success = 1;
  }

  // Method 3: SMC CH0I
  uint8_t val_i = 0x01;
  if (smc_write_key("CH0I", &val_i, 1) == 0) {
    success = 1;
  }

  return success ? 0 : -1;
}

int smc_enable_charging(void) {
  int success = 0;

  // Method 1: IORegistry
  if (set_battery_property("ChargeInhibit", kCFBooleanFalse) == 0) {
    success = 1;
  }

  int32_t negOne = -1;
  CFNumberRef cfNeg =
      CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &negOne);
  if (set_battery_property("ChargeRate", cfNeg) == 0) {
    success = 1;
  }
  CFRelease(cfNeg);

  // Method 2: SMC
  uint8_t val = 0x00;
  if (smc_write_key("CH0B", &val, 1) == 0) {
    success = 1;
  }

  uint8_t val_i = 0x00;
  if (smc_write_key("CH0I", &val_i, 1) == 0) {
    success = 1;
  }

  return success ? 0 : -1;
}

int smc_set_bclm(uint8_t percentage) {
  // Try IORegistry approach first
  int32_t val = (int32_t)percentage;
  CFNumberRef cfVal =
      CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &val);
  int result = set_battery_property("ChargeCapacity", cfVal);
  CFRelease(cfVal);

  if (result == 0)
    return 0;

  // Fallback to SMC BCLM key
  return smc_write_key("BCLM", &percentage, 1);
}

int smc_get_bclm(uint8_t *out_percentage) {
  uint32_t size = 0;
  return smc_read_key("BCLM", out_percentage, &size);
}

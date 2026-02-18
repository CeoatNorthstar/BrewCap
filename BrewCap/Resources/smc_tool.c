/*
 * Apple System Management Control (SMC) Tool
 * Based on smcFanControl by devnull / Michael Wilber
 * Simplified for BrewCap battery charging control
 */

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6
#define SMC_CMD_READ_KEYINFO 9

typedef struct {
  char major;
  char minor;
  char build;
  char reserved[1];
  UInt16 release;
} SMCKeyData_vers_t;

typedef struct {
  UInt16 version;
  UInt16 length;
  UInt32 cpuPLimit;
  UInt32 gpuPLimit;
  UInt32 memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
  UInt32 dataSize;
  UInt32 dataType;
  char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef unsigned char SMCBytes_t[32];

/* This struct layout MUST match the kernel driver exactly */
typedef struct {
  UInt32 key;
  SMCKeyData_vers_t vers;
  SMCKeyData_pLimitData_t pLimitData;
  SMCKeyData_keyInfo_t keyInfo;
  char result;
  char status;
  char data8;
  UInt32 data32;
  SMCBytes_t bytes;
} SMCKeyData_t;

typedef char UInt32Char_t[5];

typedef struct {
  UInt32Char_t key;
  UInt32 dataSize;
  UInt32Char_t dataType;
  SMCBytes_t bytes;
} SMCVal_t;

static io_connect_t g_conn = 0;

static UInt32 _strtoul(char *str, int size, int base) {
  UInt32 total = 0;
  int i;
  for (i = 0; i < size; i++) {
    if (base == 16)
      total += (unsigned char)(str[i]) << (size - 1 - i) * 8;
    else
      total += (unsigned int)(str[i] - '0') << (size - 1 - i) * 8;
  }
  return total;
}

static void _ultostr(char *str, UInt32 val) {
  str[0] = (char)(val >> 24);
  str[1] = (char)(val >> 16);
  str[2] = (char)(val >> 8);
  str[3] = (char)val;
  str[4] = '\0';
}

static kern_return_t SMCOpen(void) {
  kern_return_t result;
  io_iterator_t iterator;
  io_object_t device;

  CFMutableDictionaryRef matchingDictionary = IOServiceMatching("AppleSMC");
  result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary,
                                        &iterator);
  if (result != kIOReturnSuccess) {
    fprintf(stderr, "Error: IOServiceGetMatchingServices() = %08x\n", result);
    return result;
  }

  device = IOIteratorNext(iterator);
  IOObjectRelease(iterator);
  if (device == 0) {
    fprintf(stderr, "Error: no SMC found\n");
    return kIOReturnNotFound;
  }

  result = IOServiceOpen(device, mach_task_self(), 0, &g_conn);
  IOObjectRelease(device);
  if (result != kIOReturnSuccess) {
    fprintf(stderr, "Error: IOServiceOpen() = %08x\n", result);
    return result;
  }

  return kIOReturnSuccess;
}

static kern_return_t SMCClose(void) { return IOServiceClose(g_conn); }

static kern_return_t SMCCall(SMCKeyData_t *inputStructure,
                             SMCKeyData_t *outputStructure) {
  size_t inSize = sizeof(SMCKeyData_t);
  size_t outSize = sizeof(SMCKeyData_t);
  return IOConnectCallStructMethod(g_conn, KERNEL_INDEX_SMC, inputStructure,
                                   inSize, outputStructure, &outSize);
}

static kern_return_t SMCReadKey(UInt32Char_t key, SMCVal_t *val) {
  kern_return_t result;
  SMCKeyData_t inputStructure;
  SMCKeyData_t outputStructure;

  memset(&inputStructure, 0, sizeof(SMCKeyData_t));
  memset(&outputStructure, 0, sizeof(SMCKeyData_t));
  memset(val, 0, sizeof(SMCVal_t));

  inputStructure.key = _strtoul(key, 4, 16);
  snprintf(val->key, sizeof(val->key), "%s", key);

  /* Get key info first */
  inputStructure.data8 = SMC_CMD_READ_KEYINFO;
  result = SMCCall(&inputStructure, &outputStructure);
  if (result != kIOReturnSuccess)
    return result;

  val->dataSize = outputStructure.keyInfo.dataSize;
  _ultostr(val->dataType, outputStructure.keyInfo.dataType);

  /* Now read the bytes */
  inputStructure.keyInfo.dataSize = val->dataSize;
  inputStructure.data8 = SMC_CMD_READ_BYTES;
  result = SMCCall(&inputStructure, &outputStructure);
  if (result != kIOReturnSuccess)
    return result;

  memcpy(val->bytes, outputStructure.bytes, sizeof(outputStructure.bytes));
  return kIOReturnSuccess;
}

static kern_return_t SMCWriteKey(SMCVal_t writeVal) {
  kern_return_t result;
  SMCKeyData_t inputStructure;
  SMCKeyData_t outputStructure;
  SMCVal_t readVal;

  /* Read first to get key info */
  result = SMCReadKey(writeVal.key, &readVal);
  if (result != kIOReturnSuccess)
    return result;

  if (readVal.dataSize != writeVal.dataSize) {
    fprintf(stderr, "Error: dataSize mismatch (read=%u, write=%u)\n",
            readVal.dataSize, writeVal.dataSize);
    return kIOReturnError;
  }

  memset(&inputStructure, 0, sizeof(SMCKeyData_t));
  memset(&outputStructure, 0, sizeof(SMCKeyData_t));

  inputStructure.key = _strtoul(writeVal.key, 4, 16);
  inputStructure.data8 = SMC_CMD_WRITE_BYTES;
  inputStructure.keyInfo.dataSize = writeVal.dataSize;
  memcpy(inputStructure.bytes, writeVal.bytes, sizeof(writeVal.bytes));

  result = SMCCall(&inputStructure, &outputStructure);
  if (result != kIOReturnSuccess) {
    fprintf(stderr, "Error: SMCWriteKey() = %08x\n", result);
  }
  return result;
}

static void printVal(SMCVal_t val) {
  printf("  %-4s  [%-4s]  ", val.key, val.dataType);
  if (val.dataSize > 0) {
    printf("(bytes");
    for (UInt32 i = 0; i < val.dataSize; i++)
      printf(" %02x", (unsigned char)val.bytes[i]);
    printf(")\n");
  } else {
    printf("no data\n");
  }
}

int main(int argc, char *argv[]) {
  int c;
  extern char *optarg;
  kern_return_t result;
  int op = 0; /* 0=none, 1=read, 2=write */
  UInt32Char_t key = {0};
  SMCVal_t val;

  memset(&val, 0, sizeof(val));

  while ((c = getopt(argc, argv, "hk:rw:")) != -1) {
    switch (c) {
    case 'k':
      strncpy(key, optarg, 4);
      key[4] = '\0';
      break;
    case 'r':
      op = 1;
      break;
    case 'w':
      op = 2;
      {
        size_t len = strlen(optarg);
        char hex[3];
        for (size_t i = 0; i < len / 2; i++) {
          hex[0] = optarg[i * 2];
          hex[1] = optarg[i * 2 + 1];
          hex[2] = '\0';
          val.bytes[i] = (unsigned char)strtol(hex, NULL, 16);
        }
        val.dataSize = (UInt32)(len / 2);
      }
      break;
    case 'h':
    default:
      printf("Usage: smc -k <key> -r         (read)\n");
      printf("       smc -k <key> -w <hex>   (write)\n");
      return 1;
    }
  }

  if (strlen(key) == 0 || op == 0) {
    printf("Usage: smc -k <key> -r         (read)\n");
    printf("       smc -k <key> -w <hex>   (write)\n");
    return 1;
  }

  result = SMCOpen();
  if (result != kIOReturnSuccess)
    return 1;

  if (op == 1) {
    result = SMCReadKey(key, &val);
    if (result == kIOReturnSuccess)
      printVal(val);
    else
      printf("no data\n");
  } else if (op == 2) {
    snprintf(val.key, sizeof(val.key), "%s", key);
    result = SMCWriteKey(val);
    if (result == kIOReturnSuccess)
      printf("ok\n");
  }

  SMCClose();
  return (result == kIOReturnSuccess) ? 0 : 1;
}

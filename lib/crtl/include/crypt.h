/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <crypt.h> -- one-way password hashing (crypt(3)).
 *
 * Found building dropbear (feature-c-dropbear-builds-with-pxx):
 * svr-authpasswd.c compares crypt(password, stored_hash) with the stored
 * hash.
 */
#ifndef _CRTL_CRYPT_H
#define _CRTL_CRYPT_H

char *crypt(const char *key, const char *salt);

/* libxcrypt's reentrant interface, with its layout (32768 bytes in all), so
   an object built against the host's <crypt.h> agrees with this one. */
#define CRYPT_OUTPUT_SIZE 384
#define CRYPT_MAX_PASSPHRASE_SIZE 512
#define CRYPT_DATA_RESERVED_SIZE 767
#define CRYPT_DATA_INTERNAL_SIZE 30720
struct crypt_data {
  char output[CRYPT_OUTPUT_SIZE];
  char setting[CRYPT_OUTPUT_SIZE];
  char input[CRYPT_MAX_PASSPHRASE_SIZE];
  char reserved[CRYPT_DATA_RESERVED_SIZE];
  char initialized;
  char internal[CRYPT_DATA_INTERNAL_SIZE];
};
char *crypt_r(const char *key, const char *salt, struct crypt_data *data);

#endif

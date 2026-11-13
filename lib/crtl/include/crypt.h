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

#endif

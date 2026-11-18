/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_CTYPE_H
#define PXX_CRTL_CTYPE_H 1

int isalnum(int c);
int isalpha(int c);
int isblank(int c);
int iscntrl(int c);
int isdigit(int c);
int isgraph(int c);
int islower(int c);
int isprint(int c);
int ispunct(int c);
int isspace(int c);
int isupper(int c);
int isxdigit(int c);
int tolower(int c);
int toupper(int c);

/* XSI: 7-bit test and mask (libX11's lcCT/lcUTF8 call isascii). */
int isascii(int c);
int toascii(int c);

#endif

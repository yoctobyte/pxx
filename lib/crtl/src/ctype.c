/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: ASCII ctype helpers.
 *
 * Locale-free, embedded-friendly classification table.
 */

#include <ctype.h>

#define _IS_UPP 0x01
#define _IS_LOW 0x02
#define _IS_DIG 0x04
#define _IS_SPC 0x08
#define _IS_CTL 0x10
#define _IS_PUN 0x20
#define _IS_BLA 0x40
#define _IS_HEX 0x80

static const unsigned char ctype_tab[128] = {
    /* 0x00 */ _IS_CTL,
    /* 0x01 */ _IS_CTL,
    /* 0x02 */ _IS_CTL,
    /* 0x03 */ _IS_CTL,
    /* 0x04 */ _IS_CTL,
    /* 0x05 */ _IS_CTL,
    /* 0x06 */ _IS_CTL,
    /* 0x07 */ _IS_CTL,
    /* 0x08 */ _IS_CTL,
    /* 0x09 */ _IS_SPC | _IS_BLA,
    /* 0x0A */ _IS_SPC,
    /* 0x0B */ _IS_SPC,
    /* 0x0C */ _IS_SPC,
    /* 0x0D */ _IS_SPC,
    /* 0x0E */ _IS_CTL,
    /* 0x0F */ _IS_CTL,
    /* 0x10 */ _IS_CTL,
    /* 0x11 */ _IS_CTL,
    /* 0x12 */ _IS_CTL,
    /* 0x13 */ _IS_CTL,
    /* 0x14 */ _IS_CTL,
    /* 0x15 */ _IS_CTL,
    /* 0x16 */ _IS_CTL,
    /* 0x17 */ _IS_CTL,
    /* 0x18 */ _IS_CTL,
    /* 0x19 */ _IS_CTL,
    /* 0x1A */ _IS_CTL,
    /* 0x1B */ _IS_CTL,
    /* 0x1C */ _IS_CTL,
    /* 0x1D */ _IS_CTL,
    /* 0x1E */ _IS_CTL,
    /* 0x1F */ _IS_CTL,
    /* 0x20 */ _IS_SPC | _IS_BLA,
    /* 0x21 */ _IS_PUN,
    /* 0x22 */ _IS_PUN,
    /* 0x23 */ _IS_PUN,
    /* 0x24 */ _IS_PUN,
    /* 0x25 */ _IS_PUN,
    /* 0x26 */ _IS_PUN,
    /* 0x27 */ _IS_PUN,
    /* 0x28 */ _IS_PUN,
    /* 0x29 */ _IS_PUN,
    /* 0x2A */ _IS_PUN,
    /* 0x2B */ _IS_PUN,
    /* 0x2C */ _IS_PUN,
    /* 0x2D */ _IS_PUN,
    /* 0x2E */ _IS_PUN,
    /* 0x2F */ _IS_PUN,
    /* 0x30 */ _IS_DIG | _IS_HEX,
    /* 0x31 */ _IS_DIG | _IS_HEX,
    /* 0x32 */ _IS_DIG | _IS_HEX,
    /* 0x33 */ _IS_DIG | _IS_HEX,
    /* 0x34 */ _IS_DIG | _IS_HEX,
    /* 0x35 */ _IS_DIG | _IS_HEX,
    /* 0x36 */ _IS_DIG | _IS_HEX,
    /* 0x37 */ _IS_DIG | _IS_HEX,
    /* 0x38 */ _IS_DIG | _IS_HEX,
    /* 0x39 */ _IS_DIG | _IS_HEX,
    /* 0x3A */ _IS_PUN,
    /* 0x3B */ _IS_PUN,
    /* 0x3C */ _IS_PUN,
    /* 0x3D */ _IS_PUN,
    /* 0x3E */ _IS_PUN,
    /* 0x3F */ _IS_PUN,
    /* 0x40 */ _IS_PUN,
    /* 0x41 */ _IS_UPP | _IS_HEX,
    /* 0x42 */ _IS_UPP | _IS_HEX,
    /* 0x43 */ _IS_UPP | _IS_HEX,
    /* 0x44 */ _IS_UPP | _IS_HEX,
    /* 0x45 */ _IS_UPP | _IS_HEX,
    /* 0x46 */ _IS_UPP | _IS_HEX,
    /* 0x47 */ _IS_UPP,
    /* 0x48 */ _IS_UPP,
    /* 0x49 */ _IS_UPP,
    /* 0x4A */ _IS_UPP,
    /* 0x4B */ _IS_UPP,
    /* 0x4C */ _IS_UPP,
    /* 0x4D */ _IS_UPP,
    /* 0x4E */ _IS_UPP,
    /* 0x4F */ _IS_UPP,
    /* 0x50 */ _IS_UPP,
    /* 0x51 */ _IS_UPP,
    /* 0x52 */ _IS_UPP,
    /* 0x53 */ _IS_UPP,
    /* 0x54 */ _IS_UPP,
    /* 0x55 */ _IS_UPP,
    /* 0x56 */ _IS_UPP,
    /* 0x57 */ _IS_UPP,
    /* 0x58 */ _IS_UPP,
    /* 0x59 */ _IS_UPP,
    /* 0x5A */ _IS_UPP,
    /* 0x5B */ _IS_PUN,
    /* 0x5C */ _IS_PUN,
    /* 0x5D */ _IS_PUN,
    /* 0x5E */ _IS_PUN,
    /* 0x5F */ _IS_PUN,
    /* 0x60 */ _IS_PUN,
    /* 0x61 */ _IS_LOW | _IS_HEX,
    /* 0x62 */ _IS_LOW | _IS_HEX,
    /* 0x63 */ _IS_LOW | _IS_HEX,
    /* 0x64 */ _IS_LOW | _IS_HEX,
    /* 0x65 */ _IS_LOW | _IS_HEX,
    /* 0x66 */ _IS_LOW | _IS_HEX,
    /* 0x67 */ _IS_LOW,
    /* 0x68 */ _IS_LOW,
    /* 0x69 */ _IS_LOW,
    /* 0x6A */ _IS_LOW,
    /* 0x6B */ _IS_LOW,
    /* 0x6C */ _IS_LOW,
    /* 0x6D */ _IS_LOW,
    /* 0x6E */ _IS_LOW,
    /* 0x6F */ _IS_LOW,
    /* 0x70 */ _IS_LOW,
    /* 0x71 */ _IS_LOW,
    /* 0x72 */ _IS_LOW,
    /* 0x73 */ _IS_LOW,
    /* 0x74 */ _IS_LOW,
    /* 0x75 */ _IS_LOW,
    /* 0x76 */ _IS_LOW,
    /* 0x77 */ _IS_LOW,
    /* 0x78 */ _IS_LOW,
    /* 0x79 */ _IS_LOW,
    /* 0x7A */ _IS_LOW,
    /* 0x7B */ _IS_PUN,
    /* 0x7C */ _IS_PUN,
    /* 0x7D */ _IS_PUN,
    /* 0x7E */ _IS_PUN,
    /* 0x7F */ _IS_CTL,
};

static int _ct_test(int c, unsigned char mask)
{
    if (c < 0 || c > 127)
        return 0;
    return (ctype_tab[c] & mask) != 0;
}

int isalnum(int c) { return _ct_test(c, _IS_DIG | _IS_UPP | _IS_LOW); }
int isalpha(int c) { return _ct_test(c, _IS_UPP | _IS_LOW); }
int isblank(int c) { return _ct_test(c, _IS_BLA); }
int iscntrl(int c) { return _ct_test(c, _IS_CTL); }
int isdigit(int c) { return _ct_test(c, _IS_DIG); }
int isgraph(int c) { return _ct_test(c, _IS_DIG | _IS_UPP | _IS_LOW | _IS_PUN); }
int islower(int c) { return _ct_test(c, _IS_LOW); }
int isprint(int c) { return _ct_test(c, _IS_DIG | _IS_UPP | _IS_LOW | _IS_PUN | _IS_SPC); }
int ispunct(int c) { return _ct_test(c, _IS_PUN); }
int isspace(int c) { return _ct_test(c, _IS_SPC); }
int isupper(int c) { return _ct_test(c, _IS_UPP); }
int isxdigit(int c) { return _ct_test(c, _IS_HEX); }

int tolower(int c)
{
    if (c >= 'A' && c <= 'Z')
        return c + ('a' - 'A');
    return c;
}

int toupper(int c)
{
    if (c >= 'a' && c <= 'z')
        return c + ('A' - 'a');
    return c;
}

/* SPDX-License-Identifier: Zlib */
/*
 * <getopt.h> — the spelling programs use when they ask for getopt explicitly.
 * POSIX puts the declarations in <unistd.h>; glibc ships this header as well
 * and adds getopt_long there. getopt_long lives in <unistd.h> here too, so
 * this stays a forwarder rather than becoming a second declaration site: two
 * declarations of one function is how they drift.
 */
#ifndef _PXX_GETOPT_H
#define _PXX_GETOPT_H

#include <unistd.h>

#endif

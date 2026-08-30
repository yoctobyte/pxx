/* SPDX-License-Identifier: Zlib */
/*
 * <getopt.h> — the spelling programs use when they ask for getopt explicitly.
 * POSIX puts the declarations in <unistd.h>; glibc ships this header as well
 * and adds getopt_long there. We have no getopt_long, so this is a forwarder
 * rather than a second declaration site: two declarations of one function is
 * how they drift.
 */
#ifndef _PXX_GETOPT_H
#define _PXX_GETOPT_H

#include <unistd.h>

#endif

/* SPDX-License-Identifier: Zlib */
/*
 * <getopt.h>: getopt_long(3) and its table, and getopt itself. POSIX puts
 * getopt, optarg and optind in <unistd.h>, which this includes. getopt_long
 * and `struct option` are declared HERE and only here, as glibc does: they
 * used to live in <unistd.h> with this file forwarding to it, and a program
 * with its own `struct option` that includes <unistd.h> (git's
 * parse-options.h) then collided with getopt's.
 * bug-crtl-unistd-h-declares-getopts-struct-option
 *
 * `flag' NULL means "return val"; non-NULL means "store val there and return
 * 0", which is how a table sets a variable without the caller writing a case.
 *
 * DIVERGENCE, and it is in the message and not the decision: an ambiguous
 * prefix is rejected exactly as glibc rejects it, but the diagnostic stops at
 * "is ambiguous" instead of going on to list the candidates.
 */
#ifndef _PXX_GETOPT_H
#define _PXX_GETOPT_H

#include <unistd.h>

#define no_argument        0
#define required_argument  1
#define optional_argument  2

struct option {
  const char *name;
  int has_arg;
  int *flag;
  int val;
};

int getopt_long(int argc, char *const argv[], const char *optstring,
                const struct option *longopts, int *longindex);
int getopt_long_only(int argc, char *const argv[], const char *optstring,
                     const struct option *longopts, int *longindex);

#endif

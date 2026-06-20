#ifndef PXX_CRTL_SYS_TYPES_H
#define PXX_CRTL_SYS_TYPES_H 1

#include <stddef.h>
#include <stdint.h>
#include <sys/_types.h>

typedef __off_t off_t;
typedef __ssize_t ssize_t;
typedef __time_t time_t;
typedef long pid_t;
typedef unsigned int mode_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
typedef unsigned long dev_t;
typedef unsigned long ino_t;

#endif

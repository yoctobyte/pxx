/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/signalfd.h> -- signalfd(2). Written from the signalfd(2)
 * manual page: struct signalfd_siginfo is the record read() returns, 128 bytes,
 * fields in the order the page lists them (the later additions ssi_syscall,
 * ssi_call_addr and ssi_arch included), padded to 128. The flags are the open
 * flags of the same names, as for eventfd.
 * Without this header the HOST's was used (libsystemd's sd-event.h includes it,
 * Panorama's bus helper) and it needs glibc's <stdint.h> to have brought
 * __BEGIN_DECLS. feature-crtl-sys-signalfd-h
 */
#ifndef PXX_CRTL_SYS_SIGNALFD_H
#define PXX_CRTL_SYS_SIGNALFD_H 1

#include <stdint.h>
#include <signal.h>
#include <fcntl.h>

#define SFD_CLOEXEC  O_CLOEXEC
#define SFD_NONBLOCK O_NONBLOCK

struct signalfd_siginfo {
  uint32_t ssi_signo;
  int32_t  ssi_errno;
  int32_t  ssi_code;
  uint32_t ssi_pid;
  uint32_t ssi_uid;
  int32_t  ssi_fd;
  uint32_t ssi_tid;
  uint32_t ssi_band;
  uint32_t ssi_overrun;
  uint32_t ssi_trapno;
  int32_t  ssi_status;
  int32_t  ssi_int;
  uint64_t ssi_ptr;
  uint64_t ssi_utime;
  uint64_t ssi_stime;
  uint64_t ssi_addr;
  uint16_t ssi_addr_lsb;
  uint16_t __pad2;
  int32_t  ssi_syscall;
  uint64_t ssi_call_addr;
  uint32_t ssi_arch;
  uint8_t  __pad[28];
};

int signalfd(int fd, const sigset_t *mask, int flags);

#endif

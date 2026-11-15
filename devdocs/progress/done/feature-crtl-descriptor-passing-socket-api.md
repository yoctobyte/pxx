---
slug: feature-crtl-descriptor-passing-socket-api
track: C
prio: 60
type: feature
status: done
created: 2026-11-15
found-by: pxx (Gibux seat): the USB disk keeper passes each disk's socket to a root helper over SCM_RIGHTS
tags: [crtl, sockets]
blocked-by: []
summary: "crtl now has socketpair(2), SCM_RIGHTS/SCM_CREDENTIALS, struct ucred, MSG_CTRUNC, MSG_EOR and MSG_CMSG_CLOEXEC. sendmsg/recvmsg are the real calls on 64-bit targets with the Linux numbers (as pread/pwrite already were), so control data and every flag reach the kernel. The PAL fallback (single-buffer send/recv, no control data) stays for the rest, where socketpair answers ENOSYS. msghdr 56 bytes and cmsghdr 16, as glibc. recv with MSG_PEEK/MSG_DONTWAIT already worked. Gibux's drivers/usbhid/storage.c and drivers/lib/nbdkeeper.c compile. Test: test/c_scm_rights.c (executable, and a --threadsafe object linked by gcc)."
---

# Descriptor passing in crtl

lib/crtl/include/sys/socket.h, lib/crtl/src/netinet/in.c.

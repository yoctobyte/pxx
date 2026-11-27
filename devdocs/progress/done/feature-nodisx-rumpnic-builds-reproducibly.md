---
title: "nodisx rumpnic: the build directory no longer reaches the binary"
status: done
owner: claude-dupwt
prio: 50
area: nodisx
---

NetBSD's KASSERTs carry __FILE__. rumpnic built in two different places
therefore differed in 436 strings (the guest's /tmp/w/... against the
host's work directory). tools/nodisx/rumpnic/onsite.sh now passes
-ffile-prefix-map=$S=/usr/src/rumpnic.

Also in this change, test-onsite-rainyday.sh gzips the exported tree,
because the export serial line runs at about 20 KB/s. Its host reference
run now uses PXX_NO_HOST_INCLUDE=1 like the guest. And
lib/crtl/include/linux/unistd.h was added for e2fsprogs' llseek.c; it
includes <sys/syscall.h> for the __NR_* numbers, and its values match
gcc's.

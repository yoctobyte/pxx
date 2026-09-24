---
slug: feature-c-crtl-resolv-h-and-the-ns-parser
title: "crtl has no <resolv.h>: nslookup needs res_* plus the whole ns_* DNS message parser"
track: C
prio: 40
type: feature
status: done
created: 2026-09-02
found-by: frankD
owner:
blocked-by:
summary: 'DONE BY EVENTS in bd53b29d97 (2026-09-04, feat(crtl): a DNS resolver), found still open on 2026-09-24. lib/crtl/include/resolv.h, arpa/nameser.h, arpa/nameser_compat.h and lib/crtl/src/arpa/nameser.c provide struct __res_state and _res, res_init/res_mkquery/res_send, and the ns_* parser. The bound this ticket demanded is there: ns_name_unpack refuses a pointer that is not strictly backwards and also counts jumps. test/c_crtl_resolv.c feeds a self-pointer and a two-pointer loop, is wired in the Makefile against gcc -lresolv, and at HEAD every hostile row answers -1 and returns. That commit measured busybox at 396 of 400 TUs compiling at i386, nslookup included."'
---

# What is missing

Two layers that happen to live in one header:

**The resolver state.** `struct __res_state` and the `_res` global, and
specifically the fields nslookup reaches into: `_res.nsaddr_list`,
`_res.nscount`, `_res.options`, and `_res._u._ext.nsaddrs` /
`_res._u._ext.nscount` for the IPv6 servers. That last pair is inside a UNION
in glibc's struct and is reached by name -- so this is not a struct crtl is
free to design, it is a layout a program already depends on.

**The message parser.** `ns_initparse`, `ns_parserr`, `ns_msg` with
`ns_msg_base`/`ns_msg_end`/`ns_msg_count`, `ns_rr` with
`ns_rr_name`/`ns_rr_type`/`ns_rr_rdlen`/`ns_rr_rdata`, `ns_get16`/`ns_get32`,
`ns_name_uncompress`, and the `ns_t_*` / `ns_s_*` / `ns_c_*` enumerations.

# The one that will bite

`ns_name_uncompress` follows DNS name-compression pointers, and a message
arriving off the network can point a label back at itself. An implementation
that follows pointers without bounding the walk loops forever on a hostile
reply -- from a resolver the program was told to talk to. Any version of this
needs the bound, and needs a test that feeds it a self-referential pointer and
asserts it returns -1 rather than hanging.

# Why it is prio 40 and not higher

One translation unit, and the applet is nslookup. Everything else in busybox
that resolves names goes through `getaddrinfo`, which crtl already has. So the
value here is completeness of the corpus, not a class of programs unblocked --
unlike `feature-c-crtl-posix-regex-regcomp-regexec`, which is seven.

`feature-c-corpus-busybox-i386-the-second-architecture` is what this unblocks.

## 2026-09-24 (frankS): closed, already built

Re-measured at HEAD rather than trusting the 09-04 commit: test/c_crtl_resolv.c
compiles and runs, and the reserved-length, len-past-eom and counts-no-data rows
answer initparse=-1 uncompress=-1 without hanging. Wired at the Makefile's
c_resolv rows (gcc differential with -lresolv).

## Log
- 2026-09-24 — resolved, commit bd53b29d97.

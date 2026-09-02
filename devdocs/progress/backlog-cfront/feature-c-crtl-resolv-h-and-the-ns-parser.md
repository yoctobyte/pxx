---
slug: feature-c-crtl-resolv-h-and-the-ns-parser
title: "crtl has no <resolv.h>: nslookup needs res_* plus the whole ns_* DNS message parser"
track: C
prio: 40
type: feature
status: open
created: 2026-09-02
found-by: frankD
owner:
blocked-by:
summary: "networking/nslookup.c is the last busybox translation unit stopped by a header that is really an implementation. It needs `struct __res_state` and the _res global, res_init/res_mkquery/res_msend, and the ns_* message-parsing API -- ns_initparse, ns_parserr, ns_msg/ns_rr and their accessors, ns_name_uncompress. One TU, so it ranks below regex.h (7); filed separately because the two share nothing but their shape."
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

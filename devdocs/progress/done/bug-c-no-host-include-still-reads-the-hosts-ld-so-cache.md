---
title: "--no-host-include still read the host's /etc/ld.so.cache"
status: done
owner: claude-dupwt
prio: 60
area: cfront
---

Under --system-libs, every external C function records the soname of the
library its header's stem names (CSonameForStem). It asks /etc/ld.so.cache
first. Every rump unit is built that way. On the host, <sys/acl.h> gave
`libacl.so.1`, which went into each object's import data. Rainyday has no
cache, so the same compile there wrote `libc.so.6`. The result: rumpnic
built on site inside Rainyday differed from the same build on the host in
those bytes (tools/nodisx/test-onsite-rainyday.sh, 2026-11-27).

--no-host-include / PXX_NO_HOST_INCLUDE=1 means "compile as a target that
has nothing from the host". The host's library list is as foreign to such a
target as its headers. LdCacheLoad (compiler/pasparser_proc.inc) now leaves
the cache unread in that mode, the same way it already did when
cross-compiling. Checked with the e2e on rumpnic: guest and host binaries
are byte-identical.

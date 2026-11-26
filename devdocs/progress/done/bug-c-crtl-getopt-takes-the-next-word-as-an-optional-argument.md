---
title: "crtl getopt took the next word as an "o::" optional argument, and kept optarg across flags"
status: done
owner: claude-dupwt
prio: 55
area: crtl
---

busybox's testsuite, run on the Nodisx on-site busybox (pxx) against gcc's
build of the same configuration, failed seven sed tests and `xargs -e`.
`sed -i SCRIPT FILE` printed "unsupported command f": getopt treated `i::`
(an OPTIONAL argument) as required, so SCRIPT became -i's backup suffix and
FILE the script.

glibc's rule, now crtl's (lib/crtl/src/unistd.c): an optional argument is
only an attached one (`-i.bak`); a bare `-i` returns optarg NULL and the
next word stays an operand. The differential test also showed that a flag
option left optarg holding the previous option's argument, where glibc
clears it; each short option now starts with optarg NULL.

Test row c_optzhost26 (test/c_crtl_getopt_optional_tz_rule_and_hosts.c,
expected output from glibc).

---
slug: feature-nodisx-gnu-make-built-on-site-by-pxx
track: C
type: feature
status: done
owner: claude-dupwt
created: 2026-11-26
found-by: owner (umbrella-nodisx-compiles-the-whole-system-on-site-with-pxx, item 1)
summary: "GNU make 4.4.1 builds on the target with pxx + sh + toybox (tools/nodisx/make: record/onsite/test). Its own suite: 1422 tests, no failures (the gcc build fails misc/fopen-fail on this host). The Rainyday kernel built with the pxx make is byte-identical to the one built with the host's make (1,545,720 bytes). Needed from crtl: _POSIX_VERSION in <unistd.h> (make took its pre-POSIX sigblock path without it), eaccess/euidaccess, a reported stdout write error (bug-c-crtl-printf-reports-success-when-the-write-fails) and getenv following an assigned environ (bug-c-crtl-getenv-ignores-an-assigned-environ). The make binary: 497 KB text, 48 KB data."
---

See tools/nodisx/README.md, the GNU make section, and record.sh for the four
configure answers given as pxx's.

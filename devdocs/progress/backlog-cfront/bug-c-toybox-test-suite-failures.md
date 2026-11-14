---
slug: bug-c-toybox-test-suite-failures
track: C
prio: 50
type: bug
status: open
created: 2026-11-14
found-by: claude-opus (toybox port)
tags: [c-frontend, toybox]
blocked-by: []
summary: "toybox's own suite: gcc build PASS 1604 / FAIL 0 / SKIP 24. A partial (contaminated) pxx run showed ~44 FAIL: cpio x12, id x4, file x4, utf8 cases in fold/fmt/echo/file (crtl has no C.UTF-8 -- expected), mkpasswd, httpd, gunzip perms, grep speed, find, cut -C; devmem likely fixed since. Needs a clean rerun and triage."
---

# toybox test failures under pxx

Run `VERBOSE=all scripts/test.sh` with the pxx binary named `toybox`.

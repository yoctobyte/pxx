---
track: C
prio: 40
type: bug
status: done
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "**FIXED 2026-09-01 by `9d7228837` and left open for three days; closed 2026-09-04 after `crtl-reachability` was re-run at HEAD and answers OK -- 132 headers, 60 modules, every declared function reachable.** The fix moved the DEFINITION to `lib/crtl/src/string.c:641`, which is the remedy this ticket did not list and the best of the three: `<string.h>` keeps glibc's declaration site and no bridge TU has to be maintained. ORIGINAL REPORT: crtl's `<string.h>` declares `strsignal()` while the definition lives in `signal.c`. A program that includes only `<string.h>` gets the declaration and NOT the definition, so the symbol resolves from the host C library instead of crtl — silently, with no diagnostic. Caught by `tools/crtl_reachability.py`, which has been red on seven since 2026-09-01T17:40Z. Introduced by `3e77e3f1f`, which added the declaration where glibc puts it and the definition beside the signal code."
---

# `<string.h>` declares `strsignal()`, defined in `signal.c`

## What the checker says

`tools/crtl_reachability.py`, run at HEAD:

```
crtl-reachability: 1 unreachable declaration(s)

  <string.h> declares strsignal(), defined in signal.c

A program that includes only that header will NOT get the definition.
It will silently import the symbol from the system C library instead.
```

- declaration: `lib/crtl/include/string.h:74` — `char *strsignal(int sig);`
- definition:  `lib/crtl/src/signal.c:108`

## Why it matters

Silent host-libc fallback is the failure mode crtl exists to prevent. A program
that includes only `<string.h>` links the host's `strsignal` on a host build and
has no definition at all when cross-compiling — and nothing says so at compile
time. This is the same class as the `#include <dirent.h> resolved from the host
system` warning the checker emits elsewhere, but without the warning.

## Origin

`3e77e3f1f` "fix(C,A): a struct-typed local with a fn-pointer member, and crtl's
shell surface" — the commit that added `strsignal` for busybox's ash. Its own
message says *"strsignal with glibc's exact strings"*. The declaration went where
glibc has it (`<string.h>`) and the definition went beside the rest of the signal
code, which is a reasonable choice on each side and wrong as a pair.

## Fix — and one way NOT to fix it

The checker names three remedies. **Moving the declaration to `<signal.h>` is
the wrong one**: glibc declares `strsignal` in `<string.h>`, so moving it would
diverge from the header layout crtl is matching and break source that includes
only `<string.h>`, which is the portable spelling.

The two that preserve compatibility:

- make `<string.h>` include the header whose sibling `.c` defines it; or
- add a bridge sibling `.c` that does nothing but include `<string.h>`
  (see `lib/crtl/src/sys/socket.c` for the guard-order trap that shape has).

## Repro

```
tools/crtl_reachability.py        # exits with the unreachable-declaration report
```

Job: `lib-test#src:tools/crtl_reachability.py`. `job_last_pass` on seven is
`91b92d5e8c99`; first failure `5d983997a05a`.

## Log
- 2026-09-04 — resolved, commit 9d7228837.

## RESOLVED — fixed 2026-09-01 by `9d7228837`, and open for three days after

`tools/crtl_reachability.py` at HEAD (`72898b07c`):

    crtl-reachability: OK -- 132 headers, 60 modules,
    every declared function reachable from its own header

The fix took neither of the two remedies this ticket proposed and took the
better third: **the DEFINITION moved** to `lib/crtl/src/string.c:641`, beside
the header that declares it, rather than the declaration moving or a bridge TU
being added. `<string.h>` still declares it at line 74 exactly where glibc
does, so the compatibility this ticket was protecting is intact and there is no
extra file to keep in step. `lib/crtl/src/signal.c:158` carries a comment
saying where it went and why, so the next reader of the signal code does not
re-add it.

Closed by franks-ab while surveying the signal group for
[[bug-b-crtl-signal-and-sigaction-report-success-and-install-nothing]]. The
delay is worth one line: the checker that files this class also **clears
silently**, so a ticket whose only evidence is a red guard has nothing to
announce when the guard goes green. `9d7228837`'s subject says it made
crtl-reachability pass; nothing walked back to this slug.


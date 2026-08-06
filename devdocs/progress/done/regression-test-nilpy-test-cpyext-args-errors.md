---
prio: 70
status: done
---

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_cpyext_args_errors.npy red at 34c41bde6fd6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-05T19:36:23Z
- **Test source:** test/test_cpyext_args_errors.npy

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_cpyext_args_errors.npy'` at 34c41bde6fd66529206b2891337066a5a9fae50c

## Range
bad `34c41bde6fd6`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:16: error: uses: unit source not found: /lib/cpyext/src/pyruntime.c
(tail)
pascal26:16: error: uses: unit source not found: /lib/cpyext/src/pyruntime.c
  near:  interface uses pxxcio  ../../lib/cpyext/src/pyruntime.c >>>  ./argerr_ext_module.c  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-06 — STALE STUB, closing: the watcher itself already reported it FIXED

Not a live red. The whole cpyext family (args_errors, containers, cython, hello,
markupsafe) went red together at `34c41bde6fd6` and the watcher's very next
report — `tstate/reports/20260805T203501Z-aba953c-plexus.md`, about an hour
later — lists all five under **FIXED**. The auto-filed stub was never closed, so
it kept surfacing at the head of the ranked queue.

Re-verified at HEAD `733be3321` (compiler snapshot sha256 `cafd50517875`), all
five green:

```
PASS  test-nilpy#410  test/test_cpyext_hello.npy
PASS  test-nilpy#411  test/test_cpyext_args_errors.npy
PASS  test-nilpy#412  test/test_cpyext_containers.npy
PASS  test-nilpy#413  test/test_cpyext_markupsafe.npy
PASS  test-nilpy#414  test/test_cpyext_cython.npy
```

Also checked the failure mode itself rather than only the exit status. The log
tail was `uses: unit source not found: /lib/cpyext/src/pyruntime.c` — note the
LEADING SLASH, meaning the base directory the unit-relative
`'../../lib/cpyext/src/pyruntime.c'` resolves against came out empty. That is a
path-resolution shape worth being suspicious of, so it was probed directly at
HEAD: absolute `-Fu` with cwd outside the repo, and relative `-Fu` with cwd at
the repo root, both compile and link fine. Five tests sharing one `uses` line
going red and green together points at the transient tree state at `34c41bde6fd6`,
not at the resolver.

**No code change.** The lesson is the process one CLAUDE.md already names: an
async watcher callback is tagged to the sha it was tested at, and must be
re-checked against current HEAD before acting — this one had been fixed before
anybody read the ticket.

Possible Track T follow-up (NOT filed as a bug, since it may be intended): the
watcher files a stub on NEW-RED but does not appear to close or annotate that
stub when a later report moves the same job to FIXED, so a self-healing red
leaves a permanent prio-70 item at the head of the queue. If that is not already
handled, auto-closing would keep the ranked queue honest.
- 2026-08-06 — resolved, commit f66c75e75.

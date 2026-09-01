---
prio: 70
track: C
status: done
---

> **Track guessed as C from the FAILING STEP** — line 18 of 72, `python3 tools/crtl_reachability.py`, which names `tools/crtl_reachability.py`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 42 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py at 5d983997a05a in step 18/72, `python3 tools/crtl_reachability.py` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `802e5ed96a48`).
  Untriaged.
- **Found:** 2026-09-01T17:40:23Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +40
- **Failing step:** line 18 of 72 of the job's recipe; it names `tools/crtl_reachability.py`.
  ```
  python3 tools/crtl_reachability.py
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at 5d983997a05a49b34dba24f58a4bb38a97afc168

## Range
> **The named sha `5d983997a05a` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `5d983997a05a`, last good `91b92d5e8c99`, **2 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
lib track pinned to: stable_linux_amd64/default/pinned -> stable_pinned   (newest checkpoint: latest -> stable_latest)
frozen builtin RTL: stable_linux_amd64/default/builtin/ (11 src) -- isolates track A's compiler/builtin/ edits
=== lib-test: library smoke against stable_linux_amd64/default/pinned ===
crtl-reachability: 1 unreachable declaration(s)

  <string.h> declares strsignal(), defined in signal.c

A program that includes only that header will NOT get the definition.
It will silently import the symbol from the system C library instead.
Fix by one of: move the definition to the header's sibling .c; make the
header include the header whose sibling .c defines it; or add a bridge
sibling .c that does nothing but include that header (see
lib/crtl/src/sys/socket.c for the guard-order trap that shape has).

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## VERIFIED FIXED 2026-09-01 (frankC) — no longer reproduces at HEAD

Swept as part of "which of the 12 open auto-filed regressions still
reproduce?". Re-ran this ticket's OWN job recipe at `2d9878ac8`, compiler
`6afb21f66d10` (built from the pin, self-host fixedpoint converged):

```
PXX_ALLOW_FULL_SUITE=1 tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'
```

**GREEN, twice.** Run a second time deliberately: a single green run on a
regression that may be intermittent proves nothing, and this test's population
includes at least one known race. Two independent runs, both green.

**Cause NOT bisected, and this ticket does not claim one.** It no longer
reproduces; which commit fixed it is unestablished. Recorded that way on purpose
— an invented cause is worse than an absent one, and the bisect range in this
ticket dates the window it was FILED in, not the window it was fixed in.
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit bee5a0d19.

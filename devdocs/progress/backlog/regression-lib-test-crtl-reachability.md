---
prio: 70
track: C
type: regression
summary: "compiler/crtl_names.inc is a GENERATED file left stale by d9c71b8b3 (313 -> 323 functions). The red is the crtl-map step, NOT the crtl-reachability step the job is named after. Fix: python3 tools/gen_crtl_map.py."
---

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py red at 137a182ad46a (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T06:25:43Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +2

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at 137a182ad46aef8f5890771d223573832747c033

## Range
bad `137a182ad46a`, last good `e01894e6b1ed`, 24 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
lib track pinned to: stable_linux_amd64/default/pinned -> stable_pinned   (newest checkpoint: latest -> stable_latest)
frozen builtin RTL: stable_linux_amd64/default/builtin/ (8 src) -- isolates track A's compiler/builtin/ edits
=== lib-test: library smoke against stable_linux_amd64/default/pinned ===
crtl-reachability: OK -- 39 headers, 23 modules, every declared function reachable from its own header
crtl-map: compiler/crtl_names.inc is STALE — run: python3 tools/gen_crtl_map.py

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triaged 2026-08-16 by Track T (face 2) — REAL, and it is Track C's

Reproduced at current HEAD, so the "origin/master has advanced" caveat above is
settled — this is not stale:

```
tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'
  crtl-reachability: OK -- 39 headers, 23 modules, every declared function reachable
  crtl-map: compiler/crtl_names.inc is STALE — run: python3 tools/gen_crtl_map.py
  testmgr: RED
```

**Note which of the two steps failed.** `crtl-reachability` — the step this
ticket is NAMED after, because it is the job's first source file — passes. The
red is the *second* step in the same job, `crtl-map`. Do not go looking in
`crtl_reachability.py`.

### Diagnosis

`compiler/crtl_names.inc` is a GENERATED file and has not been regenerated since
crtl gained ten functions. Ran the generator against a copy to see the delta,
then reverted it:

```
-  313 functions across 22 headers.
+  323 functions across 22 headers.
```

68 lines of diff, all additions of the shape `cos:math.h cosh:math.h` — the ten
math entries that `d9c71b8b3 task(C): retire the ten __crtl_ dodge-prefixes in
crtl math` un-prefixed. That commit changed the headers and did not re-run
`tools/gen_crtl_map.py`; `compiler/crtl_names.inc` was last touched by
`c4a1d76f6`, before it.

### Owner and fix

**Track C** (`lib/crtl` + the C frontend; `compiler/crtl_names.inc` is compiler
ground, and this is the crtl map). The fix is one command plus a commit:

```sh
python3 tools/gen_crtl_map.py && git add compiler/crtl_names.inc
```

Track T does not make it: T owns the tool, never the bug, and
`compiler/crtl_names.inc` is outside T's push scope. Left red deliberately
rather than quietly regenerated — a generated file drifting from its source is
worth one Track C commit that says so.

### Why this took until now to surface

`lib-test` was enrolled in the watcher's `full` tier on 2026-08-14
([[task-t-enroll-libtest-demos-watcher]]). Before that, Track B's entire gate ran
only when a B agent typed it, so a stale generated file could sit unnoticed
indefinitely — the esptimer case that filed the enrolment ticket, recurring in a
different file. **This is the first red the enrolment produced, and it is a true
one**, attributed to its exact source rather than to an opaque `lib-test#00`.

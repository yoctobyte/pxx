---
prio: 70
status: done
owner: claude-A-N
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_dynarray_params.pas red at 34670fe9b872 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-07T06:56:07Z
- **Test source:** test/test_dynarray_params.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_dynarray_params.pas'` at 34670fe9b872dcfeee0e4a283c44cf0742466800

## Range
bad `34670fe9b872`, last good `06786c25ffc8`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3219155/test_dynarray_params26  [code=51782B  data=1536B  bss=9700B  procs=99]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-07 — resolved: a STALE TEST, not a code regression

The watcher's bisect was right and pointed at `635b231b9` *"fix(A): an open-array
VALUE parameter gets its own copy, as FPC does"*. That commit is **correct**; it
landed without updating this test, which still asserted the pre-fix behaviour
(*"Writes through the parameter are visible to the caller"*). The watcher then
auto-filed the resulting red as a regression, which is exactly what it should
do — the triage is what was missing.

### Measured against FPC, both halves

```pascal
procedure ScaleArr(arr: array of Integer; by: Integer);        { VALUE }
procedure ScaleArrVar(var arr: array of Integer; by: Integer); { VAR }
```

| | FPC | pxx HEAD |
| --- | --- | --- |
| value open array, after `ScaleArr(a, 10)` | `1 2 3 4` | `1 2 3 4` |
| var open array, after `ScaleArrVar(a, 10)` | `10 20 30 40` | `10 20 30 40` |

pxx agrees with FPC on both. The test was the only thing still asserting the old
semantics.

### What changed

The test now pins **both halves of the distinction** rather than just the one
that used to hold: the value form must NOT be visible to the caller, and the var
form must be. That is deliberate — the fix had to be conditional (a `var` open
array must keep aliasing), so a test that only pins one side lets a future change
"fix" one by breaking the other. Nine checks became twelve; the Makefile
expectation is updated to match.

### Why this was on the critical path

`make test` gates `make stabilize`, so a red here blocks **any** pin, by anyone —
which is how it surfaced: it blocked the pin for
[[feature-a-managed-block-kind-word]]. Worth knowing that an untriaged red in
`test-core` is not merely noise; it stops the stable-binary boundary from moving.

### Gate

`make stabilize` (= `make test` + the 4-iteration fixedpoint). Verified against
FPC directly rather than against the old expectation.
- 2026-08-07 — resolved, commit PENDING-COMMIT.

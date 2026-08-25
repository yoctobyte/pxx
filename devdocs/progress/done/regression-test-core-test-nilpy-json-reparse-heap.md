---
prio: 70
track: N
status: done
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 6 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_nilpy_json_reparse_heap.npy red at a28bc3993a0e (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T11:28:59Z
- **Test source:** test/test_nilpy_json_reparse_heap.npy

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_nilpy_json_reparse_heap.npy'` at a28bc3993a0e0caa0370b71abb1759287d3e9909

## Range
bad `a28bc3993a0e`, last good `d34ea0c3e6f0`, 9 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
ok: /tmp/testmgr-scratch-1206539/test_nilpy_jsonrep26  [code=2388648B  data=75864B  bss=75420B  procs=2002]
Segmentation fault

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## RESOLVED 2026-08-25 — a method DEFINITION read as a call, in a unit pre-scan

Both of these have one cause. Bisected by building at each candidate sha:
GOOD at `99939b3a1`, BAD at `f064c591b` — and `f064c591b` is the only commit
between them that touches `compiler/`.

That commit added a per-unit pre-scan that mints TObject's root methods when a
unit mentions a dot-preceded `Equals`/`GetHashCode`/`ToString`. `lib/rtl/json.pas`
line 307 is

```pascal
function TJSONValue.ToString(pretty: Boolean): AnsiString;
```

— a qualified IMPLEMENTATION HEADER, which is dot-preceded exactly like a call.
So every NilPy program importing `json` pulled `builtin` plus the root-method
rows, and `test_nilpy_json_reparse_heap` SEGFAULTED with no output while
`test_nilpy_json_module` silently dropped `song 120 b 3`.

The scan now walks back past `<TypeName> .` and refuses `function`/`procedure`,
so a definition no longer reads as a use.
`test/test_tobject_root_methods_inside_a_unit.pas` still passes — its unit
carries the qualified headers AND a real `L.Equals(R)` call, which is precisely
the discrimination that had been missing.

Filed separately and NOT fixed:
[[bug-a-minting-tobject-root-methods-from-a-unit-corrupts-the-heap]] — that
minting those rows from a unit can corrupt a program *at all* is the deeper
defect, and a segfault plus a silently-missing output line is far worse than
whatever the extra 42 KB costs. Which half does it (`ParseUsesUnitAmbient`
mid-unit vs `EnsureTObjectRootMethods` adding VMT rows late) is deliberately
left unmeasured there rather than guessed.

Gate: `make compiler/pascal26` converged in 1 round, both `.npy` tests match
CPython, `test_tobject_root_methods_inside_a_unit` unchanged, `tools/gate.sh
quick` GREEN.
- 2026-08-25 — resolved, commit PENDING-COMMIT.

---
track: A
prio: 55
type: bug
status: done
found: 2026-08-30
found-by: claude-A
owner: claude-A
---

# A by-ref float param on a cdecl call is classified SSE, and the program segfaults

A `var`/`const` float parameter is a **pointer**, so SysV puts it in the INTEGER
class. Both cdecl argument classifiers read the parameter's declared `TypeKind`
with no `IsRef` check, so `var d: Double` was passed in `xmm` while the callee
read a pointer out of a GP register. The result is a **segfault**, not a wrong
number.

```pascal
type TCb = function(var a: Double; b: Integer): Integer; cdecl;
function MyCb(var a: Double; b: Integer): Integer; cdecl;
begin Result := Trunc(a) + b; end;   { want 9 for (2.5, 7) }
```

## Two halves with different histories — this is the part worth reading

| | via fnptr (`IR_CALL_IND`) | called directly (`IR_CALL`) |
| --- | --- | --- |
| `pinned`, pre-SysV-prologue | **segfault** | **9**, correct |
| HEAD after the SysV prologue | **segfault** | **segfault** |
| with this fix | 9 | 9 |

- The **indirect** half is pre-existing: it crashes on binaries either side of
  the prologue work.
- The **direct** half is a REGRESSION introduced by
  `feature-cdecl-bodied-sysv-prologue`. Before it, a bodied `cdecl` proc had
  `ProcCdecl` unset, so a direct call used the internal all-integer convention
  on both sides and the misclassification was unreachable. Setting `ProcCdecl`
  moved direct calls onto the SysV path, which carries the bug.

Recording that split rather than filing one undifferentiated crash, because
"pre-existing" and "I broke it last commit" call for different amounts of
suspicion about what else moved.

## Controls run

- The same signature through a NON-cdecl proc pointer prints `9` correctly, so
  this is the cdecl classification and not by-ref params generally.
- An `array[0..2] of Double` param prints `9` on every binary tested, before and
  after. `IsArray` is therefore **not** part of the condition: widening it on
  the theory that array params look float-typed here would have changed a path
  measured working. The array param's `TypeKind` is evidently not reaching the
  classifier as a float.

## Fix

Add the `IsRef` exclusion to the register-class decision in both classifiers
(`ir_codegen.inc`, `IR_CALL` and `IR_CALL_IND`). Only the class decision is
corrected; `tk` itself is left alone at the two sites below the direct-call
classifier, which use it for variant/narrowing decisions a by-ref param does not
reach.

**Three sites recompute the same classification expression** in the direct-call
path alone. That is the `root-cause-over-microfix` smell — two is a smell, three
is a design flaw — and a single "effective ABI class of argument i" helper is
the real shape. Not done here because it touches the variadic and variant paths
and wants its own gate; the crash fix should not wait behind a refactor.

## Gate

`test/test_cdecl_bodied_sysv.pas` checks `by-ref float param via fnptr` and
`by-ref float param direct` (14 checks total, in test-core). Both segfault on a
pre-fix binary.

## Log
- 2026-08-30 — resolved, commit c63b40c71.

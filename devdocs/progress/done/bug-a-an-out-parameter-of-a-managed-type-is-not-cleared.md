---
track: A
prio: 35
type: bug
blocked-by: []
summary: "FIXED 2026-08-22 for AnsiString, dynamic arrays and interfaces; Variant and managed records deferred with a reason. `out s: AnsiString` was parsed as a plain `var`: the callee's entry does not finalize-and-nil the caller's variable, so a routine that assigns on only some paths leaves the caller's OLD string visible. FPC clears managed out parameters (and only managed ones — an ordinal `out` behaves like `var` there too, measured). pxx has no IsOut flag at all; `out` and `var` are the same token arm."
owner: trackA-night
---

# An `out` parameter of a managed type is not cleared on entry

- **Type:** bug (silent stale VALUE across a call boundary) — Track A
  (`compiler/pasparser_proc.inc` + the body-head managed-init path).
- **Status:** done
- **Opened:** 2026-08-21, from a string-RTL differential against FPC 3.2.2.

## Measurement

```pascal
procedure PVar (var v: Integer);    begin end;
procedure POut (out v: Integer);    begin end;
procedure POutS(out s: AnsiString); begin end;
begin
  i := 42;  PVar(i);   WriteLn('var:  ', i);
  i := 42;  POut(i);   WriteLn('out:  ', i);
  s := 'x'; POutS(s);  WriteLn('outs: [', s, ']');
end.
```

| row | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `var` ordinal | 42 | 42 |
| `out` ordinal | 42 | 42 |
| `out` **AnsiString** | `[]` | **`[x]`** |

So the rule is narrower than "out clears": FPC clears **managed** out parameters
only, and an ordinal `out` is indistinguishable from `var`. pxx clears neither,
which makes the ordinal row accidentally correct and the managed row wrong.

## Why it matters

A callee that assigns its `out` parameter on some paths and not others hands the
caller back its own previous value instead of an empty string. The caller has no
way to tell the difference — the variable simply still holds what it held — so
this is the "plausible wrong value far from the cause" shape, one call frame
removed. It is the same class as
`bug-a-a-failed-supports-left-the-out-interface-set`, which was the interface
spelling of exactly this and is fixed.

## Root cause

`out` is not modelled. All five parse sites read it as a spelling of `var`:

```pascal
if (CurTok.Kind = tkVar) or
   ((CurTok.Kind = tkIdent) and CaseEqual(CurTok.SVal, 'out')) then
begin
  isByRef := True;
  Next;
end
```

There is no `IsOut` flag on a parameter anywhere in the compiler.

## What the fix needs

1. **A flag.** `ProcParamIsOut`, a flat `cpi * MAX_PROC_PARAMS + i` array beside
   the existing `ProcParamIsConst` / `ProcParamDynDepth` — that pattern is
   established, so this part is cheap. Set it at all five `out` parse sites, not
   just the routine-header one, or the flag becomes another half-built arm.
2. **Finalize, not just nil.** This is the part that is not one line. An `out`
   parameter is by-reference: the frame slot holds a POINTER to the caller's
   variable, so `EmitZeroFrameSlot` (which the managed-locals pass uses) is the
   wrong tool — the store has to be indirect. And nilling alone **leaks**: the
   caller's variable currently owns a reference, and once it reads nil its own
   scope-exit release will not run. FPC *finalizes* — release, then nil. So the
   emission is a release-through-pointer plus a nil store, per managed kind
   (AnsiString, dynarray, interface, variant, managed record).
3. **At the IR level, not per backend.** The x86-64 body head does its managed
   nil-init with `EmitAsmX64`, and each other backend has its own. Prepending
   the clear as IR keeps all six in step — `devdocs/dev/ir-as-substrate.md`.

## Risk and gate

Low blast radius for self-host: the compiler's own sources use `out` in eleven
places and **none** with a managed type (the only interesting one is
`QueryInterface(constref IID: TGuid; out Obj)`, untyped). So the fixedpoint
should be unaffected; the ARC correctness of step 2 is the real risk, and
`-dPXX_HEAP_DEBUG` plus `-dPXX_OBJTRACE` are the tools for it
(`devdocs/dev/debugging-playbook.md`).

Gate: the three-row program above matching FPC, plus a managed round trip that
proves no leak — call an `out AnsiString` routine in a loop under
`PXX_HEAP_DEBUG` and watch the freed bytes, not just the printed value.

## Fixed — 2026-08-22

### The shape, which is smaller than step 2 of this ticket predicted

This ticket's plan called for a release-through-pointer emitter per managed
kind, at the IR level, because "the frame slot holds a POINTER to the caller's
variable, so `EmitZeroFrameSlot` is the wrong tool" and "nilling alone leaks".
Both true — and both already solved, by the ordinary assignment path:

- a MANAGED assignment already releases the old value before storing the new,
- an assignment through a BY-REF parameter already stores into the caller.

So "finalize the out parameter on entry" is exactly `s := ''` / `d := nil` /
`f := nil` compiled at the head of the body, and it needs no new emitter, no new
IR op, and nothing per backend. `ClearManagedOutParam` builds that one AST
assignment and hands it to `CompileAST`, beside `CompilePendingLocalInits` which
does the same thing for routine-local typed constants.

Worth noting the ORDER this had to happen in: `d := nil` through a by-ref param
was itself broken on x86-64 until
[[bug-a-a-whole-dynarray-assignment-to-a-var-parameter-is-discarded]], found
while writing this ticket's differential. Had that not been fixed first, the
dynarray arm of this pass would have compiled, emitted, and done nothing — a
half-working feature with a passing look about it.

### The flag

`pout[]`, a local of `ParseSubroutine` beside `pconst[]`, set where `out` is
distinguished from `var` and shifted with the params when `Self` is inserted
(both copies of that loop — the omission of `pconst` from one of them is a bug
this repo has already paid for once). **No persistent `ProcParamIsOut` array was
added**: the clear is emitted where the BODY is parsed, and every routine with a
body re-parses its own header through `ParseSubroutine`, so the four
declaration-side `out` sites (class/interface/record decls, proc types) have no
body to clear and need nothing. Step 1's "set it at all five sites or it becomes
a half-built arm" is answered by not building the arm the other four would feed.

### Measured

Every row against fpc 3.2.2, and the negative rows are the point: FPC clears
**only** managed kinds, so an `out Integer` / `out Char` / `out ShortString`
must keep behaving exactly like `var`.

| | before | after | FPC |
| --- | --- | --- | --- |
| `out AnsiString` | `[x]` | `[]` | `[]` |
| `out` dynarray | 3 | 0 | 0 |
| `out` interface | not nil | nil | nil |
| `out Integer` / `Char` / `ShortString` | unchanged | unchanged | unchanged |
| `out` Variant | `[vv]` | **`[vv]`** | `[]` |
| `out` managed record | `[q]` | **`[q]`** | `[]` |

Also verified: methods, class methods, a nested-routine host, two `out` params
in one header, `out` mixed with value and `const` params, an `out` param of a
FUNCTION, and an UNTYPED `out` (QueryInterface's shape) which correctly emits
nothing. `Supports` and `GetInterface` still behave.

ARC: 200,000 rounds where a SECOND owner holds the same string and the same
interface across the call — `t := s; OutS(s)` and `g := f; OutI(f)`. Zero
violations, **max RSS 392 KB flat**, and fpc 3.2.2 prints the same. That is the
property that matters: the clear must RELEASE the caller's reference (nilling
alone leaks) without releasing it twice (which would free the block the second
owner still reads).

### Deferred, with the reason

**Variant and managed records are still not cleared.** Not an oversight and not
laziness about the parse side — they are the two kinds with no empty-value
assignment to synthesise, which is the trick the rest of this fix rests on:

- `v := Unassigned` renders as `None`, not the empty string FPC prints, so it is
  not the same value and would trade one divergence for another. (That rendering
  is itself worth a look — an empty Variant printing `None` is a NilPy spelling
  leaking into Pascal output.)
- a record has no empty literal at all.

Both need the finalize-through-pointer primitive this pass was written to avoid,
which is a real piece of work and a separate slice. `PXXVarClear` already exists
in `builtinheap` for the Variant half and is the obvious starting point — note
`VarClear` is not reachable from Pascal source today
([[bug-b-vartostr-is-missing-from-variants]] covers the sibling gap).

### Test

`test/test_out_parameter_of_a_managed_type_is_cleared.pas`, wired into
`test-core`: 16 rows — the three cleared kinds, an assigned-anyway row, the
three negative controls, the plumbing shapes, and the ARC round trip.
**Byte-identical to fpc 3.2.2.**

### Gate

`make compiler/pascal26` (byte-identical fixedpoint, 1 round) + `tools/gate.sh
quick`.

## Log
- 2026-08-22 — resolved, commit PENDING-COMMIT.

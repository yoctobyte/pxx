---
track: A
prio: 35
type: bug
blocked-by: []
summary: "`out s: AnsiString` is parsed as a plain `var`: the callee's entry does not finalize-and-nil the caller's variable, so a routine that assigns on only some paths leaves the caller's OLD string visible. FPC clears managed out parameters (and only managed ones — an ordinal `out` behaves like `var` there too, measured). pxx has no IsOut flag at all; `out` and `var` are the same token arm."
owner: trackA-night
---

# An `out` parameter of a managed type is not cleared on entry

- **Type:** bug (silent stale VALUE across a call boundary) — Track A
  (`compiler/pasparser_proc.inc` + the body-head managed-init path).
- **Status:** working
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

---
prio: 55
track: P
owner: frank-rust
status: done
---

# The address of a virtual class method cannot be lowered (`AN_CLASS_VIRTUAL_CALL`, kind 88)

- **Type:** bug (refused construct; the compiler correctly errors rather than
  miscompiling) — **Track P** (Pascal frontend lowering). **May escalate to
  Track A** if a new IR op is needed to name a vmt slot as a value — file it
  there if so rather than reaching into shared internals under P.
- **Found by:** rung 6, `rtl-generics`. Exposed *underneath*
  [[bug-p-a-generic-methods-out-of-line-header-binds-to-a-same-named-non-generic-class]]
  once that fix let `generics.defaults.pas` past line 2173; this is the wall at
  2351. Fifth distinct wall on that unit, and **not** typinfo.
- **Binary:** `e82c2f63a242`, verified fixedpoint at `042bcbb32`.

## Symptom

Taking the **address** of a virtual class method — using it as a value rather
than calling it — fails to lower:

```
error: IR_UNSUPPORTED: frontend could not lower AST node (kind 88)
       — a frontend gap, would miscompile
```

`AN_CLASS_VIRTUAL_CALL` (`defs.inc:512`) models "a virtual class method called
through a receiver". In this position it is not called at all, so nothing
lowers it. The error is honest — it refuses rather than emitting something
wrong — which is why this is a gap rather than a silent-miscompile escape.

## Repro (18 lines; FPC prints `TRUE`, pxx errors)

```pascal
program v2;
{$MODE DELPHI}{$H+}
type
  TMethod = record Code, Data: Pointer; end;   { or: uses SysUtils }
  TSel = function (A: LongInt): LongInt of object;
  TSvc = class
    class function Pick(A: LongInt): LongInt; virtual;
  end;
class function TSvc.Pick(A: LongInt): LongInt;
begin
  Result := A * 2;
end;
var
  p: Pointer;
begin
  p := TMethod(TSel(TSvc.Pick)).Code;   // <-- IR_UNSUPPORTED (kind 88)
  WriteLn(PtrUInt(p) <> 0);
end.
```

**Not generic-specific.** The corpus site is inside a generic, but the repro
above has no generics at all — worth stating because the rung-6 context makes it
look like a generics bug and it is not. `TMethod` is present in
`lib/rtl/sysutils.pas:133`; the repro declares it inline only to stay
dependency-free.

## Corpus site

```pascal
FEqualityComparerInstances[tkFile] :=
  TInstance.CreateSelector(TMethod(TSelectMethod(
    THashService<T>.SelectBinaryEqualityComparer)).Code);
```

One of a table of ~20 such initialisers, so it gates the comparer dispatch table
rather than a single line.

## Note on the wall count

Rung 6 was reported as four walls with the claim "complete set for this unit".
That claim was hedged for exactly this reason — code behind a stub is
type-checked against the stub, so clearing one wall can expose another. This is
the first instance. Update the count in [[feature-pascal-corpus-expansion]]
rather than treating the earlier partition as wrong: it listed what must be
built, not a prediction of first-try success.

---

## RESOLVED — already fixed, and fixed BEFORE the current pin

The ticket's own 18-line repro compiles and runs on HEAD `a9a4818ab6c8`, and it
also compiles on `pinned` `faf762981c3c`, so this was closed by someone else's
work between `e82c2f63a242` (the binary the ticket was filed against) and the
current pin. No `IR_UNSUPPORTED (kind 88)` anywhere.

Verified against FPC on more than "it compiles" — the pointer is **called
through**, for a base and an overriding descendant, so a statically-resolved and
a vmt-resolved answer are distinguishable:

| observable | pxx | FPC 3.2.2 |
| --- | --- | --- |
| `nonnil1` / `nonnil2` | TRUE / TRUE | TRUE / TRUE |
| `distinct` (base vs override differ) | TRUE | TRUE |
| `call1` through the taken address | 42 | 42 |
| `call2` through the taken address | 210 | 210 |

**The corpus site is unblocked.** All 24 initialisers in
`generics.defaults.pas:2381-2404` use the `THashService<T>.SelectX` spelling,
and that spelling compiles — confirmed directly, with the generic, on both
binaries.

## But two sibling receiver spellings are still broken — filed separately

`TryParseParenlessMethodRef` (`pasparser_call.inc:723`) is the single place that
reads `obj.M` with no `@` and no argument list as a method REFERENCE. It handles
**two** receiver spellings and there are **four**:

| arm | receiver | pxx | FPC |
| --- | --- | --- | --- |
| B | a class NAME — `TSvc.Pick`, `THashService<T>.Select` | works | works |
| D | an instance VARIABLE — `s.Pick` | works | works |
| A | **bare name** inside the class's own method — `TSel(Pick)` | `wrong number of parameters in call to TSvc.Pick` | works |
| C | **metaclass VARIABLE** — `mc: class of TSvc; TSel(mc.Pick)` | same error | works |

Same on `pinned` and on HEAD, so A and C never worked; they are not a
regression.

They are out of this ticket's scope — its defect, its repro and its corpus site
are all the B arm — but they are the same concept reached by two more spellings,
which is the sibling check `normalise-dont-special-case.md` asks for before
closing. Filed as
[[bug-p-a-parenless-method-reference-handles-two-of-four-receiver-spellings]].

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.

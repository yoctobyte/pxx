# Bug: `var array[..] of AnsiString` parameter silently loses writes

- **Type:** bug — Track A (compiler internals, param marshalling / codegen)
- **Status:** done
- **Opened:** 2026-07-01
- **Found by:** implementing `extern`/`global` directives for the `.asm` frontend
  (feature-asm-source-frontend task #4) — a helper procedure took `var externName:
  TAsmExternNames` (`array[0..255] of AnsiString`) and wrote `externName[i] :=
  nameTok`; the caller read back an empty string at that index immediately after
  the call returned. Worked around by inlining the write into the caller (no
  by-ref array-of-managed-type param needed); the underlying bug is still open.

## Repro (minimal, isolated from the asm frontend)

```pascal
program ArrParamBug;
type TArr = array[0..3] of AnsiString;
procedure Fill(var a: TArr; idx: Integer; const v: AnsiString);
begin
  a[idx] := v;
end;
var x: TArr;
begin
  x[0] := 'unset';
  Fill(x, 0, 'hello');
  writeln('x[0]=[', x[0], ']');   { FPC: hello.  pxx self-hosted: unset. }
end.
```

- **FPC-built `compiler/compiler`:** prints `x[0]=[hello]` (correct).
- **pxx-self-hosted `compiler/pascal26`:** prints `x[0]=[unset]` (the write was
  silently lost — no error, no crash, just wrong data).

A parallel repro with `array[0..3] of Integer` (scalar element type, otherwise
identical shape — `var` array param, indexed write via a local `idx`) works
correctly on **both** builds. So the bug is specific to the array's **element
type being managed (AnsiString)**, not `var`-array-params in general.

## Suspected shape

Looks like the same family as other "managed-type write silently misses its real
target" bugs already fixed this cycle (frozen-string Result reentrancy, byvalue
managed-record field aliasing caller) — a managed-type assignment codegen path
that copies/releases through some fixed or by-value notion of "the array" instead
of the `var` parameter's actual referent address. Needs an IR/codegen-level
investigation of how `a[idx] := v` lowers when `a` is a `var` array-of-AnsiString
parameter (vs. a local array, where it presumably works — untested here but
likely fine given how pervasive plain local string-array usage is elsewhere).

## Also checked while in there

- `const array[..] of AnsiString` (read-only) — **confirmed fine**, isolated
  repro (a function reading `a[idx]` through a `const` array-of-AnsiString
  param and returning it) prints correctly on pxx self-hosted. So the bug is
  specifically `var` (write-back), not array-of-AnsiString params in general —
  `AsmExternLookup` (which only reads, `const`) did not need to change; only
  `AsmParseExternLine` (which wrote an element) did.
- Whether `array of AnsiString` (open-array form, not a named fixed-size type)
  has the *same* bug or a different one — the first workaround attempt in the asm
  frontend used open-array params and hit the identical symptom before the named
  fixed-array-type rewrite (which did NOT fix it — the bug survived both forms),
  so open vs. named fixed array is not the variable; managed element type is.

## Impact

Silent data corruption, not a compile error or crash — the dangerous kind. Only
known trigger so far is this specific shape (`var`/writeback through an
AnsiString-element array parameter); unclear how many existing call sites in
`lib/**` or user code could be hitting this unnoticed. Worth a `grep -rn "var.*:
array\[" compiler/*.pas lib/**/*.pas` sweep for AnsiString-element array `var`
params once someone picks this up, to gauge exposure.

## Not blocking

Worked around in `compiler/asmfront.inc` (inlined the extern-table write into
`ParseAsmProgram` directly, no by-ref array-of-AnsiString param). The `.asm`
frontend's `extern`/`global` work does not depend on this bug being fixed.

## Fixed (2026-07-01, Track A, commit 6cf56ea6, pinned v116)

Root cause (found via a dispatched research agent, verified by direct code
reading + disassembly of the repro's own emitted machine code):
`compiler/ir_codegen.inc`'s `IR_LEA` codegen, `InLValueWrite` branch (around
line 1985 pre-fix). An array symbol stores its ELEMENT type in `.TypeKind`
(same field a plain scalar variable stores its OWN type in) — a fact the
sibling branch two lines up (scalar `var s: AnsiString` writeback, ~line
1978) already correctly accounts for with `and not Syms[symIdx].IsArray`.
The next branch down did not: it matched `TypeKind = tyAnsiString` alone,
so a `var`/`out` array-of-AnsiString parameter (element type tyAnsiString,
but `IsArray = True`) wrongly fell into the "genuinely local scalar
AnsiString variable" code path and got `lea rax,[rbp+off]` (the address of
its OWN forwarded-pointer parameter slot) instead of `mov rax,[rbp+off]`
(dereference the slot to reach the caller's real array) — the same `mov`
every other var-array-param element type (Integer, records, nested
dynarrays — none of which have `TypeKind = tyAnsiString`) already correctly
took via the pre-existing fallback default one branch further down.

Confirmed via disassembly of the repro's `Fill` procedure: the write landed
at `&(Fill's own param slot) + idx*8`, which for `idx=0` collides exactly
with the slot holding the forwarded pointer itself — so the "old value"
read before the managed-string release step misread `&x` (the caller's
array address) as a string handle, and called `AnsiStrRelease` on `[&x -
0x10]` — decrementing (and potentially freeing) an arbitrary qword 16 bytes
before the caller's actual array, not the intended previous element value.
This session's repro happened not to crash (that memory didn't read as a
refcount of 1), but it's a genuine wrong-address ARC-decrement / possible
spurious-free hazard, not merely a silently-dropped write — confirmed worse
than the ticket's original "silent data corruption" framing suggested.

**Fix**: added the same `and not Syms[symIdx].IsArray` guard to the
`TypeKind = tyAnsiString` disjunct, mirroring the sibling scalar branch.
Case-analysis confirmed this doesn't disturb the adjacent legitimate `lea`
path for a local (non-parameter) dynamic array of any element type — that
one is gated by a separate `IsArray and ArrLen = -1` disjunct that was
already correctly unconditional on element type, and by-ref named-dynamic-
array params are peeled off even earlier (their own dedicated branch,
`ArrLen = -1` + `IsRef`), so neither path is affected by narrowing only the
`TypeKind = tyAnsiString` disjunct.

**Scope, confirmed empirically**: both the fixed-size named-type form (`var
a: TArr`) and the inline open-array form (`var a: array of AnsiString`) hit
the identical broken code path (both get the `ArrLen` sentinel from
`AllocParam`, neither is `-1`) and both are fixed by this one guard. Element
types other than `tyAnsiString` (records, nested dynarrays) were confirmed
by code reading to never reach this branch at all (their `.TypeKind` is
never `tyAnsiString`), so this bug's scope was already narrowly
AnsiString-element-specific, as the original ticket suspected — not a
broader "managed array element" class.

**Verified**: fixed + open-array shapes, index > 0 (rules out an
idx=0-coincidence-only fix), a scalar var AnsiString param (confirms the
sibling branch stayed correct), a const array-of-AnsiString read path
(confirms unaffected), and a 5000-iteration same-slot writeback loop (RSS
stable, correct final value — guards the ARC release/retain correctness,
not just a single write landing right). Matches FPC output exactly. New
`test/test_var_array_of_string.pas` in `make test-core`. Full `make test`
green, self-host bootstrap byte-identical. x64-only fix
(`compiler/ir_codegen.inc` is the x86-64 backend specifically; the other
targets have their own separate `ir_codegen_*.inc` files, architecturally
unaffected) — host-only stabilize/pin sufficient, no cross-target retest
needed for this change.

## Log
- 2026-07-01 — resolved, commit 6cf56ea6.

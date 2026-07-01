# Bug: `var array[..] of AnsiString` parameter silently loses writes

- **Type:** bug — Track A (compiler internals, param marshalling / codegen)
- **Status:** backlog
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

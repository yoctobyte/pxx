# By-value record param with a managed field aliases the caller (mutations leak)

- **Type:** bug (ABI / param passing — correctness) — Track A
- **Status:** done — fixed pin v135, 2026-07-01
- **Severity:** high — silent caller-data corruption; records with a `string`
  (or other managed) field are everywhere, and a plain (non-`var`) parameter is
  expected to be an independent copy.
- **Opened:** 2026-06-30 (Track B latent-bug sweep, against stable v97)

## Symptom

A record passed **by value** (plain parameter, no `var` / `const`) is supposed to
be a copy: writes to it inside the callee must not affect the caller. That holds
for a plain record, but a record that contains a **managed field** (e.g.
`string`) is passed by reference instead — and *every* field write (managed
**and** plain) leaks back to the caller:

```pascal
type
  TPlain = record a, b: integer; end;
  TMan   = record a: integer; s: string; end;
procedure modPlain(r: TPlain); begin r.a := 999; r.b := 888; end;
procedure modMan(r: TMan);     begin r.a := 999; r.s := 'changed'; end;
var p: TPlain; m: TMan;
begin
  p.a := 1; p.b := 2; modPlain(p);
  writeln(p.a, ',', p.b);     { 1,2      — correct, copied }
  m.a := 1; m.s := 'orig';  modMan(m);
  writeln(m.a, ',', m.s);     { 999,changed — WRONG, want 1,orig }
end.
```

## Isolation (stable v97)

| Record | by-value param mutated | caller after | correct? |
| --- | --- | --- | --- |
| `record a,b: integer` (plain) | `r.a:=999; r.b:=888` | `1,2` | yes (copied) |
| `record a:integer; s:string` (managed) | `r.a:=999; r.s:='changed'` | `999,changed` | **no — aliased** |

Both the integer field and the string field leak, so the whole record is being
passed by reference (no by-value copy is materialised) once it contains a managed
field. Note: whole-record **assignment** (`r2 := r1`) does copy correctly even
with a string field — only the value-parameter path is wrong.

Distinct from [[design-record-copy-dynarray-field-semantics]] (an *assignment*
COW question, which states parameter passing was fine as of 2026-06-22) — this is
a parameter-passing correctness regression/gap for managed-field records.

## Likely cause

The call ABI takes the by-reference fast path for any record carrying a managed
field (presumably to let the callee run ARC on the managed members) but then
omits making a private copy the callee can mutate — so the callee writes through
to the caller's storage. A non-`var` record param needs a callee-local copy
(value semantics) with proper ARC retain of managed members, the same copy the
assignment path already performs.

## Acceptance

- `modMan` above leaves the caller's `m` as `1,orig`.
- Managed members are correctly retained/released across the call (no leak, no
  double-free); `const`/`var` record params keep their existing (intended)
  semantics.
- Regression test (`test/test_byvalue_record_managed_copy.pas`) wired into
  `make test`; self-host stays byte-identical; cross targets consistent.

## Fixed (2026-07-01, pin v135)

Root cause matched the "Likely cause" guess closely, with one refinement:
it's not that the by-ref fast path is taken "for any record carrying a
managed field" specifically — it's taken for ANY record over 8 bytes
(managed or not; `compiler/parser.inc`'s `RecSize(ptypesRec[i]) > 8` check,
an ABI efficiency decision to avoid a large by-value copy through registers/
stack). The actual gap was in `compiler/ir.inc`'s `IRLowerCallArg`: the
by-ref-argument branch only forced a caller-side private copy
(`needTemp := True`) when the argument was NOT an lvalue (e.g. a function
result) — an lvalue argument (the common case, `modMan(m)`) was passed
straight through by address with no copy, so every write leaked back into
the caller regardless of managed content.

The fix needed a way to tell "by-ref because the user wrote `var`/`out`/
`const`" from "by-ref only because of the size-driven ABI promotion of an
originally plain param" — and that flag (`ProcParamExplicitByRef`) already
existed in the codebase (added earlier for a related lvalue-requirement
relaxation) but was never consulted at this call site. Now an lvalue
argument to a size-promoted plain param also gets the private-copy
treatment; genuine `var`/`out`/`const` params are untouched and keep their
correct aliasing/borrowing semantics.

Verified against real FPC output for plain/const/var/by-value-of-call-result
record params, both with and without a managed field, plus a non-managed
`>8`-byte record (bonus: this class of bug affected ANY large plain record,
not just managed ones — now fixed uniformly).
`test/test_byvalue_record_managed_copy.pas` added. Self-host byte-identical,
full `make test` green, all cross suites (i386/arm32/aarch64/riscv32) green.

Found and filed separately while cross-verifying: a pre-existing arm32-only
SIGSEGV in a specific two-call sequence (small ≤8-byte record call
immediately followed by a managed-record call) — confirmed present on the
pre-fix binary too, unrelated to this fix
([[bug-arm32-record-byvalue-over-4-bytes-abi-gap]]).

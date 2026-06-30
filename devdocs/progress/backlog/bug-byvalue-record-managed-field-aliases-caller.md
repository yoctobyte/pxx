# By-value record param with a managed field aliases the caller (mutations leak)

- **Type:** bug (ABI / param passing — correctness) — Track A
- **Status:** backlog
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

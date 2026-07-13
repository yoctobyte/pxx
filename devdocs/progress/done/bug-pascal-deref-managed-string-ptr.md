---
prio: 40
---

# `^string` — dereferencing a pointer to a managed string segfaults (all targets)

- **Type:** bug
- **Track:** A — core (managed-string deref lowering)
- **Status:** done
- **Found by:** writing the regression for [[bug-riscv32-string-literal-to-class-field]] — it
  is a SEPARATE defect that the test happened to also cover, and it reproduces on x86-64.

## Reproduction
```pascal
type PStr = ^string;
var s: string; p: PStr;
begin
  s := 'orig';
  p := @s;
  writeln(p^);        { SEGFAULT -- on the READ, before any store }
end.
```
Segfaults on x86-64 (so this is not a cross-target issue). Both `p^` as a value and
`p^ := ...` as a target are affected; the read already dies.

## Why it is probably shallow
A managed string variable's slot holds a HANDLE, so `@s` is the address of the handle slot
and `p^` must load the handle and then read through it — the same two steps a field access
does (and class/record/array element access all work: see
`test/test_managed_store_via_addr_b279.pas`). The deref path looks like it is treating the
slot address as if it were the handle, i.e. one indirection short.

Compare `AN_DEREF` lowering for tyAnsiString against `IR_FIELD` + `IR_LOAD_MEM`, which is the
working shape.

## Note on scope
`^string` is an unusual thing to write in Pascal — the managed type is already a reference —
so this has clearly never been exercised. It is filed because it is SILENT-crash rather than
a diagnostic: if the deref is not meant to be supported, it should be rejected at compile
time, not segfault.

## Gate
`make test` + self-host byte-identical.

## Log
- 2026-07-13 — resolved, commit pending.

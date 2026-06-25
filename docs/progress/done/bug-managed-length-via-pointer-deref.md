# bug: managed Length(ps^) / Length(rec.pf^) returns garbage (all targets)

- **Type:** bug (Track A — managed-string codegen)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-24 (found while fixing bug-cross-gate-masked-failures)
- **Severity:** low-medium (managed strings; loud — garbage/segfault).

## Symptom

Under managed strings (the default), `Length(ps^)` where `ps: ^string` returns
garbage on **every** target (x86-64 included):

```pascal
type PStr = ^string; var s: string; ps: PStr;
begin s := 'TRoot'; ps := @s; writeln(Length(s)); writeln(Length(ps^)); end.
{ x86-64: 5  500085772884   i386: 5  1869566548  — should be 5 5 }
```

Same for `Length(rec.pf^)`. Direct `Length(s)` is correct.

## Root cause

`Length`'s arg-lowering force-addresses any lvalue (`isRefArg :=
IsASTLValue(...)`). For `ps^` that yields the slot-pointer; the x86-64/cross
Length codegen's frozen else-path then does a single `mov rax,[rax]` and returns
the **handle** itself, never reading `[handle-8]`. The value read is the handle/
content (word-size-dependent: 8 bytes on x86-64, 4 on 32-bit), not the length.

## Attempted + reverted

Switching the managed deref to the value path (so it lowers to a tyAnsiString
handle and the Length `tyAnsiString` branch reads `[-8]`) made the first read
correct (5) but then **segfaulted** — the borrowed `ps^` handle gets treated as a
materialised temp / released, double-freeing `s`'s string. The managed-arg
ownership logic and the Length value-path need to agree that a deref result is
borrowed, not owned. Needs care.

## Note

`test_cross_frozen_strlen_deref` was repointed to `-uPXX_MANAGED_STRING` (frozen)
to stop exercising this broken managed path; the frozen path is correct. A managed
variant test should be added once this is fixed.

## Acceptance

Managed `Length(ps^)` / `Length(rec.pf^)` == direct `Length` on all targets; no
double-free.

## Resolution (2026-06-25)

Root cause was one level off from the original note: `@s` of a managed string
yields the **handle (heap data pointer) itself**, not `&slot` — the garbage
`500085772884` decodes to the bytes `'TRoot'`, i.e. the catch-all returned
`[handle]` (the string data) instead of `[handle-8]` (the length). So `ps` IS
the handle; `Length(ps^)` needs `test; [-8]` with **no** extra deref. The
attempted value-path double-free was a separate red herring; the AN_DEREF
managed-temp exclusion (ir.inc) already keeps the borrow correct.

Fix: lowering-only, in the `IRLowerAST` arg loop (`ir.inc`, beside the
dyn-array-call Length special-case). For `Length(<deref>)` where the deref's
type is `tyAnsiString`, lower the arg as the plain handle load of the pointer
operand, retagged `tyAnsiString` (`IRTk[value] := Ord(tyAnsiString)`). That is
the same node shape a managed-string *value* produces, so every backend's
existing `tyAnsiString` Length path (no extra deref → test → `[-8]`) serves it
with **zero codegen change**. Frozen `ps^` keeps `tyString` (untouched); managed
strings don't exist on ESP, so riscv32/xtensa never hit it.

Verified `5 5 5 2 2 OK` on x86-64 / i386 / aarch64 / arm32 (incl. a 1000-iter
loop = no double-free / leak). Gate: `make test` (self-host byte-identical) +
`test-i386 test-aarch64 test-arm32` + `cross-bootstrap` all green. New managed
regression test `test/test_managed_strlen_deref.pas` wired into all three cross
sections (cross-vs-x64 oracle + an absolute-output assertion). The pre-existing
`test_cross_frozen_strlen_deref` (frozen, `-uPXX_MANAGED_STRING`) stays.

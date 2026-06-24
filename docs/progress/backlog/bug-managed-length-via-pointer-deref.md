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

---
track: N
prio: 65
type: bug
---

# Every `print("literal")` reserved 8 MiB of BSS

- **Type:** bug (NilPy codegen, silent resource waste) — **Track N**
- **Found and FIXED:** 2026-08-01, while investigating why a new test's binary
  reported `bss=218114044B` where its neighbours reported ~8 KB.

## Measured

| program | BSS before | after |
| --- | --- | --- |
| `print(1)` | 8,296 B | 8,296 B |
| `print("x")` | **8,396,908 B** | 8,300 B |
| `print("x", "y")` | **16,785,524 B** | 8,308 B |
| `s = "x"` then `print(s)` | 8,308 B | 8,308 B |
| `test_nilpy_static_mixed_type_guard.npy` (13 literals) | **218,114,044 B** | 10,236 B |

Exactly **8 MiB per string literal passed directly to `print`**, linear in the
number of such arguments. Binding the literal to a variable first never cost
anything, and Pascal was entirely unaffected (`WriteLn('x')` → 9,484 B).

**Pre-existing, not a regression:** `stable_linux_amd64/default/pinned` produces
the identical 8,396,908 B for `print("x")`.

## Cause

`print`'s per-argument hidden temp took the ARGUMENT's own type kind:

```pascal
pargTk := IntToTypeKind(ASTTk[CurASTNode]);
pargTmp := AllocVar(PyHiddenName('parg'), pargTk);
```

A string LITERAL carries `tyString` — a FROZEN fixed-size string — and with no
explicit `string[N]` that slot was laid out at `STRING_CAP`, which is
`8388608` (8 MB, `compiler/defs.inc:43`). So each literal argument reserved an
8 MB frozen buffer purely to hold a value on its way to `WriteLn`.

Assigning to a variable avoided it because an assignment already widens
`tyString` to `tyAnsiString` (managed, a pointer) — the rule recorded in
`project_nilpy_ast_typing_and_string_kind_widen`. The temp simply never applied
it.

## Fix

Apply the same widening at the temp: `if pargTk = tyString then pargTk :=
tyAnsiString`. The temp only has to HOLD the value, and managed is a pointer.

## Severity, stated honestly

The BSS is a **reservation**, so resident cost was near zero — measured RSS 352
KB for `print("x")` and 824 KB for the 218 MB-BSS binary. This was never an
out-of-memory bug on 64-bit.

It still mattered: 218 MB of virtual reservation for a trivial program is a lot
of address space on the **32-bit targets** (i386, arm32, riscv32), it inflates
every ELF's memory image, and it makes `bss=` in the build line useless as a
signal — which is precisely why the anomaly went unnoticed until a test happened
to have thirteen literals in it.

## Verified

`print("x")` 8,396,908 → 8,300 B; the 13-literal test 218,114,044 → 10,236 B;
output unchanged in every case. All nine `test-nilpy` assertions added today pass
via make's own expansion, `testmgr --tier quick` GREEN, self-host fixedpoint
byte-identical, `make bootstrap` (FPC seed) exit 0. Existing `.npy` tests
re-checked and all now sit at ~8.3–8.7 KB.

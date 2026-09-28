---
track: A
prio: 50
type: bug
blocked-by: []
status: done
found-by: frankd-90 (2026-09-28)
tags: [pascal, cdecl, diagnostics, cross-target]
summary: "`--warn-ignored-directives` reported `cdecl` as ignored on every target except x86-64, including i386, aarch64 and arm32, where cdecl selects the C convention and is load-bearing: removing it makes the compiler refuse `f := @Twice` into a cdecl procvar, and before that refusal existed the program printed 0.0 instead of 42.0. The warning now asks TargetSelectsCdecl, the same list the refusal asks, and on riscv32 says why there it really is ignored."
owner: ""
---

# `--warn-ignored-directives` calls a load-bearing `cdecl` ignored

The warning asked "is this x86-64?". So on i386, aarch64 and arm32 it told the
reader that a `cdecl` was documentation only, while the same compiler
refuses the program once that `cdecl` is removed (7d105ec21c), and computed a
wrong value before the refusal existed. Following the warning's advice broke
the program.

`TargetSelectsCdecl` (symtab.inc) is the one list of targets where cdecl
selects a convention: x86-64, aarch64, arm32 and i386. The warning now asks it.
Where cdecl is really ignored, the text says why:

- riscv32: the ordinary convention is already the C one.
- other targets: there is no C-convention prologue to select.

## Measured (2026-09-28, fixedpoint 9aa9386d03a7)

`test/test_cdecl_warning_only_where_ignored.pas`, with
`--warn-ignored-directives`:

| target  | cdecl warnings | output |
|---------|----------------|--------|
| x86-64  | 0              | 42.0   |
| i386    | 0              | 42.0   |
| aarch64 | 0              | 42.0   |
| arm32   | 0              | 42.0   |
| riscv32 | 1              | 42.0   |

- The pinned v449 warns on i386.
- xtensa and wasm32 warn once, then refuse the file for an existing, separate
  reason: a Pascal-bodied cdecl routine with a by-value float parameter is not
  C-callable there yet (feature-cdecl-bodied-sysv-prologue). So they have no
  row.
- `test_warn_ignored_directives.pas` still counts 5 on x86-64.

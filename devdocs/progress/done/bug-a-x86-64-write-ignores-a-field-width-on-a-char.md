---
track: A
prio: 50
type: bug
blocked-by: []
owner: claude-A
status: done
---

# x86-64 `write(c:width)` drops the field width on a Char

- **Type:** bug (silent wrong output) — **Track A**
- **Found:** 2026-08-10 by an FPC differential over the Write-formatting surface.
- **Pre-existing:** identical on `pinned`.

```pascal
var c: Char;
begin c := 'q'; WriteLn('[', c:5, '][', 'a':3, ']'); end.
```

| | |
| --- | --- |
| FPC | `[    q][  a]` |
| pxx x86-64 | **`[q][a]`** |
| pxx aarch64 / arm32 / i386 / riscv32 | `[    q][  a]` — correct |

**x86-64, the default target, was the only backend that got it wrong.** The
other four all pad; riscv32 even has a dedicated `PXXWriteCharW(c, wid)` builtin
for it. `ir_codegen.inc`'s `tyChar` arm simply called `EmitwriteChar` and never
looked at `wid`, which was sitting right there in scope — the signed/unsigned
integer arms immediately below it both consume it.

A **one-character literal is a Char** in Pascal, so `write('a':3)` takes the same
path. That is why `write('ab':3)` looked fine and `'a':3` did not — the usual
two-spellings-of-one-thing split, and the reason this reads as "sometimes
works".

Every column-aligned report written with `write(ch:n)` came out ragged, with no
diagnostic.

## Fixed

Mirrored the aarch64 arm: pad `wid-1` spaces first, preserving the character
across the write syscall (which clobbers `rax`).

## Verified

`test/test_write_char_field_width.pas`, asserted in the Makefile — Char
variable, one-char literal, `#65`, `Chr(66)`, two padded chars in one `Write`,
and `width <= 1` which must NOT pad. Diffed against `fpc -O1` and against all
five backends, which now agree with each other and with FPC.

`tools/gate.sh quick` GREEN, self-host fixedpoint converged in 1 round.

## Found alongside, filed separately

A **variable** field width (`write(x:w)`) is a different, still-open gap —
[[bug-a-a-variable-field-width-is-refused-for-strings-and-needs-an-rtl-unit]].

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.

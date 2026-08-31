---
slug: bug-a-xtensa-has-no-q-plus-overflow-check-emitter-so-it-wraps-silently
track: A+S
prio: 30
type: bug
blocked-by: []
status: backlog
found: 2026-09-01
found-by: frankA
owner: unassigned
summary: "xtensa is the ONE backend with no {$Q+} overflow-check emitter: it is the only target absent from the `FindProc('PXXOverflow')` grep. So `{$Q+}` compiles clean there and SILENTLY WRAPS -- 2147483647+1 stores -2147483648 where the other five raise Runtime error 215. Quieter than the arm32/riscv32 bug it was found beside, which at least failed loudly at compile time. Same shape as the still-open xtensa div-by-zero gap; they are one job."
---

# xtensa has no `{$Q+}` overflow-check emitter, so it wraps silently

Found 2026-09-01 while fixing
[[bug-a-q-plus-overflow-checking-has-no-runtime-helper-on-arm32-and-riscv32]],
which is a different defect with the same trigger. That one was a switch LEAK
and is fixed. This one is a MISSING FEATURE and is not.

## The fact

```pascal
program qC; {$Q+}
var a, b, c: Integer;
begin a := 2147483647; b := 1; WriteLn('before'); c := a + b; WriteLn('after c=', c); end.
```

| target | result |
| --- | --- |
| x86-64, i386, aarch64, arm32, riscv32 | `Runtime error 215 (arithmetic overflow)` |
| **xtensa** | `after c=-2147483648` — **no trap** |

## Why it is the quiet one

The arm32/riscv32 defect it was found beside **failed to compile**. This one
compiles clean and produces a wrong value, which is the failure mode CLAUDE.md
names as the expensive kind. Anyone checking "does `{$Q+}` work on my target"
by whether it builds gets a yes.

## The cause is not subtle — it is simply absent

```
$ grep -rn "'PXXOverflow'" compiler/*.inc
ir_codegen_arm32.inc  ir_codegen_riscv32.inc  ir_codegen386.inc (x2)
ir_codegen.inc (x2)   ir_codegen_aarch64.inc
```

Six sites, five backends, **no xtensa**. There is no `EmitOvfCheckXtensa`, so
`IRIVal[node] = 1` (the `{$Q+}` marker on the binop) has nothing to dispatch to
and is dropped.

## This is the same job as the div-by-zero gap

[[bug-a-the-div-by-zero-check-is-still-missing-on-xtensa]] is the identical
shape — the last target without a pre-divide zero check, left out for the same
reasons — and its write-up already lists the four things that make xtensa a
genuinely different job rather than a sixth copy of the edit: it cannot be RUN
under the bare profile, its branches carry only an 8-bit displacement, the
windowed ABI rotates the register window on a call, and there are two shapes
depending on `XtensaSoftDivide`. All four apply here. **Take them together.**

The trap call itself is the easy half: `PXXOverflow` takes no arguments and
never returns, and hosted xtensa CAN be run (`qemu-xtensa`, `--platform=posix`),
which is how the table above was measured — so unlike the div-zero ticket's
bare-profile problem, this one has a working oracle today.

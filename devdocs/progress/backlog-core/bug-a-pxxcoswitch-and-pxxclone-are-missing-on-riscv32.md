---
slug: bug-a-pxxcoswitch-and-pxxclone-are-missing-on-riscv32
track: A
type: bug
prio: 25
status: backlog
found: 2026-08-31
found-by: frank-rust
owner: unassigned
blocked-by: []
summary: "`__pxxcoswitch(@a, @b)` compiles for x86-64 and arm32 and gives `pascal26: error: target riscv32: unsupported node in IR codegen: coswitch` on riscv32; `__pxxclone` has the same missing arm. Compile-time error, not a wrong answer. Found while auditing what else riscv32 lacked after adding IR_RTTI_REG/IR_RESOURCES — the other four absent node kinds are all unreachable on riscv32, these two are not."
---

# `__pxxcoswitch` and `__pxxclone` have no riscv32 arm

`compiler/ir_codegen_riscv32.inc` handles 58 IR node kinds; aarch64 handles 65.
Six of the seven-way difference are `IR_CLONE`, `IR_COSWITCH`, `IR_IMTADDR`,
`IR_IO_LOCK`, `IR_IO_UNLOCK`, `IR_MULHI`. (The seventh, `IR_WRITELN`, was a
false positive — it is the trailing label of `IR_WRITE, IR_WRITELN:`.)

**Four of the six cannot be reached on riscv32**, so they are not bugs:

- `IR_MULHI` — `ir.inc:7781` errors at the emission site for any non-64-bit
  target and points at `MulHiU64` in lib/rtl.
- `IR_IO_LOCK` / `IR_IO_UNLOCK` — `ir.inc:13213` gates them to
  x86-64/i386/aarch64/arm32 under `--threadsafe`.
- `IR_IMTADDR` — no emitter anywhere in the frontend, and interface dispatch
  through a `TInterfacedObject` runs correctly on riscv32 today (verified).

**Two are reachable.** `AN_COSWITCH` (`pasparser_expr.inc:4132`,
`pasparser_stmt.inc:5056`, `pyparser.inc:46140`) and `AN_CLONE`
(`pasparser_expr.inc:4170`, `pyparser.inc:46178`) are ungated builtins.

## Repro

```pascal
program cosw;
var a, b: Pointer;
begin
  a := nil; b := nil;
  __pxxcoswitch(@a, @b);
  WriteLn('back');
end.
```

```
$ pascal26 cosw.pas cn                     # ok
$ pascal26 --target=arm32 cosw.pas ca      # ok
$ pascal26 --target=riscv32 cosw.pas cr
pascal26:7: error: target riscv32: unsupported node in IR codegen: coswitch
```

## Suspected site

`compiler/ir_codegen_riscv32.inc`. Donor arms: `ir_codegen_arm32.inc` handles
both, and it is the closer model than aarch64 — same 32-bit pointer width, same
`IR_ARG` chain shape (`ir.inc:7692` for coswitch, `ir.inc:7711` for clone).
`IR_CLONE`'s comment names the SysV arg regs, so the register mapping is the
part that has to be re-derived for the RISC-V calling convention rather than
copied.

Low priority: both are low-level builtins with no in-tree riscv32 caller. The
failure is loud and at compile time.

---

## `palthread.pas` landmine — read this before you lift the `__pxxclone` guard

Found by frank-coordinator grepping for the sibling of the `PalBackendMmapAnon`
`MAP_ANONYMOUS` fix (`97e96fc1b`); scope corrected by frankS; the flag value
below is measured by frankA rather than cited.

**Not a bug today.** `lib/rtl/palthread.pas` defines `MAP_ANON_PRIV = $22` at
`:84`, used at `:161` to mmap every thread stack. That constant sits **outside**
the arch split, which starts at `:87`, while the syscall numbers sit **inside**
it — and both xtensa and riscv32 fall to the `{$else}` at `:120`, where
`SYS_mmap = -1` and the `__pxxclone` compile-error fires first. So nothing is
silently wrong right now.

**It becomes wrong the moment this ticket lands**, because lifting the guard
removes the thing that is currently saving it.

**The two targets are NOT symmetric — this is the part to get right:**

| | `SYS_mmap` | `MAP_PRIVATE\|MAP_ANONYMOUS` |
| --- | --- | --- |
| riscv32 | **222** (generic ABI), placeholder is `-1` | **`$22` = 34 — already correct**, same as x86-64/i386/aarch64/arm |
| xtensa | **80** (its own numbering; generic 222 is `Unknown syscall 222`) | **`$802` = 2050** — the sole outlier |

So: **when moving `MAP_ANON_PRIV` inside the arch split, xtensa takes `$802` and
every other arch takes `$22`** (frankS's wording, and the reason for it is that
a note grouping the two targets invites someone to "fix" riscv32's already-correct
`$22` to `$802` and reproduce the EBADF that `97e96fc1b` just removed).
riscv32 needs the syscall block only; xtensa needs the syscall block **and** the
flags constant.

**`$800` is MEASURED, not read off a table or taken from a comment.** Under
`qemu-xtensa -strace`, mmap2 with flags `$800` alone is decoded by qemu as
`MAP_ANONYMOUS` and returns EINVAL (no `MAP_PRIVATE`/`MAP_SHARED`); `$802` is
decoded as `MAP_PRIVATE|MAP_ANONYMOUS` and maps; `$22` is decoded as
`MAP_PRIVATE|0x20` — `0x20` is not a named flag on this target — and returns
EBADF, mapping fd `-1`. That is qemu's own flag decoder naming the bit,
independent of `builtinheap.pas:971`'s comment, which had been the only source.

**Scope of that measurement (frankS):** qemu's decoder is qemu's, not the
kernel's — but for this claim qemu *is* the right authority rather than a weaker
one, because hosted xtensa runs under qemu-user, so it is the execution target
for the profile where `PalBackendMmapAnon` and the thread-stack mmap actually
run. Read it as **measured under qemu-xtensa 10.2.1, the execution target for
the hosted profile** — not as a claim about silicon. The bare/ESP profile never
reaches mmap, so nothing there depends on it.

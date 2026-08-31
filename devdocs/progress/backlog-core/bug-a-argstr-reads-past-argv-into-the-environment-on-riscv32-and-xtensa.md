---
slug: bug-a-argstr-reads-past-argv-into-the-environment-on-riscv32-and-xtensa
track: A+S
prio: 45
type: bug
found: 2026-08-30
found-by: frankS
owner: unassigned
---

# ArgStr reads past argv into the environment on riscv32 and xtensa

`ArgStr(i, s)` / `ParamStr(i)` with `i >= ParamCount+1` returns an ENVIRONMENT
STRING instead of an empty one on both 32-bit generic backends. x86-64 defends
against exactly this and says so:

```pascal
{ Bounds check: out-of-range index (>= argc, or negative) publishes nil (empty
  string) instead of dereferencing a bad argv slot. argc is at [initial_rsp]. }
  'mov rcx, [rcx]',      { rcx = argc }
  'cmp rax, rcx'
```

riscv32 has no such check, and its comment records the gap as known:

> `rv32_lw(reg_a0, reg_a0, 0);  { argv[index] (or junk past envp for a huge
> index — Pascal callers pass 0..ParamCount) }`

## Measured

`test_arm32_arg_runtime` run with NO arguments (it does `ArgStr(2, fixed)`):

| target | output |
| --- | --- |
| x86-64 (oracle) | `0\n\n\n` |
| riscv32 | `0\n\nLESSOPEN=\| /usr/bin/lesspipe %s\n` |
| xtensa (both ABIs) | `0\n\nLESSOPEN=\| /usr/bin/lesspipe %s\n` |

The stack at entry is `[argc][argv0..][NULL][envp0..]`, so with `argc = 1`,
`argv[2]` **is** `envp[0]`. Both backends compute the slot correctly and simply
do not stop at the end of the array.

## Severity: it is a silent wrong value, and it reads memory the program did not ask for

Not a crash. A user variable quietly receives an environment string, which is
the "plausible wrong value far from the cause" shape — and the value is
attacker-influenceable process state rather than garbage, so a program that
prints or logs a `ParamStr` past the end discloses its environment. That is why
this is p45 and not p20 despite `Pascal callers pass 0..ParamCount` being true
of careful code.

## Provenance — NOT introduced by the xtensa -55 work

xtensa reached this only by gaining the `tkArgCount`/`tkArgStr` arms at all
(`feature-a-xtensa-the-last-five-builtins-and-the-entry-stub-that-blocks-one`);
before that the program did not compile. **riscv32 has behaved this way for as
long as it has had the arm**, with the identical byte-for-byte output, and was
already a DIFF in the cross differential. The xtensa port is faithful to
riscv32; both are unfaithful to x86-64.

Filed rather than folded into the -55 change under the standing rule that a
grant covers every arm of *that* defect and not an adjacent different one.

## Fix

Port x86-64's check to both backends: load `argc` from `[BSS_INITIAL_RSP]`,
compare the index unsigned against it, and on out-of-range publish an empty
result rather than dereferencing — nil handle for a managed destination, a
zero-length buffer for a frozen one. Both arms live in `ir_codegen_riscv32.inc`
and `ir_codegen_xtensa.inc`; nothing shared is involved.

Do BOTH backends in one change. This defect is already the "fixed on one target,
left on the others" pattern that this repo keeps paying for — see
`bug-a-riscv32-pc-relative-encoders-silently-truncate-xtensa-already-guards`
filed the same night for the identical shape one layer down.

## Gate

`make compiler/pascal26` to fixedpoint, then `test_arm32_arg_runtime` run with
NO arguments against the x86-64 oracle on riscv32 and xtensa (both ABIs) — that
is the case the existing Makefile rows miss, because they all pass `alpha beta`
and stay in range. Add a no-argument row while fixing it.

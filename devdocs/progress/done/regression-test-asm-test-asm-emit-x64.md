---
prio: 70
track: A
---

> **Re-laned P -> A by the coordinator, 2026-08-30.** The guess came from the test
> SOURCE (`.pas` -> Track P). The failing **job** is `test-asm` — the x86-64 assembler /
> disassembly emitter — which is Track A whatever language it is fed. `test_asm_emit_x64`
> reports `undefined variable (EmitSyscall)` in **`compiler/x64enc.inc`**, and the only
> code commit touching that file in the range is `3a0ed43fb` (`--rtl-libc` converts the
> mnemonic-emitted syscalls). Nothing here is Pascal-frontend work.
>
> **Master is NOT broken.** Measured at HEAD by the coordinator: `make compiler/pascal26`
> exits 0, `converged after 2 round(s)`, fixedpoint `a3f0f9e3325f`. So this red is specific
> to the `test-asm` path, not a general build break — do not read it as one.

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 5 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_emit_x64.pas red at 31198d3674df (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:08:12Z
- **Test source:** test/test_asm_emit_x64.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_emit_x64.pas'` at 31198d3674dfe530aa0699f0eb775346a705410a

## Range
> **The named sha `31198d3674df` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `31198d3674df`, last good `7956dc38005e`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:193: error: undefined variable (EmitSyscall)
(tail)
pascal26:193: error: undefined variable (EmitSyscall)
  in: compiler/x64enc.inc
  near:    end else EmitSyscall >>>  end  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-08-30 — auto-closed by the seven watcher: `test-asm#src:test/test_asm_emit_x64.pas` passes at 08cbfa20a11d (tier native); it was red at 31198d3674df. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.


## RESOLVED 2026-08-30 (frankA) — self-inflicted, fixed in `658f4bea5`

Mine. `3a0ed43fb` routed `x64_syscall` through `EmitSyscall` so `--rtl-libc`
could reach the 17 mnemonic-spelled kernel entries. That worked for the compiler
and broke every other consumer of the file: this harness includes
`compiler/x64enc.inc` standalone, mocks the byte sink, and has no compiler
policy — so `EmitSyscall` was undefined at `x64enc.inc:193`.

The defect was a **layering inversion**, not a missing declaration: a byte
encoder had acquired an upward dependency on `RtlOverLibc`, `OptLevel` and the
call-site table. Adding a mock `EmitSyscall` to the harness would have turned it
green while leaving the encoder pointing the wrong way, so the next policy the
lowering needs breaks it again.

Fixed with a hook the encoder owns — `var X64SyscallHook: procedure = nil`, where
nil means "emit the two bytes". `compiler.pas` installs `@EmitSyscall`. No test
file changed.

Verified: this harness compiles and runs green, default codegen byte-identical
to a build of HEAD without the change, `--rtl-libc` unchanged (1 residual kernel
entry, div0 rc=200, SIGTERM rc=143).

**Note for the batch:** three of the five `test-asm` reds filed alongside this
one are NOT this defect — see
`regression-test-asm-test-asmcore-x64`. twatch files per source, so one cause
splits into several tickets; nothing stops two causes landing in one batch and
reading as one.

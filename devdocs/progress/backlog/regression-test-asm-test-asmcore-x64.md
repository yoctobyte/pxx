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

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asmcore_x64.pas red at 97c5fba007f9 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:28:11Z
- **Test source:** test/test_asmcore_x64.pas

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asmcore_x64.pas'` at 97c5fba007f96db42b4f4a5698512b66355632df

## Range
> **The named sha `97c5fba007f9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `97c5fba007f9`, last good `31198d3674df`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault (core dumped)
(tail)
ok: /tmp/testmgr-scratch-619868/test_asmcore_x64_26  [code=192336B  data=17244B  bss=93284B  procs=286]
Segmentation fault (core dumped)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## TRIAGED 2026-08-30 (frankA) — NOT the EmitSyscall defect; bisected to `75d2ba662`

Filed in the same batch as `regression-test-asm-test-asm-emit-x64` and
`regression-test-asm-test-x64enc`, which WERE caused by `3a0ed43fb`
(`x64enc.inc` gaining an `EmitSyscall` reference) and are fixed in `658f4bea5`.
**This one is a different commit.** Do not close it on that fix.

Bisected, two builds one commit apart, nothing else changed:

| build | `test_asmcore_x64` |
| --- | --- |
| `75d2ba662^` (= `eb340e59d`) | `all asmcore_x64 checks passed`, **exit 0** |
| `75d2ba662` (page-separate code from data) | **SIGSEGV, exit 139** |

### The asmcore case is an out-of-bounds write, not a failed assertion

Symbolised at `test_asmcore_x64.pas:191`, *after* that line's output appeared —
so it is temporary cleanup, not the statement itself:

```
lea    0x451fb8,%rax
mov    %rax,%rdi
xor    %rax,%rax
movabs $0xf0,%rcx        { 240 }
rep stos %al,(%rdi)      { SIGSEGV }
```

240 bytes zeroed from `0x451fb8`. The single `PT_LOAD` ends at **`0x451fc4`**
(`vaddr 0x400000` + `memsz 0x51fc4`), so **only 12 of the 240 bytes are mapped**.
`filesz` puts data ending at `0x43b35c`, so the object is in BSS and is the LAST
object in it: a BSS allocation ~228 bytes shorter than its own zero-init, at the
one place in the image where nothing absorbs the overrun.

Two candidate causes ruled out by measurement rather than argument:

- **not the rel8 patch bug** — 228 short jumps in that binary, **zero** with a
  target off an instruction boundary;
- **not the optimizer** — identical segfault at `-O0`, `-O1`, `-O2` and `-O3`.

### The hello/compiler cases are the padding reaching the disassembler

`test-asm` runs `-S` and asserts `! grep -q "^    db "`. The padding zeros
disassemble as runs of `add [rax], al` with one odd byte over: exactly **one
`db 00`, line 14704 of 14704** — the last line. The assertion is working; the
padding really is undisassemblable bytes inside the code segment.

That is a design call, not a bug: either the padding moves out of the
disassembled range, or the assertion exempts a trailing pad. `75d2ba662`'s own
argument that the padding is safe ("zero is `udf #0` on aarch64 and faults on
x86-64") is about a **stray jump** and is not in tension with this — disassembly
simply was not considered.

Owner: `compiler/elfwriter.inc` is b4's file. Diagnosis only from here; no edit
made.

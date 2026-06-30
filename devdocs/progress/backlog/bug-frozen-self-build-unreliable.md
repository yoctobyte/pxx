# Frozen-string compiler self-build (`bootstrap-frozen` / `stabilize-frozen`) is unreliable

- **Type:** bug (build/infra) — Track A
- **Status:** backlog
- **Opened:** 2026-06-30
- **Found by:** incidental, while working bug-frozen-string-result-global (the
  frozen self-build is the only thing that exercises frozen-string returns in the
  compiler itself, so it was used as a probe).

## Symptom

A frozen-string compiler self-build does not reliably reach a fixpoint:

```
stable_linux_amd64/default/pinned -uPXX_MANAGED_STRING compiler/compiler.pas /tmp/frz1   # ok
/tmp/frz1                          -uPXX_MANAGED_STRING compiler/compiler.pas /tmp/frz2   # FAILS
```

`frz1` builds fine, but `frz1` compiling the compiler again produces **no output
file** — sometimes a `Segmentation fault (core dumped)`, sometimes a silent exit
with no file, occasionally exit 0. Reproduced on **pristine master** (pinned
compiler, unmodified source), so it is **pre-existing and independent of any
in-flight frozen-string-return work**.

## Cause — narrowed (2026-06-30, measured)

**Not OOM, and not an oversized stack frame.** Measured under `/usr/bin/time -v`
with 8.8 GB free:

- Pinned compiler building frozen `frz1`: exit 0, **Max RSS 237 MB**.
- `frz1` building `frz2`: **SIGSEGV (139), Max RSS 2432 KB** — i.e. it dies in
  **early startup**, before allocating its working set (the ~490 MB BSS is
  reserved, not the issue; it never gets far enough to use it).
- Intermittent across runs (sometimes exit 0) → **ASLR-dependent**: a wild /
  uninitialised pointer or a prologue touching an unmapped page, not a
  deterministic miscompile.

Ruled out **oversized stack frame** (the FPC-seed class) directly: building the
compiler in frozen mode through the new `--max-stack-frame` warning shows the
largest frozen-mode frames are only ~196 KB (`PrepareDynamicData`/`32`) and
~131 KB (`IRVerify`, `IRDump`) — nothing close to the 8 MB stack. So `frz1`'s
crash is a genuine **frozen-mode startup bug** (a `frz1` produced by the *pinned*
compiler), most likely a frozen-string global/temp init or a wild pointer hit
during unit/global initialisation.

## Why it matters / why it's low-priority right now

- **Not in the gate.** `make test` is managed-only (`test-core test-debug-g
  lib-fpc-clean`); it does NOT do a frozen compiler self-build. So this does not
  block the daily loop. But `bootstrap-frozen` / `stabilize-frozen` /
  `test-frozen`-as-selfbuild are advertised targets and should work.
- It also means **the frozen self-build cannot currently be used as a
  byte-identical signal** when changing frozen-string codegen — a real gap for
  bug-frozen-string-result-global (which only frozen mode exercises in-compiler).

## ROOT CAUSE LOCATED (2026-06-30, gdb + disasm)

The fault is in **global zero-initialisation emitting garbage absolute addresses**.

`gdb` (ASLR off via `setarch -R`) stops with `SIGSEGV` at the entry-region init
code, `rbp = 0`, stack barely descended. The faulting instruction:

```
=> 0x646a95:  mov %al, 0xffffffffe9a777ff      ; 88 04 25 ff 77 a7 e9, with al = 0
```

i.e. `mov byte [0xe9a777ff], 0` — a zero-init byte store to **absolute address
0xe9a777ff (~3.9 GB)**, which is unmapped (the whole image is vaddr
0x400000 .. ~0x1da8b000, ~494 MB). Disassembling the surrounding init run shows a
sequence of `movabs $0,%rax ; mov [abs],%al` byte-zeroing stores whose target
addresses are **mostly garbage / out of range** (0xe9a777ff, 0x51c46743 = 1.37 GB,
0x2cbb4bdb = 750 MB, 0x2e3f54xx = 778 MB), interleaved with some in-range ones
(0x17fa7e0x ≈ 402 MB). So the global zero-init address computation is wrong in
**frozen mode** — the `mov [disp32], al` absolute encoding (`88 04 25 disp32`,
sign-extended 32-bit) is being handed bogus displacements. The crash is gated by
whether ASLR happens to map the first bad address (→ the observed intermittency).

This is a real frozen-mode **codegen** bug in the pinned compiler, not OOM and not
a stack-frame size issue. Next step is the global zero-init emit path:

- Find where global (BSS) zero-init emits `mov [abs], al` (the per-byte / length-
  word clear for frozen-string and other globals) — likely an `EmitGlobRef` /
  `EmitGlobalZeroInit` site. In frozen mode globals are 8 MB `STRING_CAP` slots, so
  cumulative BSS is ~490 MB; check for a 32-bit truncation/overflow or a
  signed/zero-extension bug in the offset→absolute-address computation, or a
  garbage offset for a specific global kind. The `88 04 25 disp32` form can only
  reach the low 2 GB as a sign-extended disp32 — but even the in-range targets are
  < 494 MB, so the bogus ones are a *miscomputation*, not just an encoding-range
  limit.

## To investigate

1. It crashes at **startup** (2.4 MB RSS), so run `frz1` under `gdb` on *any*
   trivial input (`frz1 -uPXX_MANAGED_STRING test/hello.pas /tmp/x`) and get the
   backtrace of the SIGSEGV — it faults before parsing, so the crash site is in
   runtime init / global-init / unit init, not the compile logic.
2. Suspect frozen-string **global initialisation**: frozen mode turns every
   compiler `string` global/temp into an 8 MB inline `STRING_CAP` buffer; a
   zero-init or length-word setup over that BSS, or a wild pointer in the init
   order, is a candidate. Cross-check against the frozen-string-return work
   (bug-frozen-string-result-global) — same value model, may share a root.
3. Because it is ASLR-dependent, run a few times / under `setarch -R` (disable
   ASLR) to make it deterministic for bisection.

## Acceptance

- `bootstrap-frozen` (or a `pinned -u… ×2 + cmp`) reaches a byte-identical
  fixpoint reliably, OR the memory requirement is understood + documented and the
  build is made to not silently produce a truncated/missing binary.

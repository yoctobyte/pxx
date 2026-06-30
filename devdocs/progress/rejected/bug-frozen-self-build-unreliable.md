## REJECTED (2026-06-30, user decision)

WON'T FIX. The compiler self-builds **managed (AnsiString)** by design — that is
the supported, stable path. A frozen-string compiler self-build
(`bootstrap-frozen` / `stabilize-frozen`) is **not a goal**, and we will not
retrofit the compiler with static-sized strings to make it work. The startup
crash characterised below is therefore moot. `make test` is managed-only and
unaffected. Closing.

---

# Frozen-string compiler self-build (`bootstrap-frozen` / `stabilize-frozen`) is unreliable

- **Type:** bug (build/infra) — Track A
- **Status:** REJECTED (2026-06-30) — frozen self-build is a non-goal (managed is the path)
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

## Narrowed (2026-06-30, gdb + disasm) — confirmed facts + open mechanism

`gdb` (ASLR off via `setarch -R`) stops with `SIGSEGV`, **`rbp = 0`**, stack
barely descended (`rsp` ~16 bytes below the top), garbage backtrace (frame #1
return slot = `0x4`). The fault PC and its instruction (gdb-decoded, authoritative
— it is the exact CPU fault address):

```
=> 0x646a95:  mov %al, 0xffffffffe9a777ff      ; bytes 88 04 25 ff 77 a7 e9
```

a byte store to **absolute 0xe9a777ff (~3.9 GB)**, unmapped (image is vaddr
0x400000 .. ~0x1da8b000, ~494 MB). 0x646a95 is inside the code region (code ends
~0x65fcef), near the end where the runtime/init is emitted.

**Two readings, not yet resolved — DON'T trust the first one (my initial guess):**

1. *(weaker)* a real emitted zero-init store with a miscomputed absolute address.
   **Against it:** the `mov [disp32], al` form (`88 04 25 disp32`) is emitted
   **nowhere** in the compiler source (`grep EmitB($88) ... $04 $25` is empty; all
   `88 04 25`-shaped emits are 64-bit `48 89 04 25` or `48 C7 04 25`). So this byte
   pattern is not something the backend deliberately emits as an absolute store.

2. *(stronger)* **stack / control-flow corruption at startup** — `rbp = 0`, a
   return-address slot holding `0x4`, and a nonsensical backtrace say execution
   reached 0x646a95 via a **wild call/return or jump** (into the middle of real
   instructions or into emitted data), and `88 04 25 ff 77 a7 e9` is just the bytes
   straddling that misaligned PC being executed as an instruction. This fits the
   ASLR-gated intermittency (whether the wild target / the bad store address is
   mapped decides crash vs. survive).

So the real bug is most likely a **startup control-flow / stack corruption in the
frozen-mode binary**, not a cleanly-emitted bad store. Frozen mode differs from
managed in the string value model (inline 8 MB `STRING_CAP` slots, frozen-string
returns via the shared global Result — see bug-frozen-string-result-global), any
of which could corrupt a return address during global/unit init.

## To investigate

0. **Single-step from the entry point** (`0x400078`) in gdb (`si`, watch `$pc`,
   `$rbp`, `$rsp`) until control first leaves the legit init path — that PC is the
   real culprit (a bad `call`/`ret`/`jmp`), not 0x646a95. Set `b *0x400078` then
   step. This is the decisive next step; the 0x646a95 store is a symptom.

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

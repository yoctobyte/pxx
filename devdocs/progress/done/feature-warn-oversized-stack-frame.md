# Warn on oversized stack locals / stack frames

- **Type:** feature (diagnostic / safety) — Track A
- **Status:** DONE (2026-06-30) — per-frame check landed; per-*var* precision deferred
- **Opened:** 2026-06-30
- **Found by:** the FPC cold-bootstrap segfault
  ([[project_fpc_seed_segfault_done]] / done ticket): `LoadFile` had an 8 MB
  `array[0..STRING_CAP-1] of Byte` **stack local** that overflowed the default
  8 MB process stack. Nothing flagged it — it only surfaced as a runtime SIGSEGV
  under a smaller stack (FPC). A compile-time size check would have caught it.

## Idea

Locals live on the stack (correct, by design) — but the stack is small and fixed
(~8 MB default for the whole call chain). A single large local, or a fat sum of
locals, silently risks overflow. The compiler already knows every routine's
`FrameSize` (and each local's size) at codegen, so it can warn when a frame or a
single local is unreasonably large.

Add a tunable threshold and a warning:

- `MAX_STACK_VAR_SIZE` (per single local) — default **64 KB**. Enough for typical
  on-stack scratch (line buffers, DMA-ish blocks); anything bigger almost always
  wants the heap (`GetMem`) or a global/BSS buffer.
- `MAX_STACK_FRAME_SIZE` (whole routine frame) — default higher, e.g. **256 KB–1 MB**.
- Emit a **warning** (not error) naming the routine, the offending local, and its
  size — e.g. `warning: local 'buf' is 8388608 bytes on the stack (> 65536);
  consider a global or heap buffer`. Promote to error under `-Werror` (already
  exists) or a dedicated strict flag. Optional `{$MAXSTACKFRAME n}` /
  `{$MAXSTACKVAR n}` directives + a CLI flag to tune per build.

## Where

- Per-local size: at `var`-section allocation (parser) or when finalising a
  routine's locals — each local's byte size is known from its type/array bounds.
- Per-frame: at routine codegen where `FrameSize` is final (e.g. the prologue
  patch site, `PatchProcPrologue`). Compare against the threshold, warn once.

## Will flag (known offenders to clean before shipping default-on)

- The just-fixed `LoadFile` buf (now global — clean).
- Cross backends: `LabelPositions`/`LabelFixupPos`/`LabelFixupTarget:
  array[0..MAX_IR-1] of Integer` (MAX_IR=131072 → **512 KB each**, ~1.5 MB/frame)
  in `ir_codegen_{riscv32,xtensa,aarch64}.inc` — noted in the FPC-seed done ticket.
  Move to globals (these routines are not re-entered) so the compiler's own frames
  pass the check.

## Acceptance

- A warning fires for a local/frame over the threshold, with a test that triggers
  it and one that stays silent.
- Threshold tunable via constant + directive/flag; `-Werror` promotes it.
- The compiler's own source compiles clean at the default threshold (i.e. the
  cross-backend big locals above are moved off the stack first), so the warning can
  default on without noise. Self-host byte-identical.

## Why it matters

- Catches the FPC-bootstrap class of bug at compile time instead of as a runtime
  SIGSEGV under a tighter stack.
- Aligns with keeping the compiler FPC-buildable (default stack) and with the
  general "big buffers don't belong on the stack" rule.
- Doubles as a portability guard for ESP/bare-metal targets, where stacks are tiny
  (KBs) — an oversized frame there is fatal, and the same check warns early.

## Landed (2026-06-30, Track A)

Two commits:
1. **Prep — `refactor(codegen): move label-fixup scratch arrays off the stack to
   globals`.** Every backend's `IREmitMachineCode*` declared
   `LabelPositions/LabelFixupPos/LabelFixupTarget` as `array[0..MAX_IR-1]` stack
   locals (512 KB each, ~1.5 MB/frame) — the biggest offenders the warning would
   flag. Only the active target's emit runs per compile, non-reentrant, so they
   are now a single shared global set (`defs.inc`). This is what lets the default
   threshold default ON without flagging the compiler's own frames.
2. **Feature — the warning itself.**
   - `MAX_STACK_FRAME_SIZE = 1048576` (1 MB) const + `MaxStackFrameSize` global
     (0 = off), reset in `PasReset`.
   - Per-frame check at `ParseSubroutine` right after `PatchProcPrologue`
     (`parser.inc`): `if (MaxStackFrameSize>0) and (FrameSize>MaxStackFrameSize)`
     → `WarnStackFrame(line, Procs[procIdx].Name, FrameSize, limit)`.
   - `WarnStackFrame` (`lexer.inc`) prints via `writeln` (byte counts format with
     no int->string helper, like `Error`); `-Werror` promotes to fatal.
   - Tunable: CLI `--max-stack-frame=N` (`=0` disables) and `{$MAXSTACKFRAME n}`
     directive (`name='off'` disables). New helpers `PasOptHasPrefix` /
     `PasOptionInt` in `lexer.inc`.
   - Test `test/test_warn_stack_frame.pas` + Makefile: a 2 MB local warns, a 256 B
     local stays silent, the program still runs (`1\n42`), `--max-stack-frame=0`
     silences, `-Werror` makes it fatal.

**Why 1 MB default (not the ticket's 256 KB):** after moving the label arrays,
the compiler's remaining big frames are the `MAX_EXTERNAL`-sized ELF arrays
(~192 KB) and `MAX_IR` Boolean scratch (~128 KB) — all under 1 MB, so the
compiler self-builds clean at 1 MB. 256 KB would have required moving those too;
1 MB still catches the motivating FPC-class bug (an 8 MB single local → 8 MB
frame) with zero false positives on our own source. Lower it per-project via the
flag/directive when targeting tiny (ESP/bare-metal) stacks.

**Gate:** managed self-host byte-identical; `make test` (incl. the new test) +
cross (i386/aarch64/arm32/riscv32) green; xtensa codegen untouched by the feature
(verified green in the prep commit's bare-metal qemu run).

## Deferred follow-up — per-LOCAL size warning (`MAX_STACK_VAR_SIZE`)

The "Idea" section also proposed a per-single-local knob (default 64 KB) that
names the specific offending local. Only the per-FRAME check landed (it satisfies
acceptance — "a warning fires for a local/frame over the threshold" — and catches
the FPC bug, since one 8 MB local makes an 8 MB frame). The per-var check is a
tighter, complementary diagnostic (flags a fat single local even when the whole
frame is under the frame limit) and needs the size check threaded through the
~5 local-alloc sites (`AllocVar`, the array/dynarray/string alloc paths in
`symtab.inc` + `parser.inc`) with the var's name/line. Small, self-contained,
low-risk — left as a follow-up to keep this landing focused. Not blocking.

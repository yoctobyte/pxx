# Cross-target language-feature parity (Intel + ARM)

- **Type:** feature
- **Status:** urgent
- **Owner:** —
- **Opened:** 2026-06-16 (user request: "cross targets next — new features AND old ones, incl object support; validate we don't overlook something")
- **Combines:** feature-async-language-surface — its remaining open items are
  folded in here as a sub-track (see "Async sub-track" below); that ticket keeps
  the async design detail.

## Target scope (decided 2026-06-17)

In scope **now** — the four Linux targets, in two families:

- **Intel:** x86-64, i386
- **ARM:** aarch64, arm32

**Deferred** until Intel + ARM parity is done **and tested**: the embedded
targets — **Xtensa** and **RISC-V (RV32)** / ESP32. They already self-host
codegen, but the language-feature port (classes, async I/O, external symbols, …)
is *not* chased on them in this arc. Reopen the ESP/embedded path
(feature-esp32-*) once x86-64/i386/aarch64/arm32 are at full parity. Rationale:
keep the audit bounded to the four hosted targets where QEMU oracles are cheap
and the byte-identical fixedpoint is already proven; embedded RAM/ABI
constraints are a separate concern, best handled after the feature set is settled.

## Motivation

The four Linux targets (x86-64 / i386 / aarch64 / arm32) all self-host
byte-identical, but **feature coverage is uneven** — a pile of capabilities only
work on x86-64. The cross suites quietly skip them, so the gaps are easy to
overlook. This ticket is the **audit + close-out**: enumerate every x86-64-only
feature, build a parity matrix, and bring the cross backends up to it — proving,
by making the cross suites run the *same* feature set, that nothing major was
missed.

## Known gaps (x86-64-only today)

1. **Classes / objects — the big one.** i386/aarch64/arm32 codegen errors with
   *"class instantiation not yet supported"*. Blocks: `T.Create`, fields/methods
   on instances, virtual dispatch (VMT), constructors/destructors, the
   `object` reference type (feature-object-reference-type), interfaces
   (feature-interfaces), method pointers (`of object`, already cross-ready in
   codegen — see feature-procedural-types), and all of LCL/GTK. **This is the
   gating item for real OOP on cross.**
2. **Async reactor / sockets / timers** — x86-64-only. The scheduler + CoSwitch
   + channels already run on all 4 targets; the epoll reactor, `asyncnet`, and
   `CoSleep` are gated on x86-64 syscall numbers. Cross needs per-arch numbers
   (note: aarch64/arm32 have `epoll_pwait`, not `epoll_wait`; socket syscall
   numbers differ; i386 may use `socketcall`) + the cross test wiring.
3. **External (dynamic) symbols** — the i386/arm32 ELF writer blocks them
   (*"external (dynamic) symbols not yet supported"*). C-library imports (libc,
   GTK, libm) are x86-64-only → networking-via-libc and the GUI are x86-64-only.
4. **Method-pointer data fixups** (`MethodFixups`) — i386/arm32 ELF writer
   blocks them; needed for class VMTs / streaming on cross.

## Async sub-track (folded in from feature-async-language-surface)

The async **language surface** is already shipped byte-identical on all four
targets: `; async;` directive + `await` marker, the stackful default, the
stackless state-machine backend (`; async; stackless;`), configurable small
coroutine stacks + overflow canary, scheduler/channels. So async is **not** a
cross gap at the language-surface level. What remains (open items inherited from
that ticket, now tracked here):

- **Async I/O on cross** — same as Known-gap #2 above (the epoll reactor /
  `asyncnet` / `CoSleep` are x86-64-only; need per-arch syscall numbers, incl.
  `epoll_pwait` on aarch64/arm32 and i386 `socketcall`). This is the real
  cross-parity item for async.
- Stackless v1 follow-ups (params via instance slots; a `Task`/`Future` for
  `await`-with-result) and the Nil-Python `async def`/`await` shim — feature
  depth, **not** target parity; do opportunistically, not gating.

See feature-async-language-surface for the locked spelling and transform detail.

## Plan

1. **Audit pass:** extend `docs/developer/feature-matrix.md` into a real
   per-target matrix (✓ / ✗ / partial for each feature × {x86-64, i386, aarch64,
   arm32}); each ✗ becomes a checklist item here. Grep the four backends for
   `not yet supported` / `not supported` to seed it.
2. **Classes on cross targets** (largest sub-arc — may split into its own
   ticket): instantiation (VMT init + ctor call), field/method access, virtual
   dispatch, constructors, the `MethodFixups` ELF path. Unblocks method pointers
   + objects + interfaces cross.
3. **Reactor/sockets/timers cross:** per-arch syscall numbers; run
   reactor/asyncecho/timer suites on i386/aarch64/arm32 under QEMU.
4. Re-run the whole suite per target; every feature that exists on x86-64 either
   runs identically on the cross targets or has an explicit, recorded reason it
   cannot.

## Acceptance

A committed per-target feature matrix with no unexplained ✗; classes + method
pointers + the async I/O stack run on i386/aarch64/arm32 (or carry a documented
structural reason); the cross test suites exercise the same feature set as
test-core; bootstrap + cross-bootstrap stay byte-identical.

## Log
- 2026-06-16 — opened. Seeded from the procedural-types/async arc, where method
  pointers and the reactor landed x86-64-only and surfaced the classes-on-cross
  gap as the dominant blocker.
- 2026-06-17 — **scoped + combined.** Target scope locked to Intel (x86-64,
  i386) + ARM (aarch64, arm32); Xtensa / RISC-V (ESP32) deferred until those four
  are at parity and tested. Folded feature-async-language-surface's open items in
  as the "Async sub-track" (the async surface itself is already shipped on all
  four targets; only the cross async-I/O reactor is a real parity gap). This is
  now the single umbrella for "finish all language features on the Intel + ARM
  targets." Next concrete step: the audit pass (per-target feature matrix) →
  classes-on-cross.
- 2026-06-17 — **audit pass done.** Built the per-target codegen parity matrix
  in `docs/developer/feature-matrix.md` (x86-64 / i386 / aarch64 / arm32),
  seeded by grepping the four backends + `elfwriter.inc` for
  `not yet supported` / `not supported`. Confirmed the dominant blocker:
  **class instantiation** hard-errors on all three cross targets
  (`386:1653`, `aarch64:1071`, `arm32:1235`), gating fields/methods/virtual
  dispatch/method-pointers/interfaces/GUI. Other cross ✗: external C calls,
  aggregate-valued fn results, `SetLength` on var-array param, ELF32
  dynamic-symbols + method-fixups (i386/arm32 only — the 64-bit writeELF already
  handles both, so aarch64 is blocked only at codegen), async I/O reactor
  syscalls, aarch64 Variant single/extended. Indirect-call param caps are a
  shared structural limit (—), out of scope. Each ✗ is a checklist item in the
  matrix. Next: classes-on-cross sub-arc, starting with instantiation.
- 2026-06-17 — **classes-on-cross core landed (byte-identical, all 4 targets).**
  Ported the x86-64 class machinery to i386 / aarch64 / arm32: instantiation
  (heap alloc + VMT pointer init at offset 0 + ctor call returning Self) and
  `IR_VIRTUAL_CALL` (load VMT from `[Self]`, call `[VMT + slot*8]`) in each
  backend's expr emitter + statement loop, following each arch's call ABI
  (i386 cdecl all-stack; aarch64 16-byte temp -> x0..x7; arm32 word-push ->
  r0..r3). The VMT/field layout was already target-independent (8-byte slots,
  field base 8), so no parser/layout change was needed. Enabled `MethodFixups`
  in `writeELF32` (i386/arm32; the 64-bit `writeELF` already did it) so VMT
  slots link. Also ported `IR_RTTI_REG`/`IR_RESOURCES` (sentinel address loads)
  and allowed `tyClass` stores-through-pointer. `test_inheritance_dispatch`
  (ctor/fields/non-virtual+virtual methods/properties/inheritance) +
  `test_field_chain` run byte-identical to x86-64 on all four under QEMU; wired
  into test-i386/-aarch64/-arm32. `make test` + `make cross-bootstrap` (all 3)
  byte-identical. Side fix: bumped `MAX_CODE` 4->8 MB — compiler.pas grew to
  procs=939 and its arm32 self-host code crossed 4 MB ('code overflow',
  pre-existing, broke arm32 cross-bootstrap); buffer-only, no emitted-byte
  change. **Remaining class sub-gaps** (next): method pointers on i386/arm32
  (32-bit Code/Data value DIFF; aarch64 already OK), metaclass / `class of` /
  RTTI streaming (a deeper store-through-ptr type), collections /
  dynarray-of-record (`setlen_dyn` / `dynunique` IR ops), interfaces (now
  unblocked). Then external C calls + ELF32 external symbols, then the async
  reactor.

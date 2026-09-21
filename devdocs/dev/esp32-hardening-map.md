# ESP32 hardening map — what is unhardened, and WHO CAN ANSWER IT

Measured 2026-09-21 by frankb-8e (Track N seat, working S) against pin v414
(`compiler/pascal26` sha256 `aeadb1754b80b622…`, pinned source `b109703344ea`).
Box: plexus. ESP-IDF **is** installed here (`~/esp/esp-idf`) and Espressif qemu
is present for **both** ISAs (`qemu-system-riscv32`, `qemu-system-xtensa`,
`esp_develop_9.2.2_20250817`).

**THE ORDERING AXIS IS WHO CAN ANSWER A ROW, NOT HOW BAD IT IS.** That is the
axis that decides where the owner's board time goes, and severity is not. Three
buckets:

- **[SRC]** — answerable by reading the tree. Free, and the bucket people forget.
- **[QEMU]** — answerable on this box today, no hardware.
- **[BOARD]** — genuinely needs silicon.

Every row says **what would move it between buckets**, so the map stays useful
as qemu coverage and compiler capability change. A row's bucket is a claim about
*today*, not about the nature of the thing.

## THIS LIST IS INCOMPLETE, AND ITS LENGTH IMPLIES NOTHING

**The number of rows below is not a count of what is wrong with ESP support**,
and this sentence deliberately does not say what that number is -- it was
written as "eleven" on the first draft and was wrong within the hour, by its
own author adding rows. A self-counting claim in a document that grows is a
baseline that cannot survive its own file. This was written in one sitting from
the interrupt surface outward; it was **not** produced by enumerating the ESP
surface and classifying all of it. Known unexamined areas
are named in the last section rather than left to look like absence. Read a
missing subsystem as *not yet looked at*, never as *clean*.

## A DENOMINATOR WARNING FOR ANY PER-FEATURE SRAM TABLE BUILT FROM THIS

Put this in such a table's own header, not in a footnote, because the header is
what the next reader is holding:

> Any per-feature SRAM delta on ESP is measured with the 64 KiB `EspArena`
> present (`builtinheap.pas`, `HEAP_ARENA = 65536`, unconditional under
> `{$ifdef PXX_ESP}`). It is 97.1% of an empty bare program's 67,464 B of
> `data+bss`. **So a column of small per-feature deltas is small for a reason
> that has nothing to do with the features in it** — they are being compared
> against a fixed 64 KiB floor. Do not read "this feature costs almost nothing"
> off such a column without saying the floor is there.

(The arena itself is
`feature-s-the-64-kib-esp-heap-arena-is-reserved-even-when-dce-proves-the-allocator-unreachable`,
p60, unblocked. See the caution recorded there before implementing its
predicate — DCE reporting DROPPED is not the same claim as "unreachable".)

---

# 1. INTERRUPTS — the owner's must-have

## 1.1 [SRC] A PXX `interrupt;` handler has never been entered by a trap, anywhere, on any instrument

**This is the headline row and it is not a board question.**

What IS verified, by me, by disassembly (`--emit-obj`, both ISAs, pin v414):

| | riscv32 (esp32c3) | xtensa Call0 (esp32s3) |
| --- | --- | --- |
| prologue saves | `t0`-`t6`, `a0`-`a7` (64 B) + `ra`/`s0` | `a2`-`a13` (48 B) + `a0`/`a15` |
| epilogue | symmetric restore | symmetric restore |
| returns via | `mret` (`30200073`) | `rfe` (`003000`) |
| section | `.iram1.text` | `.iram1.text` |

That is a correct raw trap routine. **It has never run.** Nothing in the tree
installs it, and nothing executes it: `test/test_esp_interrupt.pas` says so in
its own header and is explicit that it is a *structural* probe — the handler is
referenced behind a runtime-false guard so that it gets emitted, and is never
called, because calling an ISR directly would `mret`/`rfe` into nowhere.

**Why it cannot run: the install instruction is not expressible from Pascal.**
Measured, not read — I tried all three spellings:

    csrw mtvec, t0     -> asm: unknown symbol: mtvec
    csrw 0x305, t0     -> asm: unknown symbol: x305   (the asm lexer splits the hex literal)
    csrw 773, t0       -> EmitAsmRv32: unsupported instruction
    wsr a4, vecbase    -> asm: unknown symbol: vecbase   (xtensa, same gap)

`csrw` *parses* as a mnemonic; there is simply no encoding for it in
`EmitAsmRv32`. The only CSR write in the whole tree is `rv32_csrw_mstatus`
(`rv32enc.inc:161`), hardwired to `mstatus` for the interrupt-disable the
atomics use. So the address of a handler can be **obtained** and not
**installed** — `IR_PROCADDR` in `ir_codegen_riscv32.inc:1654` even documents
its own purpose as *"Needed for raw ISR install (mtvec) and @isr ->
esp_intr_alloc"*. The feature is complete at both ends and missing exactly one
instruction in the middle.

**WHAT WOULD MOVE IT:** a general `csrr`/`csrw` encoding in `EmitAsmRv32` (and
`wsr`/`rsr` on xtensa) moves this row **[SRC] -> [QEMU]** — at which point
vector install + a deliberate trap is a fixture that runs on this box. It never
becomes [BOARD]. Fixing the asm lexer's hex literal is a separate, smaller bug
and is worth doing regardless.

Filed: `feature-s-a-csr-write-is-not-expressible-from-pascal-so-no-raw-isr-can-be-installed` (p60).

**A design question this exposes, for Track U rather than for silicon:** an
`interrupt;` routine has no way to adjust the return address. For an
asynchronous interrupt that is correct. For a *synchronous* trap (`ecall`,
illegal instruction, a load fault) `mret` returns to the faulting instruction
and re-faults forever. So `interrupt;` as it stands is an *asynchronous-only*
facility, and nothing in its surface says so.

## 1.2 [SRC] `esp_intr_alloc` is NOT the install path for `interrupt;`, and the two tests disagree about which directive to use

`test_esp_isr_register.pas` registers with `iram;`. `test_esp_interrupt.pas`
uses `interrupt;`. **Both are right, for different mechanisms**, and nothing
states the rule:

- The IDF dispatcher calls an `esp_intr_alloc` handler **as an ordinary
  function** (`void(*)(void*)`). It must therefore be `iram;` — a normal
  routine with a normal return.
- An `interrupt;` routine returns via `mret`/`rfe`. **Registering one with
  `esp_intr_alloc` would return out of a normal call via a trap-return
  instruction.** That is not a diagnostic today; it compiles.

**WHAT WOULD MOVE IT:** this is a compiler-side refusal (reject
`@an_interrupt_proc` passed to an external, or at minimum warn) plus one
sentence of documentation. Stays [SRC]. Cheap, and it is the kind of mistake
that costs a silicon session to diagnose.

Filed: `bug-s-an-interrupt-directive-proc-reached-through-a-normal-call-returns-via-mret-with-no-diagnostic` (p60). Note the refusal is cheap *today* precisely because §1.1 is open: with no raw install path in existence, EVERY `@interrupt_proc` is currently a mistake, so the predicate is trivial now and refinable when the install lands.

## 1.3 [QEMU] The `iram;` + `esp_intr_alloc` path is checked only as a *relocation*, never executed

`test_esp_isr_register.pas` is a `readelf -r` assertion that `@MyIsr` emits an
absolute reloc against the handler symbol. That is a real check and it is not
execution. The IDF is installed and qemu runs; an actual `esp_intr_alloc`
registration that fires is buildable here today.

**WHAT WOULD MOVE IT:** nothing — it is already [QEMU]. It is unwritten, not
unanswerable. This is the single highest-value unwritten fixture on the list.

## 1.4 [QEMU/BOARD split, already measured] qemu delivers SOME interrupt sources and not others

This split already exists in the tree and is easy to miss:

- **esp_timer callbacks: 5/5 ticks on BOTH chips** (`test-esp-idf`). Delivery
  works.
- **GPIO edges: qemu does NOT deliver them.** `examples/esp32/gpio-c3` records
  its own verdict string `PROBE: VERDICT qemu-delivers-NO-gpio-edges`, and the
  Makefile asserts that *negative* verdict.

**So "does qemu do interrupts" has no single answer — it is per peripheral.**
Note also that the timer row proves less than it appears to: the esp_timer
callback is *a plain routine running in task context*, by its own comment. It
exercises IDF dispatch, **not** a PXX ISR.

**WHAT WOULD MOVE GPIO:** only a board. This is a correct [BOARD] row and a good
example of one — the probe has already been written, has already run, and has
already returned "qemu cannot answer this".

## 1.5 [QEMU, measured] "Runs in interrupt context" IS assertable from Pascal — but the instrument is scoped to IDF-DISPATCHED ISRs and would LIE about a raw one

Measured 2026-09-21 for frankh-c0, whose acceptance row ("allocation count
unchanged across N ticks") is only evidence if the handler genuinely runs in
interrupt context.

**The instrument exists and is callable from Pascal.** ESP-IDF exports
`BaseType_t xPortInIsrContext(void)` for **both** ports
(`freertos/FreeRTOS-Kernel/portable/{riscv,xtensa}/include/freertos/portmacro.h`),
as an ordinary external. Declared `function xPortInIsrContext: Integer;
external;` it links and returns.

**MEASURED BY ME**, esp32c3 under qemu, IDF profile, 398 callbacks:

    PROBE: app_main       in-isr=0
    PROBE: timer-callback in-isr=0      (all 398)

So the esp_timer callback is task context **by measurement**, not by its own
source comment — which is §1.4's caveat now established rather than read.

**DERIVED FROM THE IDF SOURCE, NOT MEASURED BY ME — label it that way when
quoting it.** `xPortInIsrContext` returns `port_uxInterruptNesting[coreID]`
(`portable/riscv/port.c:461/469`), a counter incremented by `rtos_int_enter`
(`portasm.S:598-605`: `lw a1 / addi a2, a1, 1 / sw a2`) and decremented on the
exit path (`:736`). So it is a live variable maintained by **the IDF's own
interrupt-entry trampoline**.

**TWO CONSEQUENCES, AND THE FIRST IS A TRAP:**

1. **It would report 0 inside a RAW `interrupt;` handler.** A raw vector entry
   does not pass through `rtos_int_enter`, so the counter is never incremented
   and the instrument says "not in an ISR" while the CPU is genuinely in a trap
   handler. **`xPortInIsrContext` is a predicate about IDF DISPATCH, not about
   machine state**, and its name does not say so. Anyone verifying §1.1's raw
   path with it will get a confident wrong answer. (Not reachable today —
   §1.1 — but it will be, and this is precisely a hazard that produces no
   signal while it is believed.)
2. **It is also 0 before the scheduler starts**, even in an ISR: `rtos_int_enter`
   skips the increment when `port_xSchedulerRunning[coreID] == 0`
   (`portasm.S:596`). Early-boot interrupt code cannot use it.

**WHAT I HAVE NOT SHOWN, STATED PLAINLY:** I have not seen this return 1. All
my rows are 0, so "the instrument works and both arms are task context" and
"the instrument always returns 0" are not distinguishable from these
measurements alone — the mechanism above is what separates them, and it is a
source read. **The positive control belongs beside an IDF-dispatched ISR
arm**: one handler reading 1 where the timer callback reads 0 validates the
instrument and the precondition in a single asymmetry, which is far stronger
than either arm's absolute value. That arm is c0's.

**WHAT WOULD MOVE IT:** nothing — [QEMU] already. The 1-reading row is
unwritten, not unanswerable.

## 1.6 [SRC, and it refutes a premise two lanes were using] "An ISR that allocates is a latent crash" does NOT hold on the IDF profile — and the bare profile is a separate, open question

Two lanes (this one and Track N's `feature-n-a-nilpy-def-has-no-native-abi-
entry-point-...`) were both carrying the sentence *"boxing into Variants
allocates, and an ISR that allocates is a latent crash"*. Both halves have now
failed to survive contact, and neither failure was a measurement anyone had
taken when the sentence was written.

**The first half fell to frankh-c0's measurement** (pxx@aa4e7bb73): the
existing `$pycbthunk_` scalar path does not allocate — 200 iterations gave 5
allocations, 20,000 gave 7, against a control that scaled exactly 100x. The
allocation is in the def BODY, not the marshalling. **That is an x86-64 result
and c0 labels it as one** — it is not yet a statement about xtensa or riscv32,
and this file's own §0 warning about the 64-bit host applies.

**The second half is contradicted by the IDF's own source.** On the IDF
profile, PXX's allocator IS the IDF heap: `builtinheap.pas:1383-1400` redefines
`PXXAlloc` to `calloc`/`free`, resolving to newlib/heap_caps at link time
(`EspArena` is the BARE profile only). And `heap_caps` is deliberately
ISR-safe — `components/heap/multi_heap_platform.h:18-25`, verbatim:

    /* Because malloc/free can happen inside an ISR context,
       we need to use portmux spinlocks here not RTOS mutexes */
    #define MULTI_HEAP_LOCK(PLOCK) ... portENTER_CRITICAL_SAFE((PLOCK)) ...

`portENTER_CRITICAL_SAFE` is the ISR-safe variant, and the comment gives the
ISR case as **the reason** for choosing a spinlock over a mutex. The IDF did
not tolerate allocation in an ISR; it selected its locking primitive for it.

**So on the IDF profile the cost of allocating in an ISR is LATENCY and
determinism — a spinlock and a critical section inside a handler — not
corruption.** That is still a good reason to forbid it in a real-time path, but
it is a different argument, with a different enforcement and a different
acceptance, and a ticket justified as "latent crash" is asserting something the
platform's own source contradicts.

**THE PROFILE SPLIT IS LOAD-BEARING AND MUST NOT BE COLLAPSED.** Bare is not
IDF. There PXX uses its own `EspArena` and the ISR-safety of that path is
**unestablished by anyone** — it is not a known-good and not a known-bad. Do
not let the IDF answer travel to it.

**STILL UNMEASURED, BY ANYONE, AND OWNED BY TRACK N:** what an allocation
inside an ISR actually costs on this hardware. c0's numbers are evidence about
WHERE allocation happens, never about what it costs in interrupt context, and
they should not be cited as the latter.

**WHAT WOULD MOVE IT:** a per-call allocation census on-target. Note the
obvious instrument is the wrong one — free-heap delta is a NET measure, so an
alloc/free pair nets to zero and it can show a flat line while `malloc` is
called every tick, which is exactly the churn the claim is about. Call counts
need IDF heap tracing (a config flag, heavier build) or a hook.

---

# 2. NON-INTERRUPT ROWS

## 2.1 [QEMU] Exceptions are unexercised on the bare profile

`test/test_esp_bare.pas` — the fixture the bare tier boots on both chips — has
**zero** occurrences of `try`, `except` or `raise`. `test_esp_exception.pas`
exists (12) and `test_esp_idf_nested_try.pas` covers the windowed-ABI frame bug
on the IDF profile. The *bare* exception path is the hole. I booted
`test_esp_exception` in qemu on both chips earlier today (6/6 boots) — so the
capability is there and the *bare tier* simply does not assert it.

**WHAT WOULD MOVE IT:** already [QEMU]; it is a missing row, not a missing
instrument.

## 2.2 [SRC] 112 `PAL_ERR_UNSUPPORTED` sites in `platform_backend.pas`

Deliberate refusals — CLAUDE.md's "ESP is not a Unix" is the design and this is
not a defect. It is on the list because **nobody has classified which of the 112
a real program actually reaches.** A refusal that no demo hits is free; one on a
path `lekkerzeilen` or a busybox applet takes is a wall.

**WHAT WOULD MOVE IT:** a census of which refusals are reachable from the demo
set. [SRC], free, and it is the sort of thing that stops being affordable when
the token budget drops.

## 2.3 [SRC] The 64 KiB arena — see the denominator warning above

p60, unblocked, mechanism and precedent already in the ticket. Deliberately
**not** done here: it stays cheap, and survey work does not.

## 2.4 [SRC] The bare-image ceilings in the Makefile are now far too loose

I set `esp32c3) cap=18700` / `esp32s3) cap=15200` earlier today against
measurements of 16988 / 13788 B. The `PXXDynSetLen` dedup then landed
(`2c59f8326`) and the empty-program figures fell to 848 B (xtensa) / 336 B
(riscv32). **The ceilings are stale in the loose direction, which is the
direction that produces no signal** — exactly the stale-hazard shape CLAUDE.md
warns about. They should be re-derived against the current fixture.

**WHAT WOULD MOVE IT:** one measurement and one commit. [SRC].

---

# 3. WHERE THIS MAP IS BLANK — named, so length does not imply coverage

I did **not** examine, and make no claim about:

- **Watchdogs** (TWDT/IWDT) — whether a PXX program feeds or disables them.
- **Stack overflow detection** on either profile; no guard page on bare metal.
- **Cache/flash coherency** beyond ISR IRAM residency — e.g. whether anything
  reachable from an ISR can touch flash and stall.
- **Multi-core** (esp32s3 is dual-core) — task/core affinity, cross-core atomics.
- **Power/sleep** modes, brownout.
- **The `iram;` directive's own correctness** beyond section placement.
- **Windowed-ABI xtensa** generally — bare metal requires Call0 (the compiler
  refuses windowed + `--esp-profile=bare` outright), so the windowed path is
  IDF-only and I did not survey it.

Any of these could be empty or could hold the next p70. Unknown is not clean.

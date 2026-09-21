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

**MEASURED BY ME, BOTH ISAs**, under qemu, IDF profile, one program:

    esp32c3 (riscv32)   app_main in-isr=0   timer-callback in-isr=0   (all 398)
    esp32s3 (xtensa)    app_main in-isr=0   timer-callback in-isr=0   (all 392)

Zero non-zero readings on either chip. So the esp_timer callback is task
context **by measurement on both ISAs**, not by its own source comment — which
is §1.4's caveat now established rather than read. (The callback counts differ
only because each run is a fixed wall-clock window against a 100 ms periodic
timer; they are not a quantity either row is asserting.)

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

**AND THE TWO PORTS DO NOT RETURN THE SAME QUANTITY, SO `= 1` IS A
CROSS-TARGET TRAP.** Source read, both files, verified:

    riscv   port.c:461/469   return port_uxInterruptNesting[coreID];   { the RAW COUNT }
    xtensa  port.c           return (port_interruptNesting[coreID] != 0);  { normalised to 0/1 }

riscv hands back the nesting COUNT; xtensa normalises to a boolean. Under
nested interrupts riscv legitimately answers 2 or 3 where xtensa still answers
1 — **and nesting is real there, not theoretical**: `portasm.S:607` branches on
it in so many words, *"If we reached here from another low-priority ISR, i.e,
port_uxInterruptNesting[coreID] > 0, then skip stack pushing to TCB"*. So an
`= 1` assertion passes on xtensa and can fail on riscv, and it fails only once
a second interrupt arrives during the first — correct on every run until it
is not. **Assert `<> 0`.** Note too that the variable is spelled differently in
each port (`port_uxInterruptNesting` vs `port_interruptNesting`), so a grep for
one finds half the story.

This is the single-target hazard this file warns about elsewhere for x86-64,
arriving BETWEEN THE TWO ESP ISAs — and it nearly shipped that way here: §1.5
was drafted from the riscv implementation plus an esp32c3 run, and the xtensa
half is a different expression.

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

### The bare half, RESOLVED 2026-09-21 — and it restores the corruption argument, on bare only

frankh-c0 flagged a lead (`builtinheap.pas:1050-1059`: the hard lock is emitted
by CODEGEN around the `tkGetMem`/`tkFreeMem` sites and `PXXAlloc` does not take
it) and correctly filed it as a lead. **It holds, and it is stronger than it
was framed — on ESP there is no lock model AT ALL:**

    frontend_prologue.inc:127  EmitHeapLockSlowStub  <- ThreadSafeMode AND TARGET_X86_64
    paslexer.inc:1226          PXX_TS_SOFTLOCK       <- i386 / aarch64 / arm32
    paslexer.inc:1242          PXX_TS_HARDLOCK       <- x86-64

**riscv32 and xtensa appear in neither list.** So `PXXAlloc` on ESP takes no
lock under any flag combination — and the flag is not silently ignored, it is
**refused**, which is the compiler being honest and must not be "fixed":

    $ pascal26 --threadsafe --target=riscv32 --esp-profile=bare t.pas t
    --threadsafe is x86-64/i386/aarch64/arm32 only: the heap/ARC/I-O locks
    are not implemented on this target yet

**So the profile split is now fully resolved, and the two halves differ
completely:**

| profile | PXXAlloc backs onto | ISR-safe? |
| --- | --- | --- |
| **IDF** | `calloc`/`free` → heap_caps (`builtinheap.pas:1383-1400`) | **YES**, by the IDF's deliberate design |
| **BARE** | the `EspArena` free list, **no lock, none available** | **NO** |

**THE HAZARD IS LATENT, NOT LIVE, AND IT ARMS ON A KNOWN EVENT.** On bare there
is no FreeRTOS, so the only possible concurrency is an interrupt — and §1.1
says no interrupt handler can be installed on bare today, because the vector
write is not expressible. **So nothing can currently allocate concurrently on
bare, and the free list is safe by unreachability rather than by design.** It
stops being safe the moment §1.1's enabler lands.

**AND THE OBVIOUS REMEDY IS WORSE THAN THE HAZARD ON A SINGLE CORE — WHICH IS
WHY THE REFUSAL ABOVE MUST STAY.** Found by frankh-c0, verified here. PXX's
heap lock, where it exists at all, is a bare exchange spin with **no interrupt
masking** (`builtinheap.pas:1613`, released by a plain store at `:1678`):

    while Integer(__pxxatomic_xchg(@PXXHeapSpin, 1)) <> 0 do
      tsIgnore := tsIgnore + 1;

**The mechanism, stated rather than a prohibition, because a mechanism survives
someone renaming the flags:** on a single core, a task takes that spin, an
interrupt preempts it, the handler allocates and spins — and the only code that
can release the lock is the task the handler is standing on, which cannot run
until the handler returns. **Neither can make progress.** Unlocked corrupts a
free list, which is survivable and debuggable; this hangs the chip with no
output at all. So wiring riscv32/xtensa into the `PXX_TS_SOFTLOCK` list — which
is exactly what the source invites, since `PXX_THREADSAFE` is all over
`builtinheap.pas` and the refusal message reads like a TODO with instructions
attached — makes things **strictly worse**, not partially better.

**This is the operative half of the IDF sentence both of us first quoted for
its other half.** The full line is *"we need to use portmux spinlocks here NOT
RTOS MUTEXES"*, and `portENTER_CRITICAL_SAFE` **disables interrupts**. The IDF
is not preferring a spinlock for speed; it is choosing the one primitive that
closes precisely this hole, and `PXXHeapSpin` is the primitive it rejected. So
the shape of any eventual ESP heap lock is already determined by the platform,
and it is not the shape the existing ifdefs would give you: it must mask
interrupts in the acquire.

**Which makes this the second thing that enabler must carry**, beside §1.7's
stack story: installing raw ISRs on bare makes reachable an unlocked allocator
that has never needed a lock. Both are recorded in that ticket.

**WHAT WOULD MOVE IT:** a per-call allocation census on-target. Note the
obvious instrument is the wrong one — free-heap delta is a NET measure, so an
alloc/free pair nets to zero and it can show a flat line while `malloc` is
called every tick, which is exactly the churn the claim is about. Call counts
need IDF heap tracing (a config flag, heavier build) or a hook.

## 1.7 [SRC] EVERYTHING THE IDF DOES TO MAKE AN ISR SAFE IS INSTALLED BY ITS TRAMPOLINE — AND A RAW `interrupt;` HANDLER BYPASSES ALL OF IT

This is the row that ties §1.1, §1.5 and the stack question together, and it is
the one I would put in front of the owner before any board time is spent on
interrupts.

`rtos_int_enter` (riscv `portasm.S`) does at least two things before any
handler runs:

    :598-605   port_uxInterruptNesting[coreID] += 1     { what xPortInIsrContext reads }
    :643-645   lw sp, (xIsrStackTop[coreID])            { SWITCHES SP to a dedicated ISR stack }

The ISR stack is a real, separate object — `StackType_t
xIsrStack[portNUM_PROCESSORS][configISR_STACK_SIZE]`, with `xIsrStackTop` /
`xIsrStackBottom` (`port.c:112-120`). So an **IDF-dispatched** handler runs on
its own stack and correctly reports itself as in-ISR.

**A RAW `interrupt;` VECTOR ENTRY GETS NEITHER**, because it never passes
through that trampoline:

- It runs on **whatever stack was current** — the interrupted task's. Its
  prologue then pushes 64 bytes (riscv) or 48 (xtensa) plus its own frame onto
  a stack sized for that task. `defs.inc:2322` notes ESP-IDF task stacks of
  **3584 bytes**, and observes there that it already halves recursion depth.
- It reports **`xPortInIsrContext` = 0** (§1.5), so the obvious safety check
  says "not in an ISR" while the CPU is in a trap handler.

**AND PXX HAS NO RUNTIME STACK GUARD ON ESP AT ALL.** Measured: zero matches
for a stack overflow / guard / canary / limit check in `builtinheap.pas` or
`lib/rtl/platform/esp/**`. The only protection anywhere is
`CheckBareImageFitsSram` (`elfwriter.inc:1947`), which is **build time** — it
enforces `ESP_BARE_STACK_MIN` (16 KiB) of headroom so an oversized arena is a
build error rather than, in the tree's own words, *"a stack that grows down
into the heap and produces a plausible wrong value."* Nothing checks at
runtime, on either profile.

**So the raw path is not merely uninstallable (§1.1) — it is also unprotected
by every ISR facility the platform provides.** Enabling the install without a
stack story would produce exactly this project's most-feared failure: a
plausible wrong value far from its cause, on hardware, with the obvious
diagnostic instrument reporting all-clear.

**WHAT WOULD MOVE IT:** it is [SRC] and stays there — this is a design
conclusion, not a measurement gap. What it should PRODUCE is a decision
recorded before §1.1's enabler lands: either the raw path switches stacks in
its own prologue, or `interrupt;` is documented as IDF-dispatch-only and the
raw arm is dropped. That is a Track U question and it is cheap to answer now
and expensive to discover later.

---

# 2. NON-INTERRUPT ROWS

## 2.1 ~~Exceptions are unexercised on the bare profile~~ — **RETRACTED 2026-09-21, THE ROW WAS FALSE**

**This row was wrong and I withdraw it.** The bare tier DOES exercise
exceptions, on both chips, against the x86-64 oracle — `Makefile:35684-35693`,
inside `test-esp-bare:`, booting `test_esp_exception.pas` on esp32c3 and
esp32s3 and diffing UART byte-for-byte. It is not a hole. I found this by
trying to *fix* it.

**THE REAL COVERAGE, since the point of this file is populations**: the bare
tier boots **14 distinct fixtures** in qemu on both chips —
`test_esp_bare{,_arg64,_asm,_assert,_atomic,_float,_largeframe}.pas`,
`test_esp_{class,exception,frozen_string,procvar,record_result,stack_args,varparam}.pas`.
That is a substantially better-covered tier than this row implied.

**THE MECHANISM OF THE ERROR, which is the part worth keeping.** I grepped ONE
fixture — `test/test_esp_bare.pas` — found zero `try`/`except`/`raise`, and
asserted a property of **the tier**. The grep was *correct about that file* and
silent about the other thirteen. That is this repo's own rule fired at my own
work: *print the set your instrument enumerates and check the subject is IN
it.* The subject was "does the bare tier assert exceptions"; the set I
enumerated was "the text of one file". They never intersected, and nothing
errored.

**It is also the wrong-population trap in its most seductive form**, because the
fixture I checked is the one the tier is NAMED after. `test_esp_bare.pas` reads
like *the* bare test, so checking it feels like checking the tier — and the
name is doing the work, not the measurement. Filed under this file's own §0
warning about names.

**A residue survives and it is much smaller than the row claimed:** nothing
here establishes which exception SHAPES are covered (nested, re-raise,
finally-through-frames, exception in an ISR context once §1.1 lands). The
14-fixture list is a count of files, not of shapes, and I am explicitly not
converting one into the other — that would be the same error one level up.

## 2.2 ~~[SRC] 112 `PAL_ERR_UNSUPPORTED` sites in `platform_backend.pas`~~ — **ANSWERED IN §3**

**This row is CLOSED and kept rather than deleted, so the class stays visible.**
It asked for *"a census of which refusals are reachable from the demo set"* and
that census is **§3 of this same file**, landed 2026-09-21 in `3ef925668` — the
commit that left this row untouched.

**The short answer: zero measured walls**, and "112" was the wrong number —
1 const declaration + 8 prose mentions + 103 executable sites, of which 32 are
never compiled on any ESP target. See §3.0 for the denominator and §3.3 for the
partition.

**WHY THIS ROW IS WORTH A PARAGRAPH RATHER THAN A DELETION** (found by frankz-e5,
2026-09-21). It is the **"WHAT WOULD MOVE IT" form of the stale row, and that
form is nastier than a stale fact**: the row names its own retirement condition,
so a reader who checks it is checking exactly the right thing — and still gets
the wrong answer, because **nothing re-reads a row when its condition is met.**
A stale fact gets contradicted by the next measurement; a satisfied
retirement-condition just sits there looking open.

**Its half-life was the shortest possible: the condition was met by the same
author in the same commit.** I wrote §3 and did not look fifty lines up at the
row that had asked for it. So this is not an argument for more diligence — it is
the reason a retirement condition needs a POINTER AT THE ANSWER and not just a
description of it. **When you satisfy a "what would move it", edit the row in the
same commit**, exactly as CLAUDE.md requires of a ticket summary, and for the
same reason: the question is where a reader looks, and the answer being elsewhere
in the same document does not help them.

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
- ~~**Stack overflow detection**~~ — PARTLY ANSWERED, see §1.7: there is no
  runtime guard on either profile (measured), and the only protection is the
  build-time `CheckBareImageFitsSram`. What remains unexamined is whether the
  IDF's own task-stack watermarking is reachable from PXX, and what a sensible
  runtime check would cost.
- **Cache/flash coherency** beyond ISR IRAM residency — e.g. whether anything
  reachable from an ISR can touch flash and stall.
- **Multi-core** (esp32s3 is dual-core) — task/core affinity, cross-core atomics.
- **Power/sleep** modes, brownout.
- **The `iram;` directive's own correctness** beyond section placement.
- **Windowed-ABI xtensa** generally — bare metal requires Call0 (the compiler
  refuses windowed + `--esp-profile=bare` outright), so the windowed path is
  IDF-only and I did not survey it.

Any of these could be empty or could hold the next p70. Unknown is not clean.

## 3. THE PAL REFUSAL CENSUS — which refusals are walls and which are free

**Measured 2026-09-21 by frankb-8e at `compiler/pascal26` = the tree's HEAD build.
Every count below names its path, because there are three files of this name.**

### 3.0 The denominator, and why "112" is not the number you want

    lib/rtl/platform/esp/platform_backend.pas    112 grep hits   <- THE SUBJECT
    lib/rtl/platform/wasi/platform_backend.pas   109 grep hits
    lib/rtl/platform/posix/platform_backend.pas   22 grep hits

**109 is plausible for 112.** Quoting "112 in platform_backend.pas" and landing on
the wasi file would not announce itself, to me or to a later re-runner. The path
is part of the number.

And 112 is not 112 refusals. It decomposes exactly:

    112 = 1 const declaration + 8 prose mentions inside block comments + 103 EXECUTABLE sites

Of those 103, **32 sit in the `{$else}` arm of `{$ifdef PXX_PAL_ESP_IDF_TARGET}`** —
and that symbol is `{$define}`d for `CPU_XTENSA` *and* `CPU_RISCV32` (lines 163-164),
i.e. for **every ESP target there is**. Those 32 are the unit's host-build fallback
and **are not compiled into any ESP image**. They are not refusals on the device.

    103 executable = 71 compiled on ESP + 32 never compiled on ESP
    71 sites live in 70 distinct routines

**So the honest subject is 71 sites in 70 routines, not 112.** I arrived at the
wrong one three times on the way here — first counting comments as code, then
counting a dead `{$else}` arm as a refusal, and both times the count *looked*
reproducible.

### 3.1 The instrument, and its positive control

**`pxx --dce` call-graph reachability, per program — NOT a grep of call sites.**
A grep answers "is this entry named anywhere"; `--dce` answers "is this entry
reachable from THIS program's entry point".

**Positive control, and it is sharp:** `fs-c3` without `--dce` emits **114**
`PalBackend*` bodies — including `Fork`, `Execve` and `Alarm`, which it plainly
does not call, because without DCE the whole unit is emitted. With `--dce` it
emits **5**: `Open`, `Read`, `Write`, `Seek`, `Close` — exactly what its source
calls. **Negative control:** a bare-profile fixture emits **0**.

Flags come from each demo's own `build.sh` invocation line, not from a grep of
flags in the file — an early pass of mine read `--esp-profile=bare` out of the
NilPy scripts' *prose* while their actual compile line carries no such flag.

**A KNOWN LOOSENESS, MEASURED IN THIS POPULATION.** `nilpy-c3` and `nilpy-s3` are
**byte-identical sources** (`cmp`), and riscv32 reports `PalBackendWrite` live
while xtensa reports it dead. That is
`bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program` showing up
here. **Every riscv32 row below is therefore an UPPER BOUND** — the true reached
set is this size or smaller, which means the wall count is a ceiling, not a floor.

### 3.2 The population of programs

**14 demos in `examples/esp32/`** — and note `find examples/esp32 -name '*.pas'`
answers **10**, because the four NilPy demos are `.npy`. I used all 14.

### 3.3 The partition

    18   PAL entries reached by at least one of the 14 demos (union)
     5   of those carry a refusal that IS compiled on ESP   <- WALL CANDIDATES
    65   refusing-on-ESP routines reached by NOTHING        <- FREE TODAY

**The 5, with the ARM each refusal sits behind** — because "reached" is a claim
about the routine and the refusal is a claim about a branch inside it:

| routine | site | the arm |
| --- | --- | --- |
| `PalBackendWrite` | 356 | `if handle <= PAL_STDERR` |
| `PalBackendRead` | 342 | `if handle <= PAL_STDERR` |
| `PalBackendSeek` | 371 | `if handle <= PAL_STDERR` |
| `PalBackendClose` | 404 | `if handle <= PAL_STDERR` |
| `PalBackendClose` | 423 | `if handle < 4096` — the deliberate not-a-`FILE*` guard |
| `PalBackendOpen` | 287 | `if (flags and PAL_OPEN_EXCL) <> 0` |
| `PalBackendOpen` | 292 | `if (flags and PAL_OPEN_DIRECTORY) <> 0` |

**Every one of the five is reached on a path that does NOT take the refusing
arm.** `fs-c3` opens, reads, writes, seeks and closes a real file and works: its
handles come back from `PalOpen` above 4096 and it passes neither `EXCL` nor
`DIRECTORY`. So there are **zero measured walls in the demo set** — which is a
much weaker and much more useful statement than "112 unsupported entries".

### 3.4 THE BLIND SPOT — NAMED, THEN MEASURED, AND THE ANSWER IS BENIGN

**The blank (found 2026-09-21):** no demo in the population uses Pascal
`WriteLn`. All ten Pascal demos print through an `esp_rom_printf` external and
the four NilPy ones through the NilPy runtime. Since `TextWriteLn` calls
`PalWrite(f.Handle, ...)` and stdout's handle is `1`, which is `<= PAL_STDERR`,
**the refusing arm of four of the five wall candidates was the one arm the whole
demo set structurally could not reach.**

**MEASURED THE SAME DAY RATHER THAN LEFT AS A HAZARD BLOCK. Both profiles.**

| profile | does `WriteLn` reach the PAL? | what happens |
| --- | --- | --- |
| **IDF** (`--platform=esp`) | **NO** — `--dce` on a `WriteLn` program shows `PXXSysWrite` and **zero** `PalBackend*` | works; goes to the libc stdout stream |
| **bare** (`--esp-profile=bare`) | **NO** — zero `PalBackend*`, zero `PXXSysWrite`; whole 3-`WriteLn` program is **336 B** of code | emits nothing, **by design**, with a compiler warning |

**So the `handle <= PAL_STDERR` arm is not reachable from `WriteLn` on either ESP
profile, and §3.3's "zero measured walls" now has no known blind spot behind
it.** The IDF half is already guarded by `test/test_esp_idf_writeln_end.pas`,
whose own header records that `WriteLn` *used* to lower to nothing on ESP and
was fixed; the bare half is intentional and stated at
`docs/targets/esp32.md:70` — *"`writeln`/`readln` are intentionally no-ops —
there is no console"*.

**I nearly filed the bare result as a silent-failure bug.** The qemu boot
printed nothing and exited 0, which is the exact shape this map exists to catch.
It is not silent: the compiler says

    pascal26:5: warning: write/writeln emits nothing on the bare ESP profile:
    there is no console. Write to the UART from your own code ... or build a
    hosted image with --platform=posix.

**I could not see it because I had been reading compiler output through
`| tail -1`, which shows the `ok:` line and hides every diagnostic above it** —
in three consecutive commands, having spent the day cataloguing instruments that
are correct about something else. `tail -1` on a pxx run is one of them.

**A REAL RESIDUAL DID FALL OUT, AND IT IS FIXED:** `tools/esp_run_bare.sh` wrote
compiler output to a buildlog it printed **only on failure**, so that warning was
invisible to anyone building through the harness — program compiles, boots,
prints nothing, exits 0, and the one diagnostic explaining it sits in a file
nobody cats. The script's own comment records someone fixing exactly this
swallowing for the FAILURE case; the warning-on-success half was never covered.
Now printed to **stderr**, never stdout, so the "bytes the program wrote to
UART" contract stays byte-identical.

**STILL BLANK, and stated rather than implied:** I measured **reachability**, not
**entry** — a `--dce` live body is reachable-in-graph, and only a run records
what was entered. The 65 free refusals are free **for these 14 programs**; that
is a property of the population, not of the PAL. And nothing here covers
`readln`, which shares the bare no-op.

**A guard worth adding and deliberately not added here:** a fixture asserting
that the bare `WriteLn` warning FIRES. It is currently the only thing between a
developer and a silent-looking chip, and nothing tests that it still appears.
That is a tier row, not a drive-by.

### 3.5 WHAT RETIRES A ROW

**A new entry point into the PAL**, and one is being built today (frankh-c0's ISR
thunk consumer). A census of reachability is measured against a program shape,
so it ages the moment the shape changes. Re-run
`tools/esp_pal_reachability_census.sh` against the same 14 demos and diff the
union; its header carries both controls, so a zero from it is checkable.

Not a retiring event: someone adding a refusal. Adding a site changes 71 and
changes no row here unless the routine is one of the 18 reached.

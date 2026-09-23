---
slug: feature-s-interrupt-events-reach-python-outside-interrupt-context
track: S
type: feature
prio: 35
status: working
owner: frankS
created: 2026-09-23
found-by: frankb-8e
blocked-by: []
summary: "DESIGN SETTLED BY THE OWNER 2026-09-22; this ticket records it and scopes the build. Python must never run in interrupt context -- `python code within an interrupt is a horrible idea` -- and the design makes that unreachable BY CONSTRUCTION rather than by discipline: a handler is written in C or Pascal, the LIBRARY owns it, and it only sets a flag or pushes an event; the Python callback runs on the ordinary control flow afterwards. IDF is assumed, so the remaining surface is small -- GPIO edges and truly custom peripherals (`we are back to trivial gpio 'user presses a button'`). CHOSEN PUMP POINT: drain at the blocking points we ALREADY OWN -- `time.sleep` (nanosleep in mimic_time.pas:152), `input()`, RTL waiting reads -- plus an explicit `interrupts.poll()`. A second FreeRTOS task was REJECTED on interpreter-state grounds; compiler-emitted safepoints are DEFERRED, not refused. Surface: `interrupts.on_falling(pin=9)` and `for ev in interrupts.events():`. SCOPE BOUNDARY THAT MAKES THIS BUILDABLE NOW: the DRAIN half is verifiable on x86-64 against a synthetic source and needs no board, while EDGE DELIVERY is blocked on hardware -- qemu models no GPIO input path at all, measured with a control arm in feature-esp-gpio-and-adc-callback-slices. So build and test the pump against a synthetic source; do NOT wire the GPIO source as acceptance. `interrupts` does not exist in lib/rtl today (checked at HEAD, 2026-09-23). OPEN, and the owner raised it himself: a `hidden` loop for when modules are imported but nothing is running -- must engage only when a handler is registered, and must not stop a desktop program exiting."
---

# Interrupt events reach Python — outside interrupt context, by construction

## Status of each claim in this ticket, stated up front

Three different authorities are mixed below and they are NOT equally settled.

- **SETTLED (owner, 2026-09-22)** — quoted verbatim. Do not re-litigate.
- **PROPOSAL (frank-coordinator)** — four robustness items, carried here so they
  are not lost. **Not settled**, and each is a decision someone must actually
  take.
- **MEASURED (frankb-8e, 2026-09-23)** — the scope boundary and the absence of
  `interrupts`. Re-measurable; see the commands.

## SETTLED — Python is never in interrupt context, and not because we are careful

> *python code within an interrupt is a horrible idea*

The mechanism makes it **unreachable rather than discouraged**, which is the
part that matters:

1. A custom interrupt handler is written in **Pascal or C, preferably C**.
   Python *imports* it and communicates through globals. There is no path by
   which interpreter code runs in trap context, so no rule to enforce and
   nothing to get wrong.
2. **Users are not expected to write one at all.** The library's own ISR sets a
   flag or pushes an event; the Python callback runs on ordinary control flow
   afterwards.

**This is already the established pattern in this tree, not a new one.**
`lib/rtl/platform/esp/esptimer.pas` (slice 1 of
[[feature-esp-peripheral-callback-api]], done) says so in its own header: the
user supplies a callback and starts the timer *"without ever seeing
esp_timer_create args, esp_intr_alloc, or `iram;`"*, and the callback stays on
this side of the seam. So this ticket extends a worked example rather than
introducing a convention. **Read esptimer.pas before designing anything here.**

## SETTLED — IDF is assumed, so the remaining surface is small

> *we are back to trivial gpio 'user presses a button'*

With IDF assumed, what is left is **GPIO edges** and **truly custom
peripherals**. Everything else arrives through a driver that already owns its
own interrupt. Do not scope this as a general interrupt framework.

## SETTLED — the pump point: drain where we already block

**Chosen:** drain the event queue at the blocking points the RTL already owns —

- `time.sleep` → `nanosleep`, `lib/rtl/mimic_time.pas:152` (verified present at
  HEAD),
- `input()`,
- RTL waiting reads,

— plus an explicit **`interrupts.poll()`** for a program that wants to drain
without blocking.

**REJECTED: a second FreeRTOS task.** Reason is interpreter state: two tasks in
one interpreter means the queue is no longer the only shared thing and the
design stops being "Python runs on ordinary control flow".

**DEFERRED, not refused: compiler-emitted safepoints.** That is the answer to
"a program that is computing and never blocks", and it is a Track A change of a
different size. A deferred option is not an opening — see the `-O4` precedent in
CLAUDE.md.

## SETTLED — the surface

```python
interrupts.on_falling(pin=9)

for ev in interrupts.events():
    ...
```

**The unit name IS the Python module name** — no marker syntax to invent, and
the unit carries a Pascal surface beside the Python one. `lib/rtl/base64.pas`
(`unit base64;`) is the worked example; the crash course
(`devdocs/dev/pxx-crash-course.md`) states the rule. So this is `unit
interrupts;` and nothing about the import mechanism needs building.

## OPEN — the owner's "hidden loop", and the two questions it raises

The owner raised this himself and left it open:

> *the only thing we may want to add is a 'hidden' loop (for when all modules
> imported but nothing is running)*

The case is a script that registers handlers and then reaches the end of the
file. On a microcontroller, falling off the end is not what the author meant. Two
things must be settled before writing it, and they are the whole difficulty:

1. **It must engage only when a handler is actually registered.** A program that
   registers nothing must keep its current behaviour exactly.
2. **A desktop program must still exit.** The same source has to terminate on
   x86-64. This is the condition that makes the feature dangerous: get it wrong
   and every NilPy script that imports `interrupts` hangs at exit on the host,
   which is a regression in the frontend's ordinary use rather than in an ESP
   feature.

**Do not build the hidden loop in the same commit as the pump.** The pump is
verifiable (below) and the hidden loop needs a decision about host behaviour
that this ticket does not have. If (1) and (2) cannot both be satisfied, that is
a Track U `decide`, stated as a question about what we want — not about
interpreter shutdown internals.

## PROPOSAL (frank-coordinator) — four robustness items, none of them settled

Carried so they are not lost. Each is a real decision:

1. **A source tag, not a bare pin number.** An event should carry
   `(source, id, timestamp)`. A bare pin number cannot distinguish two sources
   on one pin, and cannot express a non-GPIO source at all.
2. **Refuse a re-entrant drain** — one `in_drain` flag. A Python callback that
   calls `time.sleep` would otherwise re-enter the drain from inside itself.
3. **Bound the work per drain.** Otherwise a fast source starves the code that
   was trying to sleep.
4. **Ring-full policy is an explicit decision, not a default.** Drop-and-count
   versus coalesce-per-source. **Whichever is chosen, the count must be
   observable** — a silently dropped edge is the plausible-wrong-value failure
   this repo keeps paying for.

## MEASURED — the scope boundary, which is what makes this buildable now

This is the load-bearing measurement, because it separates a half that can land
from a half that cannot.

**`interrupts` does not exist in `lib/rtl` at HEAD.** Checked 2026-09-23:
`ls lib/rtl/ | grep -iE 'interrupt|^machine|gpio'` returns nothing; the only
GPIO unit is `lib/rtl/platform/esp/espgpio.pas`, which is the OUTPUT path. So
this is a genuine gap and not a rename of something present. (Check before
building: a rule in CLAUDE.md exists because a `threading` gap was described as
absent months after it was implemented.)

**EDGE DELIVERY IS BLOCKED ON HARDWARE and must not be this ticket's
acceptance.** [[feature-esp-gpio-and-adc-callback-slices]] (slice 2, `blocked/`)
measured it with a control arm: `gpio_config`, `install_isr_service` and
`isr_handler_add` all return **rc=0** and `edges=0`, and the control — a second
pin configured input with a pull-up reading **0** where silicon reads 1 — shows
qemu does not model the GPIO **input path** at all. The absent edges follow from
that. So there is no instrument on this box that can see a real edge.

**THE DRAIN HALF DOES NOT NEED ONE, AND THAT IS THE WHOLE PLAN.** The queue, the
drain at each blocking point, the re-entrancy refusal, the per-drain bound, the
ring-full policy and the `events()` iterator are all testable on **x86-64
against a synthetic source** — a function that pushes an event as if from an ISR.
Nothing about them is ESP-specific. Build and assert that; leave the GPIO source
behind the existing blocked ticket.

**Acceptance, and the trap in it:** a test must assert the callback ran
**outside** interrupt context and that events are **not lost**. A row asserting
only "the callback ran" passes on an implementation that runs it in trap context,
which is the one outcome the whole design exists to make impossible — and on ESP
that is diagnosed on silicon, at the owner's expense. Assert the ORDERING (the
drain happens at the blocking point, not before it) and the COUNT (N pushed, N
delivered, and the drop counter accounts for any difference), because a value
check alone can see neither. See CLAUDE.md on matching the assertion class to
the defect class.

## Not in scope, recorded so it is not a surprise

A `machine`-shaped **bus** surface (I2C/SPI register reads) is the thing that
would carry a large corpus of existing device drivers unchanged — franks-5b's
point, that *almost no device driver depends on interrupts*: a typical driver is
twenty lines of I2C register reads. **That is separate new work and is not
ranked.** It is mentioned here only so nobody folds it into this ticket on the
grounds that both are "the device story".

## PROSE EDGES BY DESIGN — why `blocked-by` is empty although the prose names a blocked ticket

`check` flags this ticket for naming [[feature-esp-gpio-and-adc-callback-slices]]
(open, `blocked/`) in prose without a `blocked-by` edge. **That is deliberate and
it is the point of the scope boundary above**, so neither of the two repairs
`check` offers is right here:

- The edge is REAL for the **GPIO source** half — nobody can see an edge on this
  box, and no acceptance row may depend on one.
- The edge is NOT real for the **drain** half — the queue, the blocking-point
  drain, re-entrancy, the per-drain bound, the ring-full policy and `events()`
  are all exercisable on x86-64 against a synthetic source.

Wiring `blocked-by` would park the buildable half behind hardware that only the
unbuildable half needs, which is how a ticket sits untouched for weeks with its
own body saying it could have been started. Leaving the prose out would hide a
real constraint from whoever picks it up.

**If you promote this into a ranked folder, split it first** — a `-pump` ticket
with no edge and a `-gpio-source` ticket blocked on the slice — rather than
adding the edge to this one.

## Related

- [[feature-esp-peripheral-callback-api]] — slice 1 (timer), done. The pattern.
- [[feature-esp-gpio-and-adc-callback-slices]] — slice 2/3, blocked on hardware.
  The edge source lives here, not in this ticket.
- `bug-s-a-direct-call-to-an-interrupt-routine-is-the-same-trap-return-fault-by-another-spelling`
  — done 2026-09-23. Both spellings of entering an `interrupt;` body from normal
  code are now refused, which is what keeps a hand-written handler from being
  reachable the wrong way while this is built.
- `devdocs/dev/esp32-hardening-map.md` §1.5 — "runs in interrupt context" IS
  assertable from Pascal, but the instrument is scoped to IDF-DISPATCHED ISRs
  and **would lie about a raw one**. Read that before writing the
  outside-interrupt-context assertion above; it is the obvious instrument and it
  is the wrong one for a raw handler.

---

## 2026-09-24, frankS — THE PUMP HALF IS BUILT. The GPIO source is not, and the hidden loop is not.

Measured on plexus, x86-64, `compiler/pascal26` `d3d6ee833089`, fixedpoint
`converged after 1 round(s)`.

**Re-checked this ticket's own gap claim before building, because it says to:**
`ls lib/rtl/ | grep -iE 'interrupt|^machine|gpio'` still returns nothing and
`grep -rln '^unit interrupts' lib/` finds none. The gap was real.

### What landed

- **`lib/rtl/interrupts.pas`** — the queue. `IntPush(source, id)` is the only
  thing an ISR calls: it takes no callback, never allocates, never blocks and
  never dispatches. Callbacks run only from `IntPoll`, which an ISR cannot
  reach. **The invariant is structural, not a rule anyone maintains.**
- Events carry `(Source, Id, StampMs, Seq)` — the source tag from proposal 1,
  plus a push ordinal so loss is detectable rather than inferable.
- **Re-entrancy refused** (proposal 2), **per-drain budget** (proposal 3), and
  the ring-full policy **chosen and documented**: drop the NEWEST and count it
  (proposal 4), because overwriting the oldest silently rewrites history a
  consumer has not seen and leaves a `Seq` gap with no record of where.
  `IntDropped` is the observable count.
- **`platform.PalPendingDrain` / `PalDrainPending`** — a nil-by-default hook in
  the layer that owns blocking. `interrupts` installs it on the first
  registration and clears it on the last.
- **Pumped at `mimic_time.sleep` AND `sysutils.Sleep`**, after the wait.

### The design decision worth recording: the pump is INSTALLED, not linked

Making `mimic_time` `uses interrupts` would have been three lines and would
have rooted the queue in **every program that imports `time`**, including every
program that never asked for it — SRAM on ESP paid by someone else. A nil
procedure variable costs one pointer test per blocking call and lets DCE drop
the whole unit when nothing installed it. The fixture asserts this directly:
`no-handler delivered 0 pending 1`.

### A REAL DEFECT THE FIXTURE FOUND BY ACCIDENT, AND IT IS THE SIBLING-SPELLING CASE

The first run's drain row read 0 and looked like a broken pump. It was not: the
fixture wrote `uses interrupts, mimic_time, sysutils` and its bare `sleep(0)`
bound to **`sysutils.Sleep`**, because the last unit in a uses clause wins —
and `sysutils.Sleep` was unwired.

**Both spellings mean "I am about to stop doing work" to whoever wrote the
source**, so wiring only the Python-facing one leaves every Pascal program
permanently unpumped. That is `normalise-dont-special-case`'s sibling case
arriving in a `uses` clause, and neither the construct name nor any corpus
distinguishes them. Both are wired now and **asserted separately, qualified**
(`mimic_time.sleep(0)`, `sysutils.Sleep(0)`).

**Had the two units been listed the other way round, the same fixture would have
passed and the gap would have shipped unseen.** That is the arrangement-
dependence CLAUDE.md warns about, in a place it does not name.

### Acceptance: ORDERING and COUNT, not "the callback ran"

`test/test_interrupt_events_drain_outside_isr.pas`, wired into `lib-test`.

| row | claim |
| --- | --- |
| `after-push delivered 0 pending 3 seen 0` | **ORDERING** — nothing delivered at push time |
| `after-py-sleep delivered 3 pending 0 seen 3` | delivered at the blocking point |
| `order-preserved TRUE` | Seq contiguous, 1..3 |
| `before/after-pas-sleep` | the Pascal spelling pumps too |
| `push-when-full FALSE dropped 1` | the refusal is visible |
| `accounted TRUE` | **COUNT** — pushed == delivered + dropped, exactly |
| `budget-bounded 4 / second-drain 4` | bounded, and the rest deferred not lost |
| `reentrant-observed TRUE nested-delivered 0` | re-entrant drain refused |
| `no-handler delivered 0 pending 1` | the nil-hook negative control |

**POSITIVE CONTROL, measured both ways rather than asserted:** deleting the
`mimic_time` drain flips `after-py-sleep` to `delivered 0 pending 3 seen 0` and
`order-preserved` to FALSE, while the `sysutils` rows keep working — so the two
pumps are independently observable and neither row is passing for the other's
reason. Restored and re-verified identical afterwards.

**NOT inert waiting for a pin:** lib-only change, and the pinned compiler
produces byte-identical output to HEAD's on this fixture.

### What is deliberately NOT here

- **The GPIO edge source.** Blocked on hardware, not on this work. Nothing on
  this box can observe an edge, and no row here may stand in for one — which is
  why the fixture pushes from `INT_SRC_TEST` and never `INT_SRC_GPIO`.
- **The hidden loop.** The ticket says not to land it with the pump and that is
  right: the host-exit half is the dangerous one, and getting it wrong hangs
  every NilPy script that imports this unit at exit on x86-64. `IntHandlerCount`
  exists so whoever builds it has the "is anything registered" predicate ready.
- **The Python surface** (`interrupts.on_falling(pin=9)`, `for ev in
  interrupts.events()`). The unit name is already the module name, so nothing
  about the import mechanism needs building — but `events()` returning objects
  with attributes needs the marshalling types, and I would rather land the core
  with its controls than guess at the sugar. **This is the next increment**, and
  it is why this ticket is not closed.

### Suggested split, per this ticket's own instruction

It says to split before promoting: this section is the `-pump` half and is done.
What remains is `-gpio-source` (blocked on the slice), the Python surface, and
the hidden loop.

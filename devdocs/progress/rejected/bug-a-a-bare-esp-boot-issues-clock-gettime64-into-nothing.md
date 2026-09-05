---
track: A+S
prio: 40
owner: frankS
summary: "REJECTED 2026-09-05: the observable is unreachable, which CLAUDE.md sends to rejected/ rather than to a low prio. A bare ESP boot does NOT issue clock_gettime64, because builtin.pas -- the unit holding the call -- DOES NOT COMPILE on --esp-profile=bare. Measured as a 2x2 rather than asserted: `Randomize` builds on riscv32 and xtensa under --platform=posix and is `undefined variable (Randomize)` on both under --esp-profile=bare. That also answers the ticket's own open xtensa question -- xtensa behaves identically, and the missing guard on the CPU_RISCV32 arm is moot because the whole unit is absent. The ticket asked for exactly this measurement before any fix and correctly refused to guess; the answer is further in the harmless direction than either option it offered. builtin.pas:459 already states the true position and should be left alone: pylib `uses builtin` and builtin does not compile there, `if that ever changes, this is the line that fires`."
type: bug
status: rejected
found: 2026-08-30
found-by: claude-A
---

# A bare ESP boot compiles a raw `clock_gettime64` into `Randomize`, behind a guard that never ran

`builtin.pas`'s `Randomize` seeds from `clock_gettime`. The riscv32 arm issues
raw syscall 403 (`clock_gettime64`), and it was wrapped in `{$ifndef PXX_ESP}`
with the comment *"No clock on a bare target (PXX_ESP): ts stays zero"*.

**That guard never ran.** `PXX_ESP` is not a compiler symbol — `PXX_ESP_BARE`
is, and `builtinheap.pas:18` defines `PXX_ESP` *for itself only*; defines do not
cross unit boundaries. See
[[bug-a-builtin-pas-calls-a-declaration-that-esp-compiles-out]], where this was
established with a canary rather than by reading directives.

The dead directive was deleted in `fccdc4671` because it claimed a protection it
did not provide. **Deleting it changed no behaviour** (byte-identity, 17/17,
bare-ESP profiles included) — the syscall was already compiled in, and still is.
This ticket is the behaviour the guard was *meant* to produce and never did.

## What is measured and what is not

- **Measured:** the line is compiled into every bare riscv32 build. The
  `{$ifndef PXX_ESP}` around it was inert on every target.
- **Measured:** `Randomize` is the only caller, so a program that never
  randomizes never reaches it. This is a *compiled-in*, not an *always-issued*,
  defect.
- **NOT measured:** what a bare ESP boot actually does when the syscall is
  issued. The intent comment says there is no clock; nobody has run it. It could
  fault, or return an error the code ignores (`ts` stays zero, which is the
  documented fallback and would be harmless).

**Measure that before fixing it.** If the raw syscall returns an error and `ts`
stays zero, the outcome is already the intended one and this is a cleanliness
ticket, not a correctness one — which is the difference between prio 40 and
something much higher.

## The xtensa arm

Not checked. The guard covered only the `CPU_RISCV32` arm; whether xtensa's
`Randomize` has an equivalent path on a bare boot is a separate question, and
after four targets with four different mechanisms it should not be assumed.

## Related

[[bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target]] is the
other half of seeding on ESP and is where a real entropy source for these
targets belongs. If that lands, this call site may simply go away.


## Rejected 2026-09-05 (frankS) — measured, and the answer is "it never issues it"

### The ticket asked for this measurement by name

> **NOT measured:** what a bare ESP boot actually does when the syscall is
> issued. … **Measure that before fixing it.** If the raw syscall returns an
> error and `ts` stays zero, the outcome is already the intended one and this is
> a cleanliness ticket, not a correctness one — which is the difference between
> prio 40 and something much higher.

Measured, on compiler `5783500470d0`. **The answer is neither of the two options
offered.** The syscall is never issued, because the unit containing it is not
compiled for that profile at all.

| | `--platform=posix` | `--esp-profile=bare` |
| --- | --- | --- |
| riscv32 | `Randomize` **builds** | `undefined variable (Randomize)` |
| xtensa | `Randomize` **builds** | `undefined variable (Randomize)` |

A 2×2 rather than a single probe, because a one-cell result cannot tell "absent
on bare" from "absent everywhere" — and `PXXEntropy64`, my first choice of
probe, is undefined on BOTH profiles because it is not exported, so it could not
have discriminated anything. Replaced it rather than reading its red as a
result.

`builtin.pas:459` already says this in the source, and says it correctly:

> *"That cannot reach a bare ESP boot today, because pylib `uses builtin` and
> **builtin does not compile there**; if that ever changes, this is the line
> that fires."*

### So the ticket's one "Measured" line is the part that is wrong

It records *"the line is compiled into every bare riscv32 build."* Today it is
not. **This may well have been true when filed on 2026-08-30** — enough has
moved since that I am not going to claim the author measured wrongly, only that
the claim does not hold now. Either way the current state is what governs.

### The xtensa arm, which the ticket left open

> *"Not checked. The guard covered only the `CPU_RISCV32` arm; whether xtensa's
> `Randomize` has an equivalent path on a bare boot is a separate question."*

Answered: **identical.** `Randomize` is undefined on bare xtensa too. The
asymmetry in the guard does not matter, because the guard's absence and its
presence are equally inert when the unit is not compiled.

### Why rejected/ and not low-prio

CLAUDE.md: *"An observable no compiling program can reach is `rejected/`, never a
low prio — parking it at 10 keeps it in the ranker forever at zero value."* No
program that compiles for `--esp-profile=bare` can reach this line, on either
chip.

**Nothing in the source should change.** The comment at `builtin.pas:459` is the
accurate, live record of the latent hazard — it names the condition under which
this becomes real (`pylib` reaching a bare boot) and points at the exact line.
That is a note doing its job, and deleting it because the ticket closed would
remove the only warning if the condition ever changes.

### Related, and now the live half

`bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target` is where a
real entropy source for these targets belongs, and it is unaffected by this
rejection: seeding on ESP is still weak-by-construction wherever `builtin` DOES
compile.

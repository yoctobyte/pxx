---
track: A+S
prio: 40
type: bug
status: open
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

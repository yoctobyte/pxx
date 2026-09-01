---
track: A
prio: 25
type: bug
blocked-by: []
summary: "`--emit-obj` on i386/aarch64/arm32 refuses with `only xtensa/riscv32 targets` -- but x86-64 supports it and is the target most users are on. The message names a set that excludes a working target, so a reader who trusts the diagnostic over the docs concludes the feature is ESP-only."
status: working
owner: frankA
---

# The `--emit-obj` refusal names a target set that excludes x86-64

- **Type:** bug — **Track A** (`compiler/**`, the refusal site). Found by frankD
  2026-08-30 while checking a docs scope claim
  ([[bug-d-docs-scope-claims-about-a-flag-are-invisible-to-a-flag-existence-sweep]]).
  Measured against `$(PXX_STABLE)`; no rebuild.

## Measured

`--emit-obj t.pas o.out`, trivial Pascal program:

| target | result |
| --- | --- |
| x86_64 | **works** — ELF 64-bit relocatable |
| riscv32 / xtensa | works |
| i386 / aarch64 / arm32 | `pascal26:2: error: --emit-obj: only xtensa/riscv32 targets` |

The refusal is correct in *refusing*; its **text** is wrong. x86-64 is supported
and is not in the set the message names.

## Why it is worth more than its size

A diagnostic outranks a page. A reader who hits this on aarch64 and reads *"only
xtensa/riscv32"* concludes object output is an embedded-only feature — and stops,
rather than retargeting to x86-64 where it works. **The message is the instrument
they trust most and it is the one that is wrong.** The docs said "on any target"
until today, so both instruments were wrong in opposite directions and the truth
was in neither.

## Suggested

Name the supported set (`x86-64, riscv32, xtensa`) rather than a subset, or state
the unsupported one. Whichever, derive it from the same predicate the refusal
tests, so the two cannot drift.

**Before rewording, grep for the current text** — face 231: a diagnostic's wording
is an interface, `Makefile` asserts 23 of them with `grep -q`, and **zero emitting
sites say so.**

## Gate

`make compiler/pascal26` plus the six rows above, run. Do not widen.

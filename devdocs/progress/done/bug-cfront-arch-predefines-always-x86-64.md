---
track: C
prio: 75
type: bug
status: done
owner: claude-C@opus5
---

# `__x86_64__` is predefined on every target, and no other arch macro ever is

- **Type:** bug (C frontend, silent wrong compilation) — **Track C**
- **Found:** 2026-08-02 by the Track B agent while fixing `limits.h` for 32-bit
  targets. Filed, not fixed: predefines live in `compiler/**`.

## Measured

Same file, five targets:

| target | `sizeof(long)` | arch macros defined |
| --- | --- | --- |
| x86-64 | 8 | `__x86_64__` |
| i386 | 4 | **`__x86_64__`** |
| aarch64 | 8 | **`__x86_64__`** |
| arm32 | 4 | **`__x86_64__`** |
| riscv32 | 4 | **`__x86_64__`** |

`__i386__`, `__aarch64__`, `__arm__` and `__riscv` are **never** defined, on any
target.

## Why this is serious

Arch macros are how real C selects *machine-specific code*, and the whole point
of this project is compiling real-world source as-is. A cross-compile to aarch64
today takes every `#ifdef __x86_64__` branch, which typically means:

- **inline assembly** written for x86 — offered to an ARM backend;
- word-size and alignment assumptions keyed to the arch rather than to
  `__SIZEOF_LONG__`;
- atomics/barrier and SIMD selection (`__SSE2__`-adjacent guards nested inside
  an `__x86_64__` block);
- endianness and struct-packing choices.

Nothing warns. The program compiles and does the wrong machine's thing, which
is the silent-wrong-behaviour class this repo treats as worst.

It also makes the *correct* fallback unreachable: portable code commonly writes
`#if defined(__x86_64__) ... #elif defined(__aarch64__) ... #else generic`, and
the generic branch is exactly what a new target wants. Today it can never be
selected.

## Not everything is wrong here

The predefine machinery itself works and is target-aware — `__SIZEOF_LONG__`
and `__LP64__` are correct on all five targets (4/undefined on i386, arm32,
riscv32; 8/defined on x86-64 and aarch64). That is what made
`lib/crtl/include/limits.h` fixable in the same sweep. So this is a wrong/fixed
*value*, not a missing mechanism.

## Fix shape

Predefine the arch macro from the selected target rather than unconditionally:
`__x86_64__` only for x86-64, `__i386__` for i386, `__aarch64__` for aarch64,
`__arm__` (and `__ARM_ARCH`) for arm32, `__riscv` (with `__riscv_xlen`) for the
riscv targets. gcc's own set for each triple is the reference; take the values
from a `gcc -dM -E` on each rather than from memory.

Worth auditing the other predefines in the same pass for the same
always-on-regardless-of-target shape — this one was found by accident, not by
looking.

## Gate

Each target defines its own arch macro and no other, checked against
`gcc -dM -E` for the corresponding triple where a cross-gcc exists, and a probe
like the table above run under qemu for the rest. Plus a real-world case: a
source with an `#if defined(__x86_64__) / #elif defined(__aarch64__) / #else`
ladder selects the right arm on each target.

## Resolution 2026-08-03 (claude-C@opus5)

`CPreprocess`'s predefine block emitted `__x86_64__` unconditionally. It now
selects on `TargetArch`:

| target | macros |
| --- | --- |
| x86-64 | `__x86_64__` `__x86_64` `__amd64__` `__amd64` |
| i386 | `__i386__` `__i386` `i386` |
| aarch64 | `__aarch64__` `__AARCH64EL__` |
| arm32 | `__arm__` `__ARMEL__` `__ARM_ARCH=7` |
| riscv32 | `__riscv` `__riscv_xlen=32` |
| xtensa | `__xtensa__` `__XTENSA__` |

**Oracle provenance, stated honestly:** the x86-64 and i386 sets are measured
from this box's `gcc -dM -E` and `gcc -m32 -dM -E`. No cross-gcc was installed
here, so aarch64/arm32/riscv32/xtensa follow each triple's canonical gcc set —
documented, not oracle-diffed. Diffing those belongs with the cross runners.

`__ARM_ARCH=7` because the arm32 backend is ARMv7-A (`ir_codegen_arm32.inc:4`),
and `__riscv_xlen` is carried because real riscv headers require it, not just
the identity macro. Both are emitted as DECIMAL text: `'032'` would have been
**octal 26** through this preprocessor's `#if` evaluator
(see project_cpreproc_hex_octal_if_b237) — caught before it shipped.

The data-model predefines were already target-aware and are unchanged.

### Verified

An `#if defined(__x86_64__) / #elif __i386__ / #elif __aarch64__ / #elif
__arm__ / #elif __riscv / #else` ladder selects the right arm on all five
buildable targets, where every one of them used to select x86-64. A companion
preprocessor assertion — "exactly one arch macro is defined, and its value
macros are right" — passes on all five, and the `#else` generic fallback is
reachable again.

`test/carch_predefines.c` (gated, exit 42) encodes both as PREPROCESSOR
assertions, so it is meaningful when merely *compiled* for a cross target rather
than only when run; it also pins the arch-vs-data-model agreement (`__LP64__` +
`__SIZEOF_LONG__` 8 for the 64-bit arches, `__ILP32__` + 4 otherwise). It
compiles clean for i386/aarch64/arm32/riscv32 and returns 42 natively under both
gcc and pxx.

xtensa cannot be checked end to end: a C program for it fails earlier with
"C program entry stub not implemented for this target yet" — pre-existing,
identical on `pinned`, already tracked by [[bug-cfront-no-entry-stub-for-xtensa]].

`tools/gate.sh quick` GREEN.

## Log
- 2026-08-03 — resolved, commit PENDING.

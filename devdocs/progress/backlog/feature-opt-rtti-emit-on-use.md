---
prio: 40
---

# RTTI is emitted unconditionally (every class, even a classless program) — dead weight on ESP32/embedded

- **Track:** A (RTTI emission is core: `compiler/rtti_emit.inc`, the emit driver in
  `parser.inc`). **Tag:** O (size/codegen). Cross-cutting toward the ESP/xtensa +
  riscv32 targets.
- **Found:** 2026-07-16, dissecting the frozen `hello` demo's size (280 B remembered
  vs 785 B now). See [[project_rtti_streaming_plan]], [[project_rtti_reflection_and_overload_landmines]].

## What we measured (frozen, `-uPXX_MANAGED_STRING`)

| build | file | code | data |
| --- | --- | --- | --- |
| bare `begin end.` x86-64 | 679 B | 351 | 208 |
| bare `begin end.` x86-64 `--no-signals` | 407 B | 79 | 208 |
| bare `begin end.` **xtensa/ESP** | ~168 B data | **6** | 168 |

Breakdown of the x86-64 baseline growth vs the old ~280 B:
- **Signal-handler runtime ~272 B of code** — x86-64 default-on, `--no-signals` opts
  out. **NOT on ESP** (x86-64-gated). Working as intended; leave it.
- **Div-by-zero abort stub + "Runtime error 200…" string (~40 B)** — x86-64 ONLY
  (`if TargetArch = TARGET_X86_64 then EmitDiv0Stub`, parser.inc ~24210). **NOT on
  ESP** (uses hardware/trap behavior). Fine.
- **RTTI** — emitted on ALL targets, including ESP. This is the only dead weight on a
  micro. The bare xtensa binary is code=6 B but still carries a `TObject` remnant in
  `.data`.

## The two RTTI wastes

1. **Every user class gets a full RTTI header even when never reflected.** Deliberate
   today — `EmitRTTI` (rtti_emit.inc ~319-338) emits one `RTTI_CLS_SIZE` header +
   interned name per class so `ClassName` answers for any class (the published-only
   gate used to make `ClassName` a coin flip). Correct, but on ESP32 with classes and
   **no** `is`/`as`/`ClassName`/`TypeInfo`/streaming it is pure size cost.
2. **A classless program still emits a `TObject` remnant** (~8 B interned name). The
   "plain wrong" case: zero classes, zero reflection, yet RTTI bytes ship.

## Goal

Opt OUT of RTTI to compress embedded size, keep it available (opt-in / on-demand) for
debugging, reflection, and advanced software (streaming, fpcunit, dynamic dispatch).

## Approaches (ranked)

1. **Usage-driven emission (north-star).** Emit a class's RTTI only if the program
   actually reflects on it — `ClassName`/`ClassType`/`InheritsFrom`, `is`/`as` against
   it, `TypeInfo`, published-member access, LFM streaming. Track a per-class
   "RTTI-touched" bit during parse/lower; `EmitRTTI` skips untouched classes. Zero
   cost when unused, no flag, no silent breakage. Hard part: cases the compiler can't
   see statically (LFM `FindClass`-by-name, dynamic streaming) need a force-on escape.
2. **`--rtti=auto|full|none` flag (pragmatic first step).** `auto` = usage-driven (or,
   interim, the current all-classes behavior); `full` forces every class (for
   dynamic/streaming reflection the compiler can't prove); `none` hard-off — a
   reflection op under `none` is a **compile-time error**, never a silent wrong value.
   ESP/bare default leans (`auto`, and skip the classless `TObject` remnant).
3. **Minimum quick win, independent of the above:** when `UClsCount = 0` and no
   reflection op appears, emit NO RTTI at all (drop the `TObject` remnant).

## Guard rails

- **Never silently break reflection.** `is`/`as`, `ClassName`, LFM streaming
  ([[project_rtti_streaming_plan]]), fpcunit ([[project_fpcunit_green_metaclass_self]])
  all consume RTTI. Gating must be usage-aware or explicit; a stripped build that hits
  a reflection op must error at compile time, not miscompute.
- ESP already skips signals/div0 by target; RTTI gating should follow the same
  "lean-by-default on embedded, full on host" instinct.

## Not in scope (separate, minor)

- x86-64 `EmitDiv0Stub` is unconditional even for division-free programs (~40 B). Could
  gate on "a div/mod site exists." Small host-only win; file separately if wanted.

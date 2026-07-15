---
summary: "--strict-fpc / {$STRICT_FPC ON}: one umbrella for the corpus-safe FPC-parity behaviour flags (case, operator, visibility, require-forward). --mimic-fpc = --strict-fpc + {$I+} + FPC defines. StrictOverload deliberately EXCLUDED (breaks the lax RTL)."
type: feature
track: P
prio: 40
---

# --strict-fpc: the FPC-parity behaviour umbrella

- **Track P** (Pascal dialect / frontend flags). Compiler-side only; the builtin
  and RTL libraries are NOT touched.
- **Landed 2026-07-15.** Came out of the Random name-collision discussion
  ([[bug-pascal-unqualified-call-binds-builtin-over-used-unit]]).

## Model (the whole thing in 4 facts)

1. **Name providers, weakest→strongest as brought into scope:** builtin (the
   compiler's includable intrinsics — PRNG, Str/Val, Move, softfloat, …) → RTL /
   libs → user code. Each overrides any name below it.
2. **Default (INTENDED, first-class pxx):** anything overrides anything by name;
   same-name/different-signature = an overload set resolved by argument fit.
   Override is a *feature* — it is how platform softfloat-in-builtin, the RTL, and
   apps select implementations. **Unchanged. Nothing "what works" moves.**
3. **The switch — `--strict-fpc` / `{$STRICT_FPC ON}`:** behave like FPC where FPC
   chose differently. Turns on `StrictCase` + `StrictOperator` + `StrictVisibility`
   + `RequireForward` (EnableStrictFpc, lexer.inc).
4. **`--mimic-fpc` = `--strict-fpc` + `{$I+}` + the curated FPC define set** (i.e.
   also declares pxx to BE FPC). So `--mimic-fpc ⊇ --strict-fpc`.

## The one exclusion — StrictOverload (the key finding)

`--strict-fpc` deliberately does **NOT** include `StrictOverload`. FPC-parity
*would* want it, but empirically it **breaks the very corpora --mimic-fpc exists to
compile**: our own RTL (`sysutils.StringOfChar`, …) uses undirectived overloads —
the lax dialect, by design — so `--strict-overload` errors "overloaded routine
requires overload directive" on fpjson/Synapse. The only ways to satisfy it are
(a) add `overload` directives across the RTL = compatibility BOILERPLATE we
reject, or (b) scope the check to the main program only, which proved leaky
(errored inside pulled units anyway). So `StrictOverload` stays a **standalone
experimental flag** (`--strict-overload` / `{$STRICT_OVERLOAD ON}`) for
directive-clean code, out of both umbrellas. The `bug-pascal-unqualified-call-
binds-builtin-over-used-unit` disposition follows: default lax overload-compete is
INTENDED; there is no default change and no resolution surgery.

## Validation

- fpjson `--mimic-fpc` 203/0, Synapse `--mimic-fpc` green (both now carry the
  newly-promoted case+operator — validated, following the same discipline
  StrictVisibility was promoted under).
- Pascal conformance 326/0; the sweep already ran `--strict-case --strict-operator`.
- `--strict-fpc` compiles a normal RTL-using program (IntToStr/UpperCase) — proves
  the bundle coexists with the lax RTL (because StrictOverload is out).
- self-host byte-identical (default path unchanged; flags are opt-in).
- Regression test: `test/lib_strict_fpc.pas` (+ a negative under `--strict-fpc`).

## Files

`compiler/lexer.inc` (EnableStrictFpc + `{$STRICT_FPC on/off}`), `compiler.pas`
(`--strict-fpc` CLI; `--mimic-fpc` now calls EnableStrictFpc), `compiler/parser.inc`
(StrictOverload scoped to the main program — a harmless improvement to the
standalone flag). No builtin.pas / RTL edits.

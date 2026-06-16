# Synthetic all-features stress test (cross-target conformance)

- **Type:** feature
- **Status:** working
- **Owner:** —
- **Opened:** 2026-06-15

## Goal

Self-hosting is an excellent cross-target stress test, but a deliberately
incomplete one: the compiler is written in a restricted subset and omits whole
language areas on purpose (objects/classes, interfaces, variants in some forms,
operator overloading edges, sets, nested closures, generics, etc.). So the
self-host exercises only the IR-primitive combinations the *compiler itself*
uses. Bugs in primitives that the compiler never combines (but user programs
will) stay invisible until a user hits them on a given target.

Build one **synthetic** program — not a real app, just a dense conformance
harness — that combines every supported language feature in mixed, adversarial
ways, and produces deterministic output. Run it on every target and diff against
the x86-64 oracle (same pattern as the existing `test_cross_*` suite). It fills
the gap between the narrow per-primitive `test_cross_*` cases and the (subset-
only) self-host.

## Why

Every cross-target wall this cycle was a per-backend *primitive* gap exposed by a
*combination* (e.g. Int64 by-ref param next to a managed string on ARM32;
dyn-array-of-record fill for `array of const` on AArch64). The frontend/IR is
shared and transparent; IR→machine is four independent translators. A
combinatorial harness surfaces those gaps without needing each one to happen to
appear in compiler.pas.

## Scope / coverage checklist (combine, don't isolate)

- Int64/UInt64: arithmetic, shifts, div/mod, compares, **by-value and by-ref
  params**, returns, as record fields, as array elements, as `array of const`
  items, mixed with 32-bit operands in the same expression.
- Managed AnsiString: concat, index read/write (COW), Length, by-ref params,
  string fields in records, arrays of string, as function results, adjacent to
  Int64/record params (the ARM32 slot-overlap class).
- Records: by-value args >8 bytes, with managed fields, nested, arrays of record,
  record-returning functions, whole-record copy.
- Dynamic arrays: of scalars, of records, of strings, SetLength/grow, nested.
- `array of const` (TVarRec): mixed int/string/char items, in a huge-frame
  caller, built inside a `case`, passed through.
- Open arrays (`array of T`) by const/var, including `array of AnsiString`.
- Variants: int/string payloads, function return, compares.
- Floats: literals (the lexer 64-bit-bits path), arithmetic, Trunc/Round→Int64,
  Str/Val, format widths.
- Control flow: `case`, nested loops, exceptions (try/finally/except), goto if
  supported, short-circuit `and`/`or` (when landed).
- Calls: >4/>8 args (stack args), recursion, mutual recursion, large frames
  (>4 KB and >64 KB locals — the AArch64 immediate / ARM32 frame-encode class).
- Mixed adversarial expressions that force register pressure and arg-eval
  clobbering.

## Acceptance

- A single (or a small set of) `test/test_conformance_*.pas` that compiles and
  runs identically on x86-64, i386, ARM32, AArch64 (and ESP32/RISC-V/Xtensa once
  those gain the needed primitives), diffed against the x86-64 oracle.
- Wired into each `make test-<target>`.
- Output is deterministic and order-stable (no addresses/pointers printed).

## Notes

- Keep it *synthetic and dense*, not a real application — the point is coverage
  per line, not realism.
- Gate features that a target doesn't support yet behind defines so the harness
  can grow per target rather than all-or-nothing.

## Log

- 2026-06-16 — first harness drafted: `test/test_conformance_1.pas` (classes +
  inheritance + virtual dispatch mixed with Int64, managed strings, records,
  dynamic arrays, `array of const`, variant, exceptions, float formatting, case).
  **It already fails — on x86-64 itself, before any cross-diff.** Not debugged
  (deliberately, per workflow); NOT wired into `make` so the suite stays green.
  Findings to triage later:
  1. **Directly-instantiated BASE class with a managed-string field reads
     garbage.** A derived instance works (`TSquare.Create` → fields/virtuals/
     Int64 tag all correct), but a base-class instance created right after
     (`TShape.Create('generic', 7); writeln(sh.Name)`) prints a corrupt string —
     `sh.Name` ('generic') comes back with a bad length and `writeln` dumps the
     heap, producing ~24 MB of runaway output. Minimal repro: two classes
     (base + derived override), instantiate the derived then the base, write the
     base instance's string field. Suspect base-class field layout / managed
     field init when the base is instantiated directly (classes are NOT used by
     the compiler itself, so self-host never exercised this).
  This is exactly the class of gap the harness is meant to surface (a supported
  feature the compiler never self-uses). DECISION PENDING: fix the class bug(s)
  first, or shelve and continue other work — the harness + repro are in place to
  resume from.


## 2026-07-14 (later still) — SWEEP GREEN: 289 pass / 0 fail (b369). Ticket CLOSED.

User unparked the rainy-day flag. The final five:
- **tdefault8 / tset4** — already fixed by 5649c749 (class-nested types by
  qualified name + TSysCharSet); the sweep just hadn't been re-run.
- **tclass14b** — `published` class property now rejected ("a class property
  cannot be published"). Keyed on an EXPLICIT `published` marker only — the
  implicit default section stays lenient (pxx treats every class as $M+).
- **toperator71** — overloading `=`/`<>` for CLASS operands rejected (they are
  predefined reference equality).
- **toperator92 / toperator95** — a second `:=`/Implicit/Explicit conversion
  from the same source type to a result of the same TYPE KIND rejected as a
  duplicate (String[80] vs String[90] are indistinguishable at use sites);
  distinct result kinds stay legal. Catches the class-operator + global-
  operator split form too (one shared overload table).
- **tclass12b** — the one true visibility test: NOT fixable under the
  "access control unenforced" project policy. Split out to
  [[bug-pascal-member-visibility-unenforced]] (with FPC's unit-scoped
  private/protected caveat) and skip-listed pointing there.

Conformance: 285 -> 289 pass, 0 fail. tgeneric21 (nested generic-in-generic,
semantics unverified) remains noted in feature-pascal-corpus-fpc-testsuite.

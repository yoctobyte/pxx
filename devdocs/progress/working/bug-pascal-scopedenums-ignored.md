---
prio: 50
---

# {$SCOPEDENUMS} silently ignored — duplicate enum member resolves to the WRONG enum

- **Type:** bug (Pascal frontend — directive + enum scoping)
- **Track:** P — promoted out of the compat umbrella per the escape rule
  (silent wrong behavior ≠ parity nicety; see
  [[bug-pascal-missing-diagnostics-fail-tests]] triage 2026-07-11).
- **Status:** working
- **Owner:** opus-p

## Symptom (verified at v200)

`{$SCOPEDENUMS ON}` is not recognized at all. Two concrete failures:

1. **Silent wrong values.** With a scoped enum and a later unscoped enum
   reusing a member name, the bare name resolves to the LATER enum's ordinal
   — no error, wrong number:

   ```pascal
   type
   {$SCOPEDENUMS ON}
     TEnum1 = (first, second, third);
   {$SCOPEDENUMS OFF}
     TEnum2 = (zero, first, second, third);
   var e1: TEnum1;
   begin
     e1 := first;       { FPC: error (first not visible unscoped) }
     writeln(Ord(e1));  { pxx prints 1 (TEnum2.first) — user meant TEnum1.first = 0 }
   end.
   ```

   FPC rejects the assignment; pxx compiles and prints `1`. This is the
   fpc-testsuite tenum4 gap (kept as reminder in pxx.skip, `gap:` tag).

2. **Scoped access does not parse.** `e1 := TEnum1.first;` fails with
   `error: undefined variable (TEnum1)` — so code correctly written for
   scoped enums cannot compile at all.

## Fix shape

- Lexer: recognize `{$SCOPEDENUMS ON|OFF}` (directive table next to
  `{$STRICT_CASE}` etc.).
- Parser: an enum type declared under scopedenums registers members ONLY
  under the type scope (not the flat symtab); `TEnumType.member` resolution
  (symtab already has SymEnumId plumbing since 3f606750 — the enum-identity
  work — which should help).
- Minimum honest fallback if full scoping is deferred: ERROR on
  `{$SCOPEDENUMS ON}` ("not supported") instead of silently ignoring —
  kills the wrong-values hazard immediately at near-zero cost.

## Gate

`make test` + self-host byte-identical; negative test (bare member under
scopedenums rejected) + positive test (TEnum1.first works) in `make test`;
unskip tenum4 in the conformance sweep.

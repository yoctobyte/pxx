# A `set of char` typed constant corrupts `Ord(char-var)` codegen

- **Type:** bug (codegen) — silent wrong value
- **Status:** urgent (Track A)
- **Owner:** — (Track A — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** [[feature-synapse-compile-check]], while verifying the (now
  fixed) hex-char-literal bug. Relevant: Synapse's synacode/synautil use
  `set of char` constants heavily alongside char processing.

## Symptom

When a program declares a **typed constant of a `set of char` type**, codegen
for plain `char` variables in the same program goes wrong: `Ord(c)` returns
garbage (an address-like value), and `c in C` returns the wrong membership.

```pascal
program p;
type T = set of char;
const C: T = [#65];          { any set-of-char const: [#65], ['A'..'Z'], ... }
var c: char;
begin
  c := #65;
  writeln(Ord(c));           { prints 4226039 (garbage); must be 65 }
end.
```

Isolation (stable v50):

- No set const present → `Ord(c)` = 65 (correct).
- An *Integer* const present → 65 (correct).
- A **`var`** (non-const) `set of char` → 65 (correct).
- A **`const`** `set of char` (decimal `[#65]`, range `['A'..'Z']`, hex `[#$41]`
  — all forms) → **garbage**.
- With the set const, `c in C` also returns wrong (0 where it should be 1), while
  a *literal* `#$10 in C` evaluates correctly. So it is the **char-variable**
  path that breaks, not the set/`in` logic itself.

Hex-independent (decimal `#65` reproduces), so this is NOT the recently-fixed
`#$` hex-char literal bug — it is a separate codegen issue tied to the presence
of a `set of char` typed constant.

## Likely area

The `set of char` constant's data emission / addressing appears to clobber or
mis-base the char-variable access (the garbage looks like an address). Suspect
the constant-pool / global-data layout for set constants, or `Ord`/char load
picking up the set const's base. Reproduces with a single set const + single
char var, so it should reduce cleanly.

## Related const-codegen quirks (same family, found alongside)

Indexing/typed-const issues that smell like the same const-data handling — record
here, split out if they prove independent:

- **Untyped string const, indexed** → wrong char. `const t = 'ABCDEF'; c := t[2]`
  compiles but `c` is garbage (not `'B'`). Worked around in
  `lib/rtl/sysutils.IntToHex` by computing the hex digit arithmetically instead
  of indexing a const table.
- **Typed string const with initializer** → parse error. `const t: string =
  'ABCDEF';` → `Expected: begin, but got: ABCDEF`. Likely a separate parser gap
  (typed-const string initializer), noted for triage.

## Done when

- `Ord(c)` and `c in C` are correct in the presence of one or more `set of char`
  typed constants (all element forms).
- Regression test under `make test` (set-of-char const + char var: `Ord`, `in`
  with a variable operand, multiple consts).
- Self-host fixedpoint byte-identical.

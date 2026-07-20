---
track: N
prio: 55
type: feature
---

# NilPy: string methods (.upper/.lower/.strip/.split/.join/.startswith...)

Part of [[feature-nilpy-corpus-uforth]] milestone 1. Current uforth wall
(with [[feature-rtti-field-reflection]]) at uforth.py:190
`return str(t).upper()` / `t.word.name.upper()`.

Design sketch: method-call syntax on str-typed expressions desugars to
pylib functions (pystr_upper(s), ...), implemented in Pascal over
managed strings. Census uforth's actual set first; CPython is the oracle
(unicode-aware upper() can be ASCII-only v1 with a note — uforth words
are mostly ASCII + emoji, and emoji are case-stable).

Related: str(x) builtin already exists for scalars; needs variant + object
forms (repr-ish) eventually.

## Census (2026-07-19) — uforth.py + .UFO PYTHON blocks

`.upper()` 40 · `.join()` 25 · `.encode()`/`.decode()` 15 · `.find()` 10 ·
`.startswith()`+`.endswith()` 11 · `.isspace()` 6 · `.strip()`/`.rstrip()` 4 ·
`.rjust()` 3 · `.split()`/`.splitlines()` 2

Two scoping calls:

- **`.encode()`/`.decode()` are OUT of this ticket** despite ranking third.
  They are not str→str: they need a bytes model, which uforth also leans on
  via `int.from_bytes`/`to_bytes` (25 more uses). Separate feature.
- `.join()` / `.split()` / `.splitlines()` cross into `TPyList`, unlike the
  pure str→str set — they are the ones that will need list interop.

## Unit 1 — .upper() / .lower() — DONE

Mechanism (reusable for every later unit):

- `pylib.pas`: `pystr_upper` / `pystr_lower`, ASCII-only (documented in the
  unit; non-ASCII bytes pass through UNCHANGED, so emoji-bearing uforth word
  names are safe). CPython's full-Unicode case mapping needs a table pylib
  does not carry yet.
- `pyparser.inc`: `PyParseStrMethod` owns the name→pylib table and the arity
  check. **Adding a method = one row here plus the pylib function.**
- TWO parse routes, because base forms differ: an ident/field base is an
  lvalue and reaches the shared parser's postfix `.member` path (hook filed as
  [[feature-a-nilpy-str-method-parser-hook]]); a literal or CALL RESULT is not
  an lvalue and is caught by a tail loop in `PyParseBitOperand`. uforth needs
  both — `str(t).upper()` is a call result, `t.word.name.upper()` a field.
- `PyInferExprType` gained a matching case, else an inferred local widens to
  variant and scalar-loads its TAG on return. **Keep it in step with
  PyParseStrMethod's table.**

Verified against the CPython oracle (`python3 test_nilpy_str_methods.npy`
diffed against the compiled binary): ident / literal / call-result /
user-function-result / field bases, chaining both directions, empty string,
already-cased input, digits+punctuation, non-ASCII passthrough, and the
receiver staying unmodified.

Gate: `test-nilpy` GREEN, `--tier quick` GREEN, self-host byte-identical.

## Next units

`.strip()`/`.rstrip()`/`.lstrip()`, then `.startswith()`/`.endswith()`,
`.find()`, `.isspace()`, then the list-interop trio (`.join()`, `.split()`,
`.splitlines()`). Blocker found alongside: [[feature-nilpy-len-of-str]].

## Unit 2 — strip/lstrip/rstrip, startswith/endswith, find, isspace — DONE

The table moved into `PyStrMethodInfo`, now the single source of truth read by
BOTH the desugar and the inference scanner, so those two can no longer drift
(they were separate lists after unit 1 — a latent bug).

CPython semantics deliberately encoded, each of which Pascal would get wrong:

- `find` is **0-based** and returns **-1** when absent. Pascal's `Pos` is
  1-based returning 0, so passing it through would be off by one AND make
  "not found" read as "found at index 0".
- `"".isspace()` is **False** — no vacuous truth.
- `"".startswith("")` / `x.endswith("")` are True.

### Three bugs this unit surfaced

1. **Precedence (mine, silent).** The non-lvalue route was first hooked in
   `PyParseBitOperand`, i.e. AFTER the additive layer, so
   `"a" + "b".upper()` parsed as `("a" + "b").upper()` and printed `AB`
   where CPython prints `aB`. A method binds tighter than `+`: the hook
   belongs at FACTOR level. Caught only by diffing against the oracle.
2. **67 exit points (mine).** Moving the hook to the tail of `ParseFactor`
   silently missed most bases, because that body has 67 `Exit`s —
   `str(t).upper()`, the actual uforth shape, was one of them. Fixed by
   renaming the body to `ParseFactorCore` and wrapping it, so the suffix
   applies however the core returned.
3. **tyChar bases.** Python has no char type, but the shared lexer types a
   one-char literal as `tyChar`. Handled by an explicit `pystr_ofchar` call
   rather than the implicit char->string conversion, which keys on node SHAPE
   not type (the literal shape converted, the subscript shape did not, giving
   a silent NUL) — `project_string_conversion_shape_blindspot_pattern`.

### Blocker found, filed urgent

[[bug-nilpy-str-index-off-by-one]] — NilPy string subscripts are 1-BASED, so
`s[0]` reads a NUL and every index is one character early. Pre-existing, silent,
and it invalidates any corpus result touching the 123 uforth subscript sites.
`s[0].upper()` is deliberately NOT in the regression test yet: adding it now
would freeze the wrong answer.

Gate: `test-nilpy` GREEN, `--tier quick` GREEN, self-host byte-identical,
whole test file diffed against CPython.

## Unit 3 — join / split / splitlines (+ len on str) — DONE

The list-interop trio, plus [[feature-nilpy-len-of-str]] which they need to be
useful.

CPython semantics that are NOT interchangeable and are each encoded:

- `split()` (no arg) splits on RUNS of whitespace and DROPS empty fields:
  `"".split()` and `"   ".split()` are `[]`. `split(sep)` splits on an exact
  separator and KEEPS them: `"a,,b".split(",")` is `["a","","b"]`,
  `"".split(",")` is `[""]`. Two different algorithms, so two pylib functions
  chosen by argument count — not one with a default.
- `splitlines()` drops the field a TRAILING newline would produce:
  `"a\n".splitlines()` is `["a"]`, unlike `"a\n".split("\n")`.
- `join` raises TypeError on a non-str item rather than stringifying it.
  Matched, so a real type error stays an error instead of becoming plausible
  wrong output.

### Three bugs this unit surfaced

1. **Aliasing (silent, wrong values).** The split functions first built each
   field in a reused `cur` accumulator and appended that. A list slot stores
   the variant's string PAYLOAD POINTER, so all three elements ended up
   aliasing the accumulator's final contents — `parts[0]` returned `"c"`.
   Every element is now a fresh `Copy()` of the source, which also removes the
   O(n^2) concatenation.
2. **Class identity in inference (segfault).** A str method returning tyClass
   needs `PyInferLastCi` set to TPyList, else the inferred local carries
   tyClass with no identity, `len()` picks the AnsiString overload over the
   TPyList one, and reads a class pointer as a string handle.
3. **Literal bases were invisible to inference.** `PyInferExprType`'s scan only
   inspects IDENT tokens, so `"a,b".split(",")` never reached the str-method
   case and produced an untyped local — same segfault as (2), different cause.
   A literal-base branch now runs before the ident dispatch.

Gate: `test-nilpy` GREEN, `--tier quick` GREEN, self-host byte-identical,
**FPC bootstrap clean + byte-identical fixedpoint** (added to this unit's gate
after unit 1 broke it invisibly), whole test file diffed against CPython.

## Remaining — PARKED to backlog 2026-07-20

Moved out of `working/` because nobody is on it. Units 1-3 are done and
gated; what is left is small and independent, so this is pickup-ready rather
than half-applied.

**Left in scope: `.rjust()` — 3 sites, all in the .UFO stdlib**
(`IO.UFO` x2, `MATH.UFO` x1), which is why `grep` over `uforth.py` alone shows
zero. One row in `PyStrMethodInfo` plus one pylib function, per this ticket's
own "adding a method =" rule. `.ljust()`/`.center()` are absent from the
corpus and not worth pre-empting.

**Out of scope, deliberately:** `.encode()`/`.decode()` — 16 sites across
uforth.py and the .UFO blocks, but they are not str->str and need a bytes
model. The bytes core landed separately (TPyBytes, 6468ff22); wire them up
under [[feature-nilpy-bytes-and-slices]], not here.

**Blocked/related, both filed:** [[bug-nilpy-subscript-on-literal]] (`"abc"[1]`
does not parse — needs the shared ParseFactor hook, so Track A-adjacent).
[[bug-nilpy-string-local-truncates-at-255]] limits what any of these methods
can build.

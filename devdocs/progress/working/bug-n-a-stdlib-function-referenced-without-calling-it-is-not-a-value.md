---
slug: bug-n-a-stdlib-function-referenced-without-calling-it-is-not-a-value
track: N
type: bug
prio: 65
status: working
owner: frankB
created: 2026-09-10
found-by: frankuser
tags: [nilpy, lekkerzeilen, stdlib, values]
blocked-by: []
summary: "FIXED 2026-09-10 (compiler binary `de51b67ba86b`). `_sin = math.sin` gave `no member sin came of the qualifier math`; lekkerzeilen/scenery is now clean. THE TICKET'S GUESS ABOUT THE MECHANISM WAS WRONG AND THAT IS THE USEFUL PART: it predicted the same gate as bug-n-os-environ-and-os-sep-are-not-values, and PyIsStdlibMemberValue knows only sys and os and was never consulted for math. Three unrelated mechanisms served one construct and TWO OF THEM WERE SILENT, not errors -- `f = string.capwords` printed an empty line where CPython prints `A B`, and `b = twinmod2.parse` answered a DIFFERENT MODULE'S function, because the all-Variant-overload scan searched every proc in the program by folded name. The CALL spelling of all of them was right throughout, which is why no probe of \"does an imported function work\" could see either. The compiler's own shim table (math.fabs, os.getcwd) stays a REFUSAL and now says why and what to write instead: the call site adds a domain guard, an overflow guard, an overload pick and an arity re-target that a bare reference has no arguments to apply."
---

# Measured 2026-09-10, compiler `61f8a78f8aae`, tree `31dad27bd`

```python
import math
print(math.sin(1.0))        # compiles, runs
```
```python
import math
_sin = math.sin             # error: no member sin came of the qualifier math
```

`math.atan2` is refused in BOTH forms and is a genuinely absent name
(`feature-nilpy-math-module-twelve-absent-names-measured`). `math.sin` is
PRESENT — so this is not a missing-name ticket, and a probe that used `atan2`
would have confounded the two. The probe must use a name that exists.

# Why it is the same animal as the Pascal bug fixed today

`ad7c03b03` (Track P): a bare method name in argument position reached the
reference door, built a correct node, and the committed parse took the CALL path
instead. Here the call path works and the reference path does not. Both are
**one concept served by two mechanisms**, which `normalise-dont-special-case.md`
names as the shape where the second path is the one that stays broken.

# Relationship to the os ticket — same gate, do not fix twice

`bug-n-os-environ-and-os-sep-are-not-values` measured `PyIsStdlibMemberValue` as
recognising exactly three `os` members, so every `os` DATA attribute fails. Its
summary says *"while its functions work"*. That holds for a CALLED function and
this ticket is the counterexample for an uncalled one. **Whoever takes either
should look at both**: a gate that enumerates members is the mechanism, and the
fix that makes `os.sep` a value is likely the fix that makes `math.sin` one.

Confirmed live in the same census: `session` fails with
`undefined variable (os)`, which is the os ticket's exact signature.

# Cost, measured rather than asserted

One module in the lekkerzeilen census (`scenery`) today, and it took a
previously-clean module red. The idiom is common in any Python hot loop, so the
population is "real code that cares about speed" rather than anything exotic.

# RESOLVED 2026-09-10 — frankB, compiler `de51b67ba86b`

`_sin = math.sin` compiles and runs. lekkerzeilen/scenery is CLEAN — it
COMPILES END TO END, not "advanced to a new wall", which is the only reason it
is quoted here at all. CLAUDE.md's first-failure census rule applies to
everything else in that corpus and to this ticket too: a count of subjects
naming a wall is not a count of work, and nothing here claims one. The sizing
that does mean something is at the bottom of this note — the corpus writes this
construct ONCE.

**The ticket's guess about the mechanism was wrong, and the wrong guess is worth
keeping**: it predicted the same gate as
[[bug-n-os-environ-and-os-sep-are-not-values]] — *"the fix that makes `os.sep` a
value is likely the fix that makes `math.sin` one"*. `PyIsStdlibMemberValue`
knows only `sys` and `os` and was never consulted for `math`. Three unrelated
mechanisms turned out to serve this one construct, and only by measuring each
door separately did they separate.

## Three doors, three different defects, and TWO OF THEM WERE SILENT

| door | before | cause |
| --- | --- | --- |
| an RTL unit member — `math.sin` | `no member sin came of the qualifier math` | the value door re-decided a case question the lookup had answered |
| a shim-unit member — `string.capwords` | **compiled and printed an EMPTY LINE** where CPython prints `A B`; `struct.calcsize` raised `bad char in struct format` | the callable wrapper was built only when every parameter was ALREADY a Variant |
| a `.py` module member — `twinmod2.parse`, `casemod.Pick` | **compiled and answered ANOTHER MODULE'S function** | the all-Variant-overload scan searched every proc in the program by folded name |
| the compiler's shim table — `math.fabs`, `os.getcwd` | `no member fabs came of the qualifier math` / `undefined variable (os)` | reached by name, not through a unit — **left a refusal, deliberately, see below** |

The CALL spelling of every one of these was correct throughout. That is what
made the two silent rows invisible: no probe of *"does an imported function
work"* can see a defect that only appears when the function is not called.

## The four changes

1. **`PyFindVariantParamOverload` is scoped to the proc's own unit and honours
   `ProcCaseSensitive`.** It scanned every proc in the program for a `CaseEqual`
   name match and took the first. Measured at `df4aebdbbf51`, against CPython on
   the same sources: two modules each declaring `def parse(x)` — `b =
   twinmod2.parse; b(1)` answered `twin 1`, twinmod's; one module declaring
   `pick` and `Pick` — `zz = casemod.Pick; zz(2)` answered `lower 2`, pick's.
   The caller already holds the right proc in the right unit; this scan exists
   only to prefer a same-arity all-Variant OVERLOAD, and an overload lives
   beside its proc. The name test is now the pair-shaped one symtab.inc uses in
   a dozen places — exact, or folded only when the candidate's own registration
   says it is case-insensitive. This lookup carried only the FOLDED half, the
   mirror of the one CLAUDE.md records as carrying only the exact half.

2. **`PyMakeFuncValueFor` wraps a callee whose parameters are Variant-COERCIBLE,
   not only ones already Variant.** The else arm of that gate is not "no
   wrapper" but "box the RAW ADDRESS and call it through the Variant ABI" — its
   own comment called that *"possibly-unsafe"* and left it. The precondition was
   never needed: the wrapper's body is `return realproc(a0, ...)` with `const
   aN: Variant` parameters, so the ordinary argument coercion runs on the way in
   exactly as the return coercion does on the way out. A class, record, set,
   pointer or open-array parameter, and a genuine `var`/`out` slot, still
   decline.

3. **The qualified-member value door stops overriding `FindProcInUnit`.** That
   lookup already tries exact first and folds only for a proc whose own
   registration permits it; the caller then threw the answer away with a blanket
   exact-case test. For a Python module the override was a no-op (a NilPy def is
   registered case-sensitive), and for a Pascal unit it discarded the only
   answer there is. `math.sin(0.5)` compiled on the line above because the CALL
   door folds case — one construct, two doors, two answers, with the value door
   the stricter one.

4. **A case-folded match must have PARAMETERS.** Found by this change's own
   probe, not by reasoning — the reasoning in (3) argued an explicit qualifier
   made an ambush impossible and was wrong about exactly this shape.
   `lib/rtl/math.pas` declares `function Pi: Double`, so `math.pi` fold-matched
   it and printed `<function at 0x54bd57>` where CPython prints
   3.141592653589793. **In Pascal a zero-argument function IS its own call**;
   in Python a bare reference is the function object. The two languages
   genuinely disagree, and for a Pascal unit the Pascal reading is what the
   author meant. An EXACT match is exempt, because only a case-sensitive
   registration produces one.

## What is NOT fixed, and why it is a refusal rather than a value

The compiler's own shim table (`PyStdlibCallProc`: `math.fabs`, `os.getcwd`,
`time.time`, `collections.deque`, `os.path.join`, ...) now gives a message
naming the reason and a one-line workaround, instead of `no member fabs came of
the qualifier math` and `undefined variable (os)` — diagnostics that blamed the
import for a name the CALL door compiles on the line above.

It is not turned into a value, and this is the part to re-measure before
changing it. `PyParseStdlibCall` does far more than name a proc: it picks the
all-Double overload for `Power`/`Exp`/`Sinh`/`Cosh`, wraps argument 0 in a
DOMAIN guard for `Sqrt`/`Ln`/`Log10`/`Log2`/`ArcSin`/`ArcCos`/`Power`, applies
an OVERFLOW guard, lowers `math.log(x, base)` to a quotient of two `Ln`, and
re-targets by ARITY *after* the arguments are parsed. A value form has no
arguments, so a callable built there would answer NaN where `math.sqrt(-1)`
raises ValueError and would call the two-argument `os.path.join` for a
three-argument call. **A silent wrong value is strictly worse than the refusal
it would replace** — and this change exists precisely because two silent wrong
values were sitting behind this construct already.

The workaround in the message is not a consolation: a lambda body goes through
the ordinary call lowering and therefore carries every guard. Measured, and
asserted in the Makefile so the message cannot start prescribing something that
stopped working: `lambda x: math.sqrt(x)` applied to -1.0 raises ValueError
exactly as the direct call does.

**Cost, measured rather than asserted:** the lekkerzeilen corpus writes a module
member in value position ONCE — `_sin = math.sin` at scenery.py:296 — and that
one is an RTL unit member, fixed here. A value form for the shim table has zero
corpus demand today, which is why it is a diagnostic and a ticket rather than
machinery.

## Found on the way, filed rather than fixed

[[bug-n-a-local-holding-a-callable-is-shadowed-by-a-pascal-intrinsic-at-the-call]]
(p70): `lo = f; lo(2)` prints `2` and `hi = f; hi(2)` prints `0` where CPython
prints f's result — the Pascal intrinsic answers at the call site. `abs` is the
same; `ord`, an equally Python builtin, is CORRECT, which is the control that
makes it a shadowing bug rather than a builtin-name policy. Not this door: the
value is built fine and the CALL re-reads the name. It surfaced because it made
a row of the new case-sensitivity test red for a reason nothing in that row
could explain, and the variable there is now named `lower_fn` and says why.

## Verification

- `test/test_nilpy_an_rtl_module_member_as_a_value.npy`, oracled against live
  CPython on the same file — no stored `.expected`. Every `math.pi` row in it is
  the control for change (4), which this change's first version broke.
- `test/test_nilpy_a_module_member_value_is_case_sensitive.npy` with
  `test/nilpy_units/casemod.npy`, whose `pick` and `Pick` have DIFFERENT bodies
  on purpose — two identical bodies would make the row unfalsifiable. It pins
  the claim changes (1) and (3) rest on: a NilPy def registers case-SENSITIVE
  (`DeclCaseSensitive = CaseSensitiveMode or NilPyUserCode`), so the fold that
  lets `math.sin` reach `Sin` cannot reach into a Python module.
- `twinmod`/`twinmod2`, both declaring `parse`, for the unit-scoping half.
- Two Makefile assertions on the shim refusal: the message must name the shim
  AND the workaround, and no binary may be produced; and the workaround must
  actually work, domain guard included.
- Positive controls measured against the pre-change compiler at `df4aebdbbf51`,
  not assumed: the RTL row is a compile error, the case row answers `lower 2`,
  the twin row answers `twin 1` twice, and the shim row emits the old
  qualifier message so the grep fails. The lambda row passed BEFORE the change
  too and is a did-not-break control, not evidence.

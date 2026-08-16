---
track: N
prio: 25
type: bug
blocked-by: []
summary: "`2.0 ** 10000` answers +inf where CPython raises OverflowError, and so does `1e300 * 1e300`. A program that catches OverflowError — the documented way to detect this in Python — silently gets an infinity instead and carries on."
status: done
owner: claude-acpn
---

# Float overflow answers `inf` where CPython raises `OverflowError`

Measured 2026-08-16 while working
[[bug-a-nilpy-star-star-has-its-own-low-precision-pow]]; pre-existing on the
pinned binary and on HEAD alike, and unrelated to that ticket's plumbing.

## Repro

```python
print(repr(2.0 ** 10000))   # CPython: OverflowError   NilPy: inf
print(repr(1e300 * 1e300))  # CPython: OverflowError   NilPy: inf
```

## Why it is a bug and not laxity

NilPy accepting what CPython REJECTS is a feature, not a defect — but this is
the other direction in disguise. Code that WORKS on CPython is code like

```python
try:
    scale = base ** exponent
except OverflowError:
    scale = FALLBACK
```

which is the documented way to detect this, and on NilPy the `except` never
runs and `scale` becomes `inf`. The wrong branch is taken silently, which is the
test in `devdocs/dev/nilpy-semantics-divergences.md` for "a program CPython
accepts and runs can observe it".

## Scope

Not pow-specific: the multiply does it too, so this is the general float
overflow policy rather than one operation. IEEE says +inf; CPython's float
arithmetic raises for `**` and for the C-level operations it wraps. Deciding
which of those NilPy follows — and whether it is worth a per-operation check on
every float multiply — is a design call, so it may want a `decide-` ticket
before any code.

Note that pxx's own Pascal side must keep IEEE semantics; whatever lands has to
be gated on `PyNodeIsUser`, not on `PyProgramMode`
(project_pyprogrammode_is_program_wide_not_user_code).

## FIXED 2026-08-16 — and the ticket's second row was wrong, which is what made it cheap

The "Scope" section above feared a per-operation check on every float multiply
and suggested a `decide-` ticket for it. Measuring CPython row by row removed
the question rather than answering it:

| form | CPython | was NilPy |
| --- | --- | --- |
| `1e300 * 1e300` | **inf** | inf — already agreed |
| `1e300 / 1e-300`, `1e300 + 1e300` | inf / 2e+300 | agreed |
| `2.0 ** 10000`, `1e300 ** 2` | OverflowError | inf |
| `math.exp(1000)`, `math.pow(10, 400)`, `math.sinh`/`cosh(1000)` | OverflowError | inf |
| `math.exp(float('inf'))`, `float('inf') ** 2` | **inf** | inf — agreed |
| `2.0 ** -10000`, `math.exp(-1000)` | 0.0 | agreed |

So the ticket's `1e300 * 1e300` row is struck: CPython does **not** raise there.
The rule is per-CALL — CPython checks errno/ERANGE on the C library calls it
wraps and on float pow — so the guard goes on the RESULT of those calls and
nowhere near `*`, `/` or `+`. No decide- ticket needed; no cost on arithmetic.

The half that a result-only check gets wrong is the **infinite input**:
`math.exp(inf)` is inf in CPython, not an error. So the guard takes the operands
too (`pyfloat_range_overflowed(v, a, b)` in pylib), and naming an operand twice
means parking it in a temp first.

**Both `**` routes**, deliberately: the static one (an operand statically float
→ the RTL's `Power`) and `pypow_v` (a variant receiver, a loop variable, a list
element, dispatched at run time). One without the other is two spellings of one
expression giving two answers, which is the shape this frontend keeps producing.

`math.exp`/`sinh`/`cosh` joined `PyStdlibCallProc`'s table so the call is BUILT
in `PyParseStdlibCall`, which is where a result guard can wrap it; that also
gives them the float-only overload lookup `Power` already had. Their values are
unchanged — verified against the pinned binary.

Gated on the NilPy lowering, so pxx's own Pascal keeps IEEE, as the ticket
requires.

**Out of scope, and NOT this bug:** `float(2 ** 10000)` still answers inf where
CPython raises. That is NilPy having no arbitrary-precision ints — the int
overflowed long before the conversion — and belongs to whatever ticket carries
bignums.

**Found on the way:** `1.5 ** f()` called `f()` twice. Filed and fixed as
[[bug-nilpy-the-float-power-operator-evaluates-its-exponent-twice]].

Gate: `test/test_nilpy_float_overflow_raises.npy` (all of the table above, both
`**` routes, and a call in the exponent to prove the guard did not eat a side
effect), diffed against CPython; the existing pow/math tests unchanged;
`gate.sh quick` green.

Note for the next reader: `test_nilpy_math_log` and `test_nilpy_math_domain_errors`
are RED in the tree today on `math.pow(2.0, 0.5)`'s last ulp — the PINNED binary
fails them identically, so that is [[bug-nilpy-float-pow-loses-a-ulp-vs-libm]]
and not this change.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.

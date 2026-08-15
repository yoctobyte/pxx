---
track: A
prio: 55
type: bug
blocked-by: [bug-nilpy-uses-math-breaks-abs-on-a-float]
summary: "NilPy's `x ** y` does NOT go through the RTL's Power — pypow_v carries its own hand-rolled series ln/exp in compiler/builtin/pylib.pas. Measured against CPython over 105 pairs: 18 exact, 48 within 16 ulp, 15 worse, worst 1282 ulp (`1.0001 ** 10000` = 2.718145926824356 against 2.7181459268249255). The comment justifying it says the value is 'about to be str()'d through a known-truncated float formatter anyway', and that formatter now prints full precision."
---

# `x ** y` in NilPy is its own pow, and it is ~1e-12 out

Found while verifying [[feature-b-rtl-fast-power-needs-a-hi-lo-log]], against
`stable_linux_amd64/default/pinned` **v339 /
f11e0ed9816edc1d57ef8ee6e6ab0e5b9885db6c**. Pre-existing; the Power work did not
cause it and does not touch it.

## Measured

The same `.npy` run under pxx and under CPython, 105 (base, exponent) pairs over
10 bases and 12 exponents:

| agreement with CPython | pairs |
| --- | --- |
| bit-identical | 18 |
| within 2 ulp | 39 |
| within 16 ulp | 33 |
| within 1024 ulp | 14 |
| worse | 1 |

```
1.0001 ** 10000  ->  2.718145926824356      CPython 2.7181459268249255   (1282 ulp)
2.718281828459045 ** 250 -> 3.746454614502636e+108  CPython 3.7464546145026233e+108
```

That first row is wrong in the **12th significant digit** — visible to anyone
who prints it, and it is the compound-interest shape, not a contrived one.

## Why, exactly

`pypow_v` (`compiler/builtin/pylib.pas:8048`) reaches `PyMathLn` / its exp
partner at line 7957, which are a hand-rolled series with this comment:

> Deliberately hand-rolled rather than `uses Math`: that unit declares its OWN
> `Max`/`Min` overloads ... Precision is bounded by the series/reduction below,
> not IEEE-exact, **which is fine for a value that is about to be str()'d
> through this compiler's own (separately, already known-truncated) float
> formatter anyway.**

Both halves of that are worth separating:

- The `uses Math` obstacle is **real** — pulling it into pylib shadowed pylib's
  own `max`/`min` overload set and regressed `test_nilpy_minmax`. Any fix has to
  deal with that rather than wish it away.
- The precision excuse is **stale**. NilPy's float repr now prints full
  precision: the divergence above is what `print(1.0001 ** 10000)` shows a user
  today. The premise the trade-off rested on is gone, so the trade-off should
  be revisited.

Meanwhile `lib/rtl/math.pas`'s `Power` answers that same row correctly
(2.7181459268249255, within 1 ulp of glibc across an 11,556-point sweep) — the
good implementation exists, three directories away, and `**` cannot see it.

## Fix shape

Two independent routes, and the first is much the smaller:

1. **Port the fdlibm kernels into pylib** the way `lib/rtl/math.pas` has them
   (`FastLnBits` / `FastExpD` / `FastLogHiLo` / `FastExpHiLoCore` are
   self-contained and need no `uses Math`). Copying is duplication, which this
   repo dislikes — but it is duplication of ~150 lines of constants-and-Horner
   that nothing else in either copy depends on, against a `uses` that is known
   to break the overload set.
2. **Fix the shadowing** so pylib can `uses Math` at all, and then `**` and
   `Power` are one implementation. This is the `normalise-dont-special-case.md`
   answer and the reason the two drifted in the first place; it is also the
   larger job, since it is really about how a unit's overload set merges.

Either way, add a `.npy` regression test diffed against CPython — the shape
`test/lib_codecs.npy` and `examples/shell/nilsh.npy` already use — so the two
implementations cannot silently disagree again.

## Note for whoever reads the Power ticket

[[feature-b-rtl-fast-power-needs-a-hi-lo-log]] says "`Power` sits under NilPy's
`x ** y`". That is **not true today**, and it is worth knowing before anyone
credits NilPy speedups to the RTL work: making `**` 26x faster and 1-ulp
accurate is this ticket, not that one.

## 2026-08-16 — prototyped, MEASURED, and NOT landed. The wall is bigger than the ticket says.

A working prototype exists and is kept as
`devdocs/dev/prototypes/nilpy-float-pow-via-rtl-power.patch` (apply with
`git apply`). It is not on master, and this section is why.

### What it does, and what it bought

Neither of the ticket's two routes: a THIRD one, which is smaller than both.
`math.pow` already resolves to the RTL's `Power` (see `PyStdlibShimName`), so
`**` was pointed at the same routine rather than either porting kernels or
merging overload sets:

1. `PyMakePow` lowers a STATICALLY float `**` to `Power` via
   `FindProcArityDouble` — the same call `math.pow` makes, and for the same
   reason (`Power(Integer, Integer)` is declared first and truncates).
2. A loop variable or list element is a VARIANT, so it reaches `pypow_v` at RUN
   time and no static intercept can see it. pylib cannot name `Power` (builtin
   unit), so a `PyPowHook` function pointer was added beside pypow_v and the
   frontend installs `@Power` as the program's first statement — the shape
   `builtinheap` already uses for its object finalizer.
3. `pypow_dom` keeps the two REFUSALS the move would otherwise have lost: the
   RTL's Power answers NaN for a negative base with a fractional exponent (a
   COMPLEX in CPython) and +inf for `0.0 ** -1` (a ZeroDivisionError). A silent
   wrong number where there used to be a sentence is the wrong trade.

Measured over 120 (base, exponent) pairs against CPython:

| | exact | within 1 ulp | worst |
| --- | --- | --- | --- |
| before | 78 | 98 | **84 ulp** |
| prototype | 107 | **120** | **1 ulp** |

`1.0001 ** 10000` moves from `2.718145926824356` to CPython's
`2.7181459268249255` — the headline of this ticket — in all three spellings
(literal, named, `**=`) AND through a loop.

### Why it is not landed: `math` cannot be pulled into a NilPy program at all

Every version of this needs `Power` linked, which needs the `math` unit in the
program. That breaks `abs`:

- `ParseUsesUnitAmbient('math')` → `abs(-1.5)` stops compiling:
  *"no overload of abs matches these arguments (Double); candidates:
  abs(LongInt)"*. Pulling it BEFORE pylib/pyeval instead of after changes
  nothing, so this is not the last-named-unit rule.
- `ParseUsesUnit('math')` (ordinary, not ambient) → it COMPILES and answers
  WRONG: `abs(-0.0)` gives `-0.0` where CPython gives `0.0`, and
  `abs([-0.0][0])` gives **6642640** — a pointer read as a number. Silently.

`test_nilpy_abs_minmax_sum_oracle.npy` catches both, which is the only reason
this was not pushed.

Worth knowing: an EXPLICIT `import math` plus `abs(-1.5)` compiles correctly on
HEAD and FAILS on the pinned binary, so the visibility work landed earlier on
2026-08-15 already fixed one arm of this. The ambient/implicit arm is still
broken, and the wrong-VALUE arm above is a different bug again.

### So the routes are now three, ranked

1. **A small builtin unit carrying Power's kernels**, which pylib may `uses`
   directly. This is the ticket's route 1, but confined: a private unit exposes
   no `Abs`/`Min`/`Max`/`Round` to collide with, so it sidesteps the wall
   instead of fighting it, and `pypow_v` calls it with no hook and no frontend
   change at all. `Power` needs `TDd`, `Dd2Prod`, `DdRint`, `FMod`,
   `FastLogHiLo`, `FastExpHiLoCore`, `DdBits` — bigger than the ~150 lines this
   ticket estimated, and still the smallest thing that works.
2. **Fix what `uses math` does to `abs`** and then apply the prototype
   unchanged. This is the `normalise-dont-special-case` answer and it is a real
   name-resolution bug worth its own ticket — the wrong VALUE arm especially.
   Filed as [[bug-nilpy-uses-math-breaks-abs-on-a-float]].
3. The prototype as-is, gated on the program not calling `abs`. Rejected: that
   is a rule nobody can predict from the source.

### Residual, whichever route lands

13 of the 120 pairs stay 1 ulp below CPython — the RTL `Power`'s own rounding,
not the plumbing. That is [[bug-nilpy-float-pow-loses-a-ulp-vs-libm]] and it is
where the remaining work is once `**` and `math.pow` are one answer.

Also measured and NOT this ticket: `2.0 ** 10000` answers `+inf` where CPython
raises `OverflowError`, on the pinned binary and on HEAD alike — a general float
policy divergence (`1e300 * 1e300` does the same). Filed as
[[bug-nilpy-float-overflow-answers-inf-where-cpython-raises]].

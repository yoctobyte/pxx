---
track: A
prio: 55
type: bug
blocked-by: []
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

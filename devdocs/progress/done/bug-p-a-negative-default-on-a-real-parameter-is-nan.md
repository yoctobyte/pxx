---
track: P
prio: 70
type: bug
---

# A negative default on a real parameter is NaN (and `= -1.5` does not parse)

Found 2026-10-27 chasing songformatter's report that `create_rectangle(...,
outline="red")` drew no outline. itemcget said outline=red, but the item's
width was 0.0 where CPython's is 1.0.

    function g(w: Double = -1): Double;   { g() returned NaN }
    function h(w: Double = -1.5): Double; { "expected ')' before '1.5'" }

**Cause.** ParseParamDefaultValue sent a real literal down the float arm (stored
as IEEE bits) and EVERYTHING else down the ordinal ConstEval. The call site
(DefaultArgValueNode) reads a non-float default as an INT_LIT, so for a Double
parameter the integer -1's all-ones bits were read as NaN, and `= 3` was a
denormal. ConstEval has no real factor, so `-1.5` (unary minus before a real)
did not parse at all. Both Pascal and NilPy callers were affected, and pin v452
behaves the same way, so this is long-standing.

tkinter.pas uses `width: Double = -1` as its "not given" sentinel and tests it
with `d < 0`. NaN fails that test, so Tk got `-width nan` and drew every
create_rectangle/create_oval/create_polygon outline at width 0, i.e. invisible.

**Fix.** A real-typed parameter's default (anything but a set or string
literal) goes through ConstEvalF and is stored as IEEE bits with isFloat set.
That covers `-1`, `3`, `-1.5`, `C * 2` and named real consts.

Test: test/test_real_param_default_is_a_real.pas. Its output is byte-identical
to fpc 3.2.2's. After the fix, songformatter's outline repro gives 800 red
pixels under Xvfb, the same as CPython.

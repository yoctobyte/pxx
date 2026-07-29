---
track: N
prio: 70
type: bug
---

# `lambda: f()` — a zero-parameter lambda cannot call a compiled def

```python
import tkinter as tk
root = tk.Tk()
def body():
    print("in lam")
root.after(300, lambda: body())
root.mainloop()
```

dies with

```
pyeval: unknown call: body()
```

and takes the process with it (the Tk event loop never comes back).

## Why

`PyParseLambdaStub` LIFTS a lambda to a real compiled proc only when
`nParams = 1` (pyparser.inc ~3667). A zero-parameter lambda therefore always
falls to the **pyeval closure** fallback, and the interpreter can only call what
it knows — interpreted defs, builtins, and methods on a captured object. A
compiled top-level `def` is not in that set.

What DOES work through the closure path (verified): `lambda: print(...)`,
`lambda: obj.method()`, reading a captured field (`lambda: print(app.n)`). What
does not: calling a top-level or nested `def`, and `lambda: root.destroy()`.

This is what leaves songformatter's preview blank — the redraw is armed as
`cv.after(120, lambda: draw(cv.winfo_width()))`, and `draw` is a def.

## What was tried and REVERTED (do not repeat as-is)

Extending the lift to `nParams <= 1` with an unused own parameter. The lambda
body then runs (the "in lam" print appears), but the process SEGFAULTS inside
`pyboundfn_call_ptr` right after, in the variant tag-dispatch that follows the
call — and it also breaks the previously-clean `lambda: obj.method()` case.
Registering the lifted proc as a Variant-returning FUNCTION instead of a
procedure (so its ABI matches every other pyboundfn callee, an unannotated def
returning a Variant) did NOT fix the crash.

So the lift itself is the right direction, but the bridge's contract needs
sorting out first: `pyboundfn_call_ptr` calls every wrapped callee through
`TBF1..TBF13`, which are now Variant-returning (45fc761), while the lifted
lambda shell is registered as a procedure returning tyInteger. Establish ONE
ABI for everything a pyboundfn can wrap, then re-apply the `nParams <= 1` lift.

The alternative — teaching pyeval to call a compiled def by name — is a bigger
change and does not help the other interpreted-body limits.

## Gate

`make test-nilpy` + self-host fixedpoint, plus the snippet above printing
`in lam` and exiting cleanly, and `lambda: obj.method()` still working.

## Log
- 2026-07-29 — resolved, commit cab5a5179.

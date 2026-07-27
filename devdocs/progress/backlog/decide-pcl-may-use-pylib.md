---
summary: "decide: may a PCL library unit use pylib (Python runtime types) to accept Python-shaped arguments?"
type: decision
track: U
prio: 55
---

# May `lib/pcl/**` depend on pylib?

- **Type:** decision — **Track U**
- **Raised:** 2026-07-27, from songformatter's `settings.py`.

## The fork

`tkinter.create_window((0, 0), window=..., anchor="nw")` passes a TUPLE where the
façade declares two Integers. Real tkinter accepts both forms, and this project's
mission is compiling existing source AS-IS, so the app may not be edited.

To accept it, `lib/pcl/tkinter.pas` must read a TPyList out of a Variant — which
means a PCL unit `uses pylib`, pulling the Python runtime into a library that
Pascal programs also link.

## Options

1. **Let the façade use pylib** (recommended), scoped to a separate
   `tkinter`-facing helper unit so a plain Pascal PCL user never links it.
   Honest, local, no frontend magic. Cost: one more unit, and the layering rule
   "libraries are language-neutral" gets a documented exception.
2. **A frontend rule**: when a NilPy call passes a tuple literal to a routine
   whose next N parameters are ordinals, unpack it. Zero library cost, but it is
   invisible at the call site and would fire in places nobody intended.
3. **Leave it unsupported.** Costs an app-side edit, which the mission rules out.

## Why it needs YOU

It is a layering decision about what `lib/pcl` is allowed to depend on, not a
bug — and the same question will return for every Python-shaped argument any
future façade meets (colours as tuples, callbacks as callables).

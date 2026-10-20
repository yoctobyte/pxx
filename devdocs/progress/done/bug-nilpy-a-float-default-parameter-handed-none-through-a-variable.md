---
track: N
prio: 20
type: bug
---

# A float-default parameter handed None through a variable raised TypeError

Found 2026-10-20 in Vloot's GUI: `Graph(parent, height, colours, top=100.0)`
is built from a metrics table where `top` is None for the auto-scaled graphs,
and `draw()` asks `if top is None:`. The native build raised
`TypeError: expected a number, got NoneType` from the first timer tick.

**Cause:** PyParamTypeFromSites lets the default anchor a scalar claim (float
here) when a call site cannot be typed. That is deliberate (lekkerzeilen's
Vec3 fields are typed this way). It is a bet that the untypeable site passes
the default's type. Here the site passed a variable that is sometimes None. A
literal None at a site already vetoed the claim; None through a variable
could not.

**Fix:** before a scalar claim stands, look for a None test of the name
(`x is None`, `is not None`, `== None`, `!= None`, with or without a
receiver) in the class body, or in the def body for a plain function. If
there is one, make no claim, so the parameter stays a variant. The check
matches on the token name only, so it can veto more often than needed but
never less. A veto costs speed, never a wrong value. The `n.psites` debug
channel reports it.

Test: test_nilpy_float_default_handed_none_through_a_variable (the pin raises
on it).

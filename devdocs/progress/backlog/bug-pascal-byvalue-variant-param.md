---
track: A
prio: 40
type: bug
---

# By-VALUE Variant parameters are miscompiled (silent garbage)

Found while building pylib (2026-07-19): `procedure show2(v: Variant)` —
by value, no const — compiles but the callee reads garbage: `show2(2)`
printed 4264384, and a variant VAR passed by value printed its TAG.
`const v: Variant` (by-ref) is correct and is what pylib uses. Either
implement true 16-byte by-value marshalling or reject by-value Variant
params with a diagnostic. Repro: scratchpad p7.pas pattern in the
feature-nilpy-list session log.

---
track: N
prio: 20
type: bug
---

# A lambda capturing a str could not call one of the program's defs

Found 2026-10-20 in Vloot's hover rows: `lambda e: paint(hover_bg)` where
`hover_bg` is a str parameter answered `pyeval: unknown call: paint()` on
every <Enter>.

**Cause:** the lambda lifter refused to lift a lambda that captures a managed
string (a bound slot holds an Int64, and a borrowed string handle would
outlive its owner;
bug-nilpy-lifted-lambda-cannot-capture-a-managed-string). Such a lambda fell
back to the pyeval source closure, which handles expressions but knows no
user def.

**Fix:** the string is captured in a VARIANT slot instead.
`pyboundfn_bind_var` copies it into a slot the bound object owns, and the
lifted proc declares that parameter a variant. The lambda is compiled, so it
can call defs, and the string lives as long as the closure. The fallback
remains for when `pyboundfn_bind_var` is not loaded or the capture slots are
full.

Test: test_nilpy_lambda_capturing_a_str_calls_a_def (the pin prints
`pyeval: unknown call: tint()`).

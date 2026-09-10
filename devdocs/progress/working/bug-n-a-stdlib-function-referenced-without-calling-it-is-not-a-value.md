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
summary: "`_sin = math.sin` fails with `no member sin came of the qualifier math`, while `math.sin(1.0)` compiles and runs. A stdlib module function is reachable through the CALL door and not through the REFERENCE door -- the same double-door shape as the Pascal bare-method-name bug (ad7c03b03), in a different frontend. Same gate as bug-n-os-environ-and-os-sep-are-not-values (`PyIsStdlibMemberValue`), but a distinct arm: that ticket is about DATA attributes and says in its own summary that `its functions work`, which is true only of called ones. Found by re-measuring the lekkerzeilen census at HEAD: `scenery` was clean in the 2026-09-09 census and fails now, NOT from a regression -- the owner's own commit 7da065e (2026-09-10 10:50) added `_sin = math.sin`, which is the ordinary Python idiom for a hot-loop lookup (`math.sin` is called a third of a million times before the first frame there, per the comment above it)."
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

---
track: C
prio: 60
type: bug
status: backlog
owner: ""
created: 2026-09-10
found-by: frank-seven
tags: [c-frontend, builtins, float, corpus, duktape]
blocked-by: []
summary: "`__builtin_inf` is not declared, so the duktape 2.7.0 amalgamation fails to compile: `pascal26:899: error: call to undeclared function: __builtin_inf` in duk_bi_json.c. This is the ONLY thing standing between test-duktape and a verdict -- the job is otherwise wired, the source tree is present, and the target runs to the compile step in 4s. Measured 2026-09-10 at 89f5a6c8d on seven with the Track T watcher STOPPED, so the 4s is a clean number. test-duktape has never produced a verdict on any host (bug-t-six-real-program-jobs-are-in-no-tier-so-they-never-run); this is what its first one says."
---

# `__builtin_inf` is undeclared, so duktape cannot compile

```
$ make test-duktape
compiling duktape smoke ...
test-duktape: FAIL — compile
pascal26:899: error: call to undeclared function: __builtin_inf
  in: duk_bi_json.c
```

`__builtin_inf` is the GCC builtin returning positive infinity as a `double`.
duktape uses it in its JSON serialiser to construct the IEEE-754 infinity it
must then reject — so this is on the path of the very semantics
`feature-c-corpus-duktape` exists to exercise (GC + IEEE-754 double behaviour).

# Why this is worth a ticket rather than a one-line addition

It may well BE a one-line addition. The ticket is for the two things around it:

**The sibling builtins travel together.** `__builtin_inf` has `__builtin_inff`,
`__builtin_infl`, `__builtin_nan`, `__builtin_nans` and `__builtin_huge_val*`
beside it, and real C code reaches for whichever suits its type. Adding exactly
the one duktape names would make this job green and leave the next corpus at the
same wall — so the unit of work is the family, and which members are in scope is
a decision for this lane rather than for the seat that measured the red.

**A wrong value here is worse than a missing declaration.** An undeclared
function is a loud compile error; a builtin that returns the wrong bit pattern is
a silent numeric defect in exactly the code that cares about infinities. Whatever
lands should be checked against the bytes, not against "it compiled".

# Provenance and what this does NOT say

Measured on seven at `89f5a6c8d`, watcher stopped, as part of enrolling the six
never-run real-program jobs. A green here would say the curated duktape smoke
compiles, runs, exits 42 and is byte-exact against `duk_smoke.expected` — it says
nothing about duktape more broadly, and nothing about any other corpus.

`test-duktape` is currently in NO tier, so nothing re-measures this: the red will
neither move nor be noticed until the job is enrolled. Enrollment of the four
GREEN jobs is proceeding separately; this job and `test-quickjs` are held pending
an owner decision on whether they enroll visible-but-not-blocking (a
`pin-allowlist.tsv` entry naming this ticket) or wait until this lane clears them.
Auto-pin is armed, so an unallowlisted red here would stop pins firing at all.
See [[bug-c-malloc-usable-size-is-undeclared-so-quickjs-cannot-compile]] for the
other half, filed from the same measurement.

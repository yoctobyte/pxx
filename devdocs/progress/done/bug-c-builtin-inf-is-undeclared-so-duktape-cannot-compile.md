---
track: C
prio: 60
type: bug
status: done
owner: frankb-56
created: 2026-09-10
found-by: frank-seven
tags: [c-frontend, builtins, float, corpus, duktape]
blocked-by: []
summary: "RESOLVED 2026-09-16 (frankb-56, Track C). `__builtin_inf` is reduced in compiler/cparser.inc to an AN_FLOAT_LIT carrying the IEEE-754 double +Inf bit pattern 0x7FF0000000000000, beside __builtin_expect and __builtin_constant_p. It needs NOTHING below the parser -- no IR op, no codegen arm, no crtl helper -- and a crtl function would have been worse, because gcc's is a constant expression usable where a call is not. VERIFIED BY VALUE AND NOT ONLY BY COMPILING: a probe prints `x > 1e308, x > 0, x != 0` as 1 1 1 under pxx and 1 1 1 under gcc, and every column differs from what a 0.0 do-nothing answer gives, so it cannot pass by colliding with the default. THE TICKET'S CENTRAL CLAIM HELD: this was the only wall. `make test-duktape` now reports PASS -- curated JS smoke byte-exact, exit 0, which is test-duktape's FIRST verdict on any host. That target is a unity build of crtl + the duktape 2.7.0 amalgamation + duk_smoke.c, requires exit 42, and byte-compares stdout against duk_smoke.expected, so duktape actually ran JS. Confirmed it RAN rather than skipped: the recipe's absent-tree arm also exits 0. Measured on plexus with DUKTAPE_SRC pointed at an existing tree in a sibling checkout, because library_candidates/ is gitignored and this checkout has no duktape; nothing was fetched. THE SIBLING BUILTINS ARE DELIBERATELY NOT ADDED and that is a measurement, not an omission: grepping for __builtin_inff, __builtin_infl, __builtin_huge_val{,f} and __builtin_nan{,f} returns hits, and reading them shows every one is inside tcc/include/tccdefs.h where tcc DEFINES them for its own users -- definitions in another compiler's header, not calls anything here makes. Each is one line in the same shape if a corpus ever calls one."
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

## RESOLVED 2026-09-16 (frankb-56, Track C)

One line of demand, one line of supply, and the ticket was right that nothing
else stood behind it.

`__builtin_inf()` is reduced in `compiler/cparser.inc` to an `AN_FLOAT_LIT`
whose `ASTIVal` is the IEEE-754 double +Inf bit pattern. Two traps are noted at
the site because both would have produced the ORIGINAL error message again
rather than a new one: it takes no arguments, so the `and (argHead >= 0)` guard
that `__builtin_expect` and `alloca` carry must NOT be copied here; and it needs
no `FindProc` guard, unlike `alloca`, because `alloca` is a plain name a program
may define and `__builtin_inf` is reserved.

### The claim, kept in the two halves I promised to keep apart

| claim | evidence |
| --- | --- |
| the builtin compiles | duktape.c gets past :899; the wall moved to `main function not found`, which is correct for a library amalgamation |
| the builtin has the right VALUE | probe prints `1 1 1` under pxx AND under gcc; a 0.0 do-nothing answer gives `0 0 0` in every column |
| test-duktape is green | `test-duktape: PASS — curated JS smoke byte-exact`, exit 0 |

The third is the one the ticket cared about and it is a FIRST: its own summary
recorded that test-duktape had never produced a verdict on any host.

### Two things a later reader should not have to re-derive

**It ran; it did not skip.** The recipe's absent-tree arm prints a SKIP and
exits **0**, so a green exit proves nothing on its own. The log carries
`compiling duktape smoke ...`, which only the running arm prints.

**Nothing was fetched.** `library_candidates/` is gitignored and this checkout
has no duktape tree; `DUKTAPE_SRC` was pointed read-only at an existing tree in
a sibling checkout. So this result is reproducible here only with that override,
and on a host provisioned by `tools/install_lib_candidates.sh duktape` without
one.

## Log
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

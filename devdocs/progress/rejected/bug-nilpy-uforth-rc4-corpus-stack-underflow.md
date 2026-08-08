---
track: N
prio: 45
type: bug
status: rejected
summary: "WITHDRAWN — not a pxx bug. `ERROR: Stack underflow` came from MY harness invoking `INCLUDE testje.for`; uforth's INCLUDE POPS a string, so the correct form is `\"testje.for\" INCLUDE`. With that, all four RC4 corpora are byte-identical to CPython."
---

# WITHDRAWN: the RC4 underflow was a harness bug, not a compiler bug

Filed 2026-08-08 on the strength of

```
$ printf 'INCLUDE testje.for\nBYE\n' | ./uforth
ERROR: Stack underflow
```

`INCLUDE` in uforth is `( "filename" -- )` — it **pops** the filename off the
stack. `INCLUDE testje.for` therefore pops an empty stack, and the underflow is
the CORRECT answer. The proper spelling is `"testje.for" INCLUDE`, and with it:

```
testje.for       0 7 11 15 11      IDENTICAL to CPython
testjefixed.for  8A 6A D9 02 6A    IDENTICAL
testjefix2.for   DB 3D D9 CD AF    IDENTICAL
testjefix3.for   2D D6 65 30 F2    IDENTICAL
```

## Why it looked real

CPython appeared to accept the bad form and print the cipher output, which made
it look like a pxx-only failure. It did not: the comparison was run before the
`select.select` fix, so the two sides differed in prompt handling as well, and I
read one difference as evidence for another.

## What it cost, and the lesson

Nothing was changed on its account — the real bug in the same area
([[bug-nilpy-sequence-repeat-with-a-variant-count-falls-through-to-arithmetic]])
was found by bisecting the FILE, which immediately produced a failing line that
reproduced with the correct INCLUDE spelling too.

The lesson is the one this arc keeps teaching from the other direction: when a
corpus fails, **check that the harness speaks the corpus's language** before
concluding anything about the implementation under test. A wrong invocation and
a real defect look identical from the outside.

Superseded by [[bug-nilpy-uforth-drv-suite-last-line-and-file-words]] for what
IS still red in uforth's own suite.

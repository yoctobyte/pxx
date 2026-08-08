---
track: N
prio: 45
type: bug
summary: "uforth's four RC4 corpora all end in `ERROR: Stack underflow` where CPython prints the cipher output. The smoke gate (make test-uforth) is GREEN, so this is the next layer: a real Forth program, not a one-liner."
---

# uforth's RC4 corpora underflow the data stack

`make test-uforth` PASSES, and every one-liner probed so far matches CPython
(`value` / `TO` / `create` / `allot` / `c@` / `c!` / `and` / `mod`). The real
programs do not:

```
$ printf 'INCLUDE testje.for\nBYE\n' | ./uforth
ERROR: Stack underflow            # CPython: 0 7 11 15 11

testjefixed.for  -> CPython: 8A 6A D9 02 6A
testjefix2.for   -> CPython: DB 3D D9 CD AF
testjefix3.for   -> CPython: 2D D6 65 30 F2
```

All four are RC4 in Forth (`~/projects/uforth/testje*.for`), and all four fail
the same way, which suggests ONE missing/mis-lowered word rather than four bugs.

## What is already ruled out

Probed individually against the CPython oracle and matching: `0 value ii`,
`5 TO ii`, `create SArray 256 allot`, `65 SArray c!`, `SArray c@`, `255 255 and`,
`7 3 mod`. So the words the file's first twenty lines use are not the problem in
isolation — something further in, or a COMBINATION, is.

## Where to start

Bisect the FILE, not the source: feed `testje.for`'s definitions one at a time
(they are short colon words) and diff each against CPython, rather than reading
4300 lines of uforth. `\ ` comments make it easy to cut.

Then reach for the differential tools rather than reasoning:
`tools/pydiff.py` on a reduced `.npy` once the failing word is named, and
uforth's own `trace_log` (it has one) to see the stack depth per token — the
underflow message names no word, and that is the whole difficulty.

Watch the traps this arc has already sprung four times: a minimal repro that
PASSES does not clear the shape, because several of these bugs were UNDEFINED
behaviour that only bit once a block was reissued or a register happened to hold
the wrong value. If a reduction passes, vary it rather than concluding.

## Gate

All four `testje*.for` byte-identical to the CPython run, `make test-uforth`
still PASS, plus the per-fix loop.

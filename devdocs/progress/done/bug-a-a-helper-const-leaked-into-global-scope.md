---
slug: bug-a-a-helper-const-leaked-into-global-scope
track: P
prio: 60
type: bug
blocked-by: []
summary: "test-core's test_record_helper_for_string_b331 went red asserting a LEAK: an untyped const declared inside a helper was registered as an ordinary global, so `BITS` resolved bare at program scope. FPC 3.2.2 refuses that. ee388cf3a closed the hole as a side effect; the test was codifying the bug, so the assertion moved to what FPC does."
status: done
owner: claude-A
commit: PENDING-COMMIT
---

# A helper's const was visible as a bare global

## Reported

Track T, `test-core#src:test/test_record_helper_for_string_b331.pas`, bad
`2e7286e499d1`, last good `9ac7e74e367b`, 3 commits in range →
`ee388cf3a fix(P): a typed class/record const was global, so two owners shared
one slot`. Still red at HEAD when re-measured.

```
pascal26:71: error: undefined variable (BITS)
```

## The test was wrong, not the compiler

Line 71 read:

```pascal
  Writeln('bits:   ', BITS);                     { helper const (global scope) }
```

`BITS` is `const BITS = 32;` inside `TU32Helper = record helper for Cardinal`.
The comment says the quiet part: the test asserted that a helper's const is
visible as a plain global.

**Oracle** (FPC 3.2.2, on the `type helper for LongWord` spelling FPC accepts):

```
hc.pas(14,21) Error: (5000) Identifier not found "BITS"
```

FPC refuses the bare read and requires `TU32Helper.BITS`. So the red is a
divergence being CLOSED, not opened. `ee388cf3a` gave typed class/record consts
their own mangled backing symbol; the untyped helper const stopped being minted
as a bare global on the way past.

Same shape as `bug-a-a-units-mode-directive-turns-delphi-mode-off-for-the-program`,
found in the same tstate sweep: **the commit that exposes a defect is not the
commit that caused it**, and in both cases reverting would have restored the
bug. Worth stating together because two of two reds in one night had that
shape, and the reflex on a bisect result is to revert the named commit.

## Change

- The assertion moved to `TU32Helper.BITS` — what FPC accepts — with the
  history recorded at the site. The program's output is unchanged, so the
  Makefile's expected string did not move: the row was red on the COMPILE, and
  a stale expectation that still produces the right bytes is the kind that
  survives a long time.
- New `test/test_helper_const_not_global_fail.pas` asserts the bare form is
  REFUSED, in both arms — untyped (folded as a literal, no symbol) and typed
  (real storage, mangled backing name) reach a helper const through different
  machinery, so the regression can return on either. A sibling that only reads
  the const QUALIFIED cannot tell the difference, which is exactly how this
  went unnoticed.

No compiler change: the behaviour is already right.

## Honest note on the negative control

There isn't one, and that is better said than implied. `pinned` does reject the
new test, but on the line ABOVE — `class method not found: WIDTH` — because it
predates qualified typed-const access entirely and never reaches the bare read.
The test locks behaviour that is correct today; it is not evidence about
yesterday.

## Gate

`make compiler/pascal26` + both rows + `tools/gate.sh quick`.

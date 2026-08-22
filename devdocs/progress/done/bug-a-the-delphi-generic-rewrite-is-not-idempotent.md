---
track: A
prio: 60
type: bug
blocked-by: []
summary: "FIXED 2026-08-22, same day it landed. DelphiRewriteGenericUses rewrites `TFoo<T>` (spelled with the template's OWN parameter names) into `specialize TFoo<T>` IN PLACE — and then matched the same group again on the next round, inserting a second `specialize`, then a third, two tokens per round forever. Harmless while each template was swept exactly once; a live regression the moment 5179c4d4350b started running the sweep to a FIXED POINT. Caught by Track T: test-core#test_generic_inherit_delphi.pas and test-pascal-conformance#shard0/6, 1 commit in range, unambiguous."
---

# The mode-Delphi generic rewrite was not idempotent

- **Type:** bug (regression, compile-time refusal) — Track A
  (`compiler/pasparser_generic.inc`)
- **Status:** **fixed 2026-08-22**
- **Opened / closed:** 2026-08-22. Introduced by `5179c4d4350b`
  ([[bug-a-a-nested-inline-specialize-is-refused-outside-a-type-section]]) and
  reported by Track T against that exact sha.

## Symptom

```
$ pascal26 test/test_generic_inherit_delphi.pas
pascal26:10: error: generic specialization nested deeper than 16 levels (or a rewrite loop)
```

On a file nested **one** level deep. The message is the runaway guard added in
the same commit, doing its job — the parenthetical was the true half.

## Root cause

`DelphiRewriteGenericUses` has two match patterns: **A**, a bare `TFoo<Args>`
(mode-Delphi only), and **B**, an inline `specialize TFoo<Args>`.

When the arguments are the template's own parameter names (`TCounted<T> =
class(TBox<T>)`), the group cannot be collapsed to an alias — it resolves only
once the enclosing template is specialized — so pattern A's arm gives it the
objfpc spelling by **inserting the word `specialize` in front of it, in place**.

Next round, at that position, pattern B matches the new keyword and correctly
does nothing. But the loop's `Inc(i)` then lands on the `TFoo` `<` immediately
after it, **pattern A matches all over again**, and another `specialize` goes in.
Two tokens per round, forever, until the guard fired.

This was latent for as long as the procedure existed. It only mattered once
`5179c4d4350b` started calling it **repeatedly**, to a fixed point, so nested
inline specializations could collapse inner-first. **A rewrite that a
fixed-point loop calls more than once has to be idempotent**, and nothing had
ever required this one to be.

## Fix

One clause on pattern A: do not match when the preceding token is already the
`specialize` ident. The rewrite becomes idempotent, the fixed point converges on
the first unchanged round, and the runaway guard goes back to being unreachable.

## Verified

- `test/test_generic_inherit_delphi.pas` — the reported failure, now printing
  its expected five lines.
- `test/test_generic_nested_inline_specialize.pas` — the test the offending
  commit ADDED, still passing all six rows, so the fixed point still does the
  job it was introduced for.
- `test/test_generic_inherit.pas` (the objfpc twin) — passes.
- `tools/run_pascal_conformance.sh --shard 0/6` — **57 pass, 0 fail** (the other
  half of the Track T report; the tgeneric*.pp files in that shard were the same
  loop).
- `--shard 4/6`, the other open conformance regression — **58 pass, 0 fail**;
  attributed to a different sha but clean now.

## What this says about the gate, and it is not "widen it"

`gate.sh quick` was GREEN on the offending commit and is GREEN on this one:
the quick tier does not run `test-core` or the conformance suite, which is
exactly the trade the per-fix loop makes on purpose. The offload worked as
designed — T found it, attributed it to one sha with one commit in range, and
the fix took one clause. Total exposure was a few hours on master with a
compile-time refusal, which is the loud kind.

The transferable lesson is narrower and worth more: **when you change a
one-shot pass into a loop, the thing to verify first is idempotence, not depth.**
The guard I added in the same commit was written for runaway nesting, and the
runaway it caught was my own non-idempotent rewrite.

## Gate

`make compiler/pascal26` (byte-identical fixedpoint, 1 round) + `tools/gate.sh
quick`, plus the four files and two conformance shards above.

## Follow-up: both conformance shards verified clean at HEAD (2026-08-22)

Track T still lists two open regressions against this area, and both are stale:

- `test-pascal-conformance#shard0/6 bad=5179c4d4350b` — this bug's own sha.
- `test-pascal-conformance#shard4/6 bad=74d84a6ba449` — `fix(P): bodyless
  generic class, interface method directives, duplicate nested spec`, a
  *different* commit. It was never separately diagnosed; the shape is the same
  (the Delphi generic rewriter) and the fix here covers it.

Re-run at HEAD (`f9f1a42bc`), against the real corpus
`library_candidates/fpc-testsuite/tests/test` that the `full` tier shards:

```
shard 0/6: 57 pass, 0 fail, 30 skip, 5 auto-gated (of 92)
shard 4/6: 58 pass, 0 fail, 28 skip, 5 auto-gated (of 91)
```

Both green. T's entries should clear on its next `full` tier — it is 7 testable
commits behind and its newest full run is 6h old, so the open list is describing
a tree from before the fix, not this one. No action; recorded here so the next
reader does not re-diagnose a closed bug from a stale report.

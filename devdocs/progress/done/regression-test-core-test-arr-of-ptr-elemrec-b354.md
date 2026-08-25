---
prio: 70
track: P
status: done
owner: claude-A
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_arr_of_ptr_elemrec_b354.pas red at 10dada0b7689 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T16:38:27Z
- **Test source:** test/test_arr_of_ptr_elemrec_b354.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_arr_of_ptr_elemrec_b354.pas'` at 10dada0b7689fee546516eec7ea90d1da4256053

## Range
bad `10dada0b7689`, last good `d20300d288eb`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:51: error: "A": this value has no members (only records, classes, interfaces and variants do)
pascal26:51: error: "B": this value has no members (only records, classes, interfaces and variants do)
pascal26:51: error: "C": this value has no members (only records, classes, interfaces and variants do)
(tail)
pascal26:51: error: "A": this value has no members (only records, classes, interfaces and variants do)
  near: lst  i    >>> A    
pascal26:51: error: "B": this value has no members (only records, classes, interfaces and variants do)
  near: lst  i    >>> B    
pascal26:51: error: "C": this value has no members (only records, classes, interfaces and variants do)
  near: lst  i    >>> C   

```

## Diagnosis (Track A/P, 2026-08-25)

Self-inflicted by `582cdc934` (bug-p-a-member-on-a-computed-value-silently-reads-
the-values-own-bytes). That fix put a `recId = REC_NONE` refusal inside the SHARED
`RequireRecMember`, which is on all FOUR copies of member dispatch. Two of those
are DEREF sites where `REC_NONE` is normal and harmless.

Measured, not reasoned: a temporary site-tag on the four call sites shows the
refusal fires from **`pasparser_lval.inc:2710` (`ParseSelectors`)**, while the two
tests the guard was written for hit `pasparser_lval.inc:4204` and
`pasparser_expr.inc:1143` — the computed-receiver sites, and only those.

`lst[i]^.A` over an `array[0..3] of PInner` leaves the parser's running `recName`
at `REC_NONE` (the leaking-`LastTypePointerElemRec` shape this very test was
written for), yet the field still resolves correctly downstream — the pinned
binary compiles it and prints `10 20 30`. So the shared arm refused **valid**
code, which is strictly worse than the silent path it replaced.

Reduction (`/tmp/tt/r1..r3`): the trigger is a decoy pointer type + a pointer
LOCAL declared between the array alias and its use. Without the decoy the same
program compiles either way.

## Fix

`REC_NONE` means *"no record id HERE"*; only on a **computed value** does it also
mean *"and there never will be one"*. Split accordingly:

- new `RequireValueHasMembers` in `compiler/pasparser_call.inc`, holding the
  `REC_NONE` arm and its rationale;
- called from the two computed-receiver sites ONLY (`pasparser_lval.inc:4204`,
  `pasparser_expr.inc:1143`);
- `RequireRecMember` back to its pre-`582cdc934` body (the `>= REC_UCLASS_BASE`
  no-such-member arm), so the two deref sites are lax again.

Verified: `test_arr_of_ptr_elemrec_b354` prints `10 20 30`;
`test_computed_member_fail` and `test_chained_helper_member_fail` still refuse.
`tools/gate.sh quick` GREEN (self-host fixedpoint converged).

Doctrine note for the next reader: the `582cdc934` write-up justified the shared
placement with *"every reader names a FIELD offset"* and 141 lib units compiling
unchanged. That sweep never compiled `test/`, which is where the counterexample
lives — the widening was the guess, and Track T is what caught it.
- 2026-08-25 — resolved, commit PENDING-COMMIT.

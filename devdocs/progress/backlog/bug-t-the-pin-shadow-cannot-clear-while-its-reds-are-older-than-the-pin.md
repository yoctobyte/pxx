---
track: T
prio: 55
type: bug
blocked-by: []
summary: "pin_shadow answers `would_pin` from a raw red count, with no notion of a red whose CAUSE is already inside the current pin — so it is currently refusing every pin over 10 reds that were all red before the current pin too, six of them blocked on an unresolved Track U decision. A gate that cannot clear is not a gate."
---

# The pin shadow cannot clear while its reds are older than the pin

Filed 2026-08-19 by the coordinator, out of pin v366.

## What happened

`plexus.json:pin_shadow` at 19:34:58Z on `a15cb05fa9ce` said `qualifies: false`,
`would_pin: false`, `reds: 10`, `streak: 0`. The coordinator pinned v366 anyway —
**without having consulted the shadow**, which is a separate process failure and is
recorded in the roster. But when the ten were checked afterwards, every one of them
had a cause that is **already an ancestor of pin v365**:

| red job | cause | inside v365? |
| --- | --- | --- |
| `lib-test#…lib_mimic_xml_etree_elementtree.npy` | pre-existing; fails from source at the range's own last-good `9bfb7fcfac03` | yes |
| 6 x `test-nilpy#…test_cpyext_*.npy` | the import rule vs a real C extension module | yes |
| `test-nilpy#…test_nilpy_callable_to_str_param_fails.npy` | bisected to `9bbbbef6c` | yes |
| `test-riscv32#…test_cross_float.pas` | suspect `354f734c1` | yes |
| `tools-devtest#00` | a hardcoded cpu sentinel — **fixed in `93db54159`, which is inside v366** | fixed |

So the shadow was refusing v366 for a red set that was **equally red under v365**, and
v366 is strictly better on one of the ten.

## Why this is a tool bug and not just a bad night

**Six of the ten are the cpyext jobs, which are blocked on
[[decide-nilpy-import-rule-vs-a-cpyext-extension-module]] — a Track U decision only the
owner can make.** Until that is answered, `would_pin` can never become true. A gate whose
clearing condition is "a human answers a design question" will be overridden every time it
is consulted, and a gate that is always overridden stops being read at all. That is the
failure mode worth preventing, not this one pin.

## What the shadow is missing

It counts reds. It has no notion of:

1. **A red whose cause is already inside the current pin.** Such a red is not an argument
   against the next pin — every lane is already living with it. `git merge-base
   --is-ancestor <cause> <pin-commit>` is the whole test, when a cause is known.
2. **A red that is deliberately open**, i.e. attached to a filed ticket that says "not being
   fixed, awaiting a decision". Those should be an acknowledged baseline, not a veto.
3. **Whether the candidate is BETTER than the incumbent.** The interesting question for a pin
   is not "are there reds" but "does this binary have fewer, or different, reds than the one
   it replaces".

## Options

1. **Baseline the shadow against the current pin**: `would_pin` compares the candidate's red
   set to the incumbent's, and vetoes only on reds the incumbent does not have. Needs the
   incumbent's red set stored, which is the same data already published.
2. **An acknowledged-red list**: jobs with an open ticket marked awaiting-decision are
   excluded from the veto and reported separately as a standing baseline. Cheaper, but it is
   a manual list and will rot.
3. Leave it, and document that `would_pin` is advisory. Honest, but see the failure mode
   above — an always-false gate teaches people to skip it.

Recommend (1): it is the same question the straddle rule asks, and it needs no manual list.

## Note

This is downstream of [[bug-t-a-red-job-records-no-reason]] — the shadow cannot reason about
a red's cause partly because tstate stores a failed job as the bare string `"fail"`.

## Gate

Track T tooling change — T's own lane gate applies, plus the shadow's verdict exercised
against a recorded red set rather than argued.

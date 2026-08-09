---
prio: 40
track: N
type: chore
blocked-by: []
---

# `pylib.pas` calls eight helpers before defining them, with no forward declaration

- **Type:** chore (robustness / latent build tripwire) — **Track N**
- **Found:** 2026-08-09, after being bitten by the same shape three times in one
  session.
- **Owner:** —

## The hazard, and why it is not theoretical

`pylib.pas` is ~11k lines. A routine called from ABOVE its body, with no entry
in the unit's top declaration block and no `forward;`, **does not fail to
compile** — it links to a plausible wrong address
([[project_bodyless_procaddr_links_to_entry_minus_one]]).

Two things make that worse than a style issue:

1. **Such a call can pass its tests.** Three sites added earlier the same night
   (`pystr_translate`, `pystr_startswith_any`, `pystr_endswith_any` calling
   `PyVarText`) were CPython-diffed, green, and committed. They were forward
   uses the whole time.
2. **An unrelated edit elsewhere can turn them into hard errors.** Adding one
   forward declaration in the middle of the implementation section made
   `PySliceBounds` and `PyVarText` start failing to compile in routines nobody
   had touched. That is a build break with a cause nowhere near the symptom —
   the next person will spend the time re-deriving it that this ticket exists to
   save.

## The eight, measured

Called before their definition, with no declaration anywhere:

| helper | defined at | called from (examples) |
| --- | --- | --- |
| `PySliceBounds` | 6373 | `PyWindowStart` (2127) |
| `PyVarIsFloat` | 4770 | `pyvar_gt` (4109) |
| `PyVarAsFloat` | 4783 | `PyVarEq` (3356) |
| `PyVarText` | 5503 | `pyvar_gt`, `pyfloormod_v` |
| `PyIntOpOverflows` | 5588 | `pymul_v`, `pypow_v` |
| `PyPromoteIntArith` | — | `pymul_v` |
| `PyFmtExp` | 9244 | `pypercent_format` (8786) |
| `PyFmtG` | 9302 | `pypercent_format` |

(The routines added this session are all properly `forward;`-declared — checked.)

## Fix

Add a `forward;` declaration for each, **in the unit's TOP declaration block**,
not beside the implementation — a declaration dropped mid-file is what disturbed
resolution order in the first place. Mechanical, no behaviour change intended,
and the whole point is that it stops being possible to link one of these to the
wrong address.

## Worth pairing with a CHECK

The audit that found these is a ~30-line script: parse `^function|procedure`
implementations, collect the top-block and `forward;` declarations, and report
any call to a routine defined later that is in neither set. It has to handle
MULTI-LINE signatures — the first `;` is often inside the parameter list, which
is what made a naive version report false positives. Worth handing to Track T as
a lint, since the failure mode is silent by construction.

## Gate
`gate.sh quick` plus `make test-nilpy`: the change is declarations only, so any
behaviour difference at all is a bug in the change. Re-run the audit afterwards
and expect zero.

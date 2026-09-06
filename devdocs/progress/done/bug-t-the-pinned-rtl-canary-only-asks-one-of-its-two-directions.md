---
slug: bug-t-the-pinned-rtl-canary-only-asks-one-of-its-two-directions
track: T
prio: 55
type: bug
status: done
blocked-by: []
owner: ""
summary: "`gate.sh quick`'s `pinned_rtl_canary` sweeps all 54 lib/rtl root units, but only with the PIN; `compiler/pascal26` is invoked ONLY on units that already failed under the pin. So a unit the pin compiles and the TIP breaks is never handed to the tip at all, and the row is green. Measured 2026-09-06: `393fe0184` (a new `^T` refusal) broke `uses syncobjs` and went red fleet-wide; `syncobjs` is one of the 54 roots and the probe the sweep already generates for it is byte-for-byte the failing program, so a HEAD-side pass would have caught it on the row. Cost of the missing direction measured at 12.4s / 13.6s on two runs (-P 8, 54 roots, 0 failures at d11b8a1a9, compiler f555ef556761 built `converged after 2 round(s)`). NOT wired in by the filer: adding ~13s to every lane's quick gate is a widening of the per-fix loop and is not a tooling seat's call. RECOMMENDED SHAPE: gate it on `compiler/**` having uncommitted changes, the way the FPC seed canary in the same file already is -- a session with a clean `compiler/**` cannot be the one that broke the RTL, so it costs 13s to exactly the sessions that can cause this and nothing to anyone else."
---

# The pinned RTL canary asks "does the PIN fail where HEAD succeeds" and never the reverse

`tools/gate.sh`, `pinned_rtl_canary()`. The sweep itself is not the problem and is
the best-argued row in the file: it discovers roots rather than keeping a list
(after a one-file fixture missed 20 of 111 units), it costs ~18s, and its comment
block records three cheaper shapes that were measured and rejected.

**The asymmetry is one `if`:**

```sh
xargs -P 8 -I{} "$work/one.sh" {} "$work" "$pinabs" < "$roots" > "$fails"
if [ -s "$fails" ]; then          # <- only units the PIN could not compile
  ... ./compiler/pascal26 --threadsafe -Fulib/rtl "$work/probe_$u.pas" ...
```

The tip compiler appears only inside the retry that sorts pin-lag from ordinary
breakage. When the pin compiles everything, `$fails` is empty and
`compiler/pascal26` is never invoked on any unit.

## Why it matters, measured

`393fe0184` added a refusal for a `^T` whose T is never declared — a true premise
— and refused `uses syncobjs`, because the drain asked the name question from the
PROGRAM scope and a type in a transitively-used unit is not visible there.
`uses palsync` (one level down) compiled; `uses syncobjs` did not. Red fleet-wide,
two auto-filed tickets from one cause, reverted in `d11b8a1a9`.

**Both of the author's gates were green and neither could have been otherwise:**
`gate.sh quick` builds lib/rtl only through the compiler's own dependency set,
which never reaches syncobjs, and the pinned canary compiled all 54 roots fine
*with the pin*.

`syncobjs` **is** one of the 54 roots. The probe the sweep already writes for it is

```pascal
program probe;
uses syncobjs;
begin end.
```

which is the failing program. The instrument was standing on the defect and
looking the other way.

## The measurement, so nobody re-derives it

| | |
| --- | --- |
| lib/rtl units | 111 |
| roots (no other lib/rtl unit `uses` them) | 54 |
| HEAD-side sweep wall, `-P 8`, two runs | 12.4s, 13.6s |
| failing roots at `d11b8a1a9` | 0 |
| compiler | `f555ef556761`, built at `d11b8a1a9`, `converged after 2 round(s)` |

## What this ticket is NOT asking for

Not a wider gate for everyone. Adding ~13s to `quick` unconditionally changes the
per-fix loop for every lane, which is the owner's call and not a tooling seat's.
The recommended shape is the one the same file already uses for the FPC seed
canary: **run it only while `compiler/**` has uncommitted changes.** A session
with a clean `compiler/**` cannot have broken the RTL, so the cost lands on
exactly the population that can cause the defect.

Filed rather than fixed because the fix is a decision about everyone's loop, and
filed rather than left in a message because the author of the incident is
mid-re-land and a recommendation delivered by message has no reader once that
lands.

## RESOLVED by frankS, `ef96b48f8` — `gate(T): sweep lib/rtl with HEAD's compiler, the direction the pinned row cannot see`

Landed as its own commit, separate from the fix that occasioned it, and wired
better than this ticket asked for:

- **Armed off the MERGE-BASE with origin/master**, not `git diff HEAD` — the FPC
  seed canary's rule verbatim, so committed-but-unpushed is covered. The loop is
  as often edit→commit→gate→push as edit→gate→commit.
- **Failures are sorted against the pin instead of against an exclusion list**:
  fails-under-both prints as a note, only fails-under-HEAD-but-not-the-pin is
  RED. That is this ticket's own argument pointed the other way, and it means the
  row can never rot the way a maintained exclusion list does.
- **`rtl_roots` and `rtl_probe_script` are now shared helpers**, so the two rows
  asking opposite questions cannot disagree about what the population is.
- Both guards carried and branched on: discovery >= 20 roots, and an absent-type
  control that must fail to compile.

**And it ships with the control this ticket could not supply.** With
`DrainPendingPtrTargets` removed from `ParseUnit` and everything else kept, the
row goes **RED in 15s naming exactly `atexit`, `palparallel`, `palpthread`,
`syncobjs`**; restored, 0 of 54. A canary shown failing on the real defect, by
ablation, which is the whole subject of the incident that produced this ticket.

Cost: **0s** on a clone that did not touch `compiler/`, **~11-15s** on one that
did — which prices it out of the objection this ticket was filed to avoid, and is
why the fleet-wide question the filer declined to answer did not need answering.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 88156a7c3.
- **The change that resolves this is `ef96b48f8` (frankS), not the resolve commit above** — verified `git merge-base --is-ancestor ef96b48f8 origin/master` TRUE. The sibling half is NOT resolved and moved to [[task-t-two-standalone-checks-are-written-and-unwired-price-them-together]] so frankA's `c1961bc63` does not die inside a closed ticket.

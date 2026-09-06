---
slug: bug-t-the-pinned-rtl-canary-only-asks-one-of-its-two-directions
track: T
prio: 55
type: bug
status: backlog
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

## A SIBLING PROPOSAL ARRIVED THE SAME DAY — price them together, not one at a time

`tools/lowering_passthrough_census.py` (frankA, `c1961bc63`) is a second standalone
check written the same afternoon, deliberately NOT wired into `gate.sh` for the
same reason this one is not: a new fleet-wide gate step is Track T's to price.
It finds AST kinds whose value arm is a pass-through but which have no arm in
`IRLowerAddress` — the shape that made `v := Variant(y)` segfault, where a
consumer asking for an address silently gets contents. It runs standalone, exits
1, has two branched-on controls, and wiring it is one line.

**Recorded here so the two are priced as a pair.** Two agents each declining to
add a gate step on the way past is correct discipline and produces a predictable
failure: two good rows sitting unwired, each waiting for a decision nobody knows
they are holding, and each re-proposed in a fortnight by someone who did not find
the first. Whoever prices this row should look at that one in the same pass — the
budget question is *"how much may `quick` grow, and what buys the most"*, and it
cannot be answered one candidate at a time.

Both share the recommended shape: gate on `compiler/**` having uncommitted
changes, as the FPC seed canary already does, so the cost lands only on sessions
that can cause the defect.

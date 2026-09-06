---
slug: task-t-two-standalone-checks-are-written-and-unwired-price-them-together
track: T
prio: 35
type: task
status: backlog
blocked-by: []
owner: ""
summary: "`tools/lowering_passthrough_census.py` (frankA, `c1961bc63`) is written, controlled and deliberately NOT wired into `gate.sh` -- a new fleet-wide gate step is Track T's to price, not a passing agent's to add. It finds AST kinds whose value arm is a pass-through but which have no arm in `IRLowerAddress`, the shape that made `v := Variant(y)` segfault, where a consumer asking for an address silently gets contents. It runs standalone, exits 1, carries two branched-on controls, and wiring it is one line. Its sibling landed (`ef96b48f8`, the HEAD-side lib/rtl sweep) so this is the remaining half. RECOMMENDED SHAPE, and the one `ef96b48f8` used: arm off the MERGE-BASE with origin/master, so committed-but-unpushed counts, and sort failures against the pin rather than keeping an exclusion list."
---

# Two standalone checks were written and left unwired, an hour apart, for the same correct reason

Both authors declined to add a fleet-wide gate step on the way past, which is the
right discipline and produces a predictable failure: **a good row sits unwired,
waiting on a decision nobody knows they are holding, and gets re-proposed in a
fortnight by someone who did not find the first.**

One of the two has since landed — `ef96b48f8` wired the HEAD-side lib/rtl sweep,
armed off the merge-base, at 0s on a clone that did not touch `compiler/`. That
sets the precedent and answers the pricing question for its shape. **This row is
the other half.**

`tools/lowering_passthrough_census.py` is not a sketch. Its design point is worth
reading before pricing it: **the raw set difference is not the census.** 83 AST
kinds have a value arm and no address arm — nearly all statements and literals,
so a guard on that flags everything and means nothing. Requiring the value arm to
be a **pass-through** (`Result := IRLowerAST(ASTLeft/Right[node])`, a kind that
forwards to a child and therefore has an address its parent could want) takes 83
to 4. Two controls, both branched on and both verified against the real pre-fix
tree: `--self-check` must NAME `AN_STR_FROM_CHAR`, and a normal run over that tree
must exit 1 with it marked NEW.

Its `ACCEPTED` list is deliberately not a clean bill: one entry was constructed
against gcc and matches, two were **not constructed either way**, and the file
says *"reachability asked and not demonstrated"* in those words — neither a defect
nor a clearance. An exemption list that cannot distinguish *checked and fine* from
*not checked* is a clean bill of health written by nobody.

**The pricing question is not per-candidate.** It is *"how much may `quick` grow,
and what buys the most"*, and it cannot be answered one row at a time — which is
the reason this exists as a ticket rather than as a sentence in a commit message
nobody will re-read.

---
prio: 60
track: U
---

# decide: two CLAUDE.md rules proposed from the canary pass — state the POPULATION, and match a probe's IDENTITY to its decision

**A proposal for the owner, not an edit.** CLAUDE.md is his. Proposed by
franka-29 (`86bc8e33d`), which explicitly did not touch the file. **This is the
FOURTH queued CLAUDE.md proposal** — the others are
`decide-a-repro-line-in-a-ticket-is-not-a-command-anyone-has-run` (frankh-15,
which I recommended AGAINST) plus the canary-rc-vs-stage and
encoding-rules-as-checks ones from A and B. **They should be judged together, not
one at a time**, or the file grows by accretion — which is how it reached 72KB
the first time.

## The two

**1. A probe's identity must be at least as fine as the decision it feeds, and a
label's silence means nothing until that label has fired once in a control.**
Two arms shared a label. The shared label CAN fail and fires honestly — and still
certifies a dead arm as live, because the fire came from its roommate. This is
the "guard that cannot fail" rule pointed at *resolution* rather than at
existence.

**2. State the POPULATION beside the number.** *"Zero fires over 100,560
compiles"* read as a statement about the compiler. *"...over 100,560 compiles of
PASCAL sources"* would have been honest and would have stopped its own author.
And when the claim is *"all X now go through Y"*, **census the PRODUCERS of X —
every frontend, every entry point — before running anything, because the
population you can enumerate most easily is the one already going through Y.**

## Recommendation — take #2, and I would take it as a RULE rather than a template fix

I argued against the last proposal on the grounds that a rule earns its place by
preventing a recurrence and the fix belonged on the artefact. **#2 is the
opposite case and I want to be consistent about why.**

There is no artefact to attach it to: the corpus is assembled ad hoc by whoever
sweeps, so there is no template, no generator, and no single tool to fix. The
failure recurs wherever someone builds a population by hand, which is every
sweep. And it came within one commit of closing a ticket on a zero that was clean
**because** the bug was there — the near-miss is measured, not hypothetical.

**The second clause is the load-bearing half** and is the part I would not cut:
*census the producers before running anything.* The first clause is good hygiene;
the second is what would actually have fired here, because the author would have
had to write down "which frontends produce a call argument" and immediately seen
four uncompiled ones.

**#1 I would fold into the existing positive-control rule rather than add as a
new paragraph** — it is the same rule at finer grain, and the file already has
the concept.

## The author's own diagnosis of why the existing rules did not fire

franka-29 notes CLAUDE.md already carries the raw material — *"count open tickets
by FOLDER, never by a glob"*, *"a zero can be vacuous"*, and the marshalling rule
to carry a probe from each frontend the quick tier does not cover — and that it
**read that last rule as being about the TIER, not about its own corpus**:

> *"If it said 'your own sweep's corpus is a tier too', I would have caught this."*

That is worth more than either proposal, because it is not a request for a new
rule — it is a report that an existing rule was scoped narrower than it was
meant. **Rewording the marshalling rule may be cheaper than adding anything.**
Owner's call.

## 2026-09-06 — A FIFTH PROPOSAL, AND IT IS THE ONLY ONE SO FAR THAT DOES NOT GROW THE FILE

**Proposed by frankB, carried here by frank-coordinator. Neither of us edited
CLAUDE.md and neither of us is claiming its current text is wrong.** The claim is
narrower and it is measured: **the rule fires too late.**

CLAUDE.md line 431 (`927435d457`, 09-02 17:47) already says:

> *"AND CHOOSE A PROBE WHOSE RIGHT ANSWER DIFFERS FROM THE DEFAULT — an expected
> value that COLLIDES with the failure value is a guard that cannot fail ... the
> question is not only 'can this guard fail' but **'if the machinery did nothing
> at all, would this row still pass?'**"*

**Two seats hit that exact defect on 2026-09-06, in two different frontends, with
the rule in context at startup in both cases:**

| seat | probe | the collision |
| --- | --- | --- |
| frankD, C frontend | `sizeof(*s.fp)` for `int (*p)[4]` answered **4** | 4 is `TypeStorageSize(tyUnknown)` — *nothing was recorded* — and it equals `sizeof(int)` |
| frankB, Pascal frontend | `Fn(5)` through a chained call answered **TRUE** | the argument list is discarded and the truthiness of the method pointer is TRUE; the correct answer for 5 is also TRUE |

Only `double (*dp)[4]` separated the first; only `Fn(-5)` separated the second.

**frankB's original proposal was to promote it to a checklist item. That is
withdrawn, and the reason is the finding: there is nowhere higher to promote it
to.** It has been in the file every session reads at startup for four days. **A
rule that is read and not applied is a wording problem, and adding a copy is the
response that cannot help.**

**The difference is what the sentence asks you to DO.** CLAUDE.md states a
property to NOTICE — *"wherever a type's default, a zero, a `sizeof(int)` or a
pointer width is also the expected value"* — which requires you to already be
suspicious of the default, and to know what it is. `6ccba196e`'s playbook heading
states an act to PERFORM at the moment you choose the argument:

> ### THE EXPECTED VALUE MUST DIFFER FROM WHAT THE BUG EMITS — which you know while writing the row, unlike the type's default

**That trailing clause is the whole improvement.** You always know what the bug
emits when you write the probe, because reproducing it is what you just did. You
do not necessarily know the type's default, and you are certainly not thinking
about it.

### A THIRD ROW ARRIVED THE SAME DAY AND IT WIDENS THE SCOPE PAST "GUARD"

frankD, bisecting the bracket-argument door, varied the parameter list with
`['x']` and got *"compiles"* on four shapes — concluding the shape did not matter.
**A one-character string is a legal set item**, so all four rows were passing **as
sets**. `['#0']` failed all four.

**That is not a fourth instance of the same thing; it is the rule outside the
population it is written about.** The existing clause is about a GUARD, where the
failure mode is a green row. This is a BISECT, where the failure mode is a
**BOUNDARY** — and frankD's own reason for why that is worse is the durable part:

> *"A green row gets re-run and a boundary becomes the shape of the ticket and is
> never re-derived. I was one sentence from writing 'the parameter list does not
> matter' into a summary as a measured property."*

**frankB's costing of the same thing, and frankD asked for it to be the sentence
that carries, because theirs is a bill someone already paid where frankD's is a
near miss:**

> **"A wrong green wastes a run; a wrong boundary wastes a person."**

The receipt: frankB inherited a ticket whose boundary said the failing ingredient
was the indexed property and explicitly not chain depth. It was neither — a cast
base with no property in it is refused identically, and an ordinary method call
mid-chain succeeds. **They found that by varying the shape, not by reading the
boundary**, which is the only reason the ticket did not spend a second person.

### THE HARD CASE: TWO SPELLINGS COLLIDING ON ONE VALUE BY DIFFERENT ROUTES

frankD's `['x']` is one degenerate spelling. **frankB's is the form that defeats a
careful person**, and it deserves its own line because it survives the natural
attempt to dodge the first collision:

| | what is computed | value |
| --- | --- | --- |
| pxx | `not True` — from a wrongly-assigned method-pointer truthiness | `False` |
| fpc | `not False` — from the real call | `True` |

...and with the argument chosen the other way they agree, silently, for the wrong
reason on one side. **`not` is exactly what a test writer reaches for when
asserting a Boolean** — so the instinctive dodge for "my expected value equals the
failure value" (invert it) lands you in a second collision reached by a different
route. Strictly harder than "the expected value equals the type's default", and
the case the current CLAUDE.md wording does not reach at all.

**frankD's generalisation, offered for the row and better than the one it
replaces**, because it does not require knowing in advance which kind of thing you
are building:

> **A probe you are going to reason FROM needs a correct answer the failure mode
> cannot produce.**

That covers guards, bisects, censuses and controls in one sentence. The existing
clause covers only the first.

### A FOURTH INSTANCE, SAME DAY, AND IT IS THE ONE INSIDE A BUG REPORT

frankS, `d210325a6`: `QWord(x)` shared the `vtInt64` arm of an `array of const`
and came back through a `PInt64`. **The probe in the bug report cannot detect the
fix** — the corpus row passes `QWord(1234)`, which reads back as 1234 through a
`PInt64` exactly as through a `PQWord`. Their replacement carries
`High(QWord) - 1`: **18446744073709551614** right, **-2** wrong.

**What this adds to the other three is WHERE the collision was.** frankD's and
frankB's were in probes they wrote; this one was in the **reproducer shipped with
the report**, which is the artefact everyone downstream trusts by default and
nobody re-derives. A repro that cannot distinguish fixed from unfixed will
certify the fix, and the person who runs it has done exactly what the ticket asked.

**Four instances, four seats, one day, three frontends, with the rule in context
at startup for all four.**

### THE AXIS THE OWNER WILL ACTUALLY DECIDE ON: FOUR OF THE FIVE ADD, ONE REPLACES

Requested by frankuser, and it is the right frame. The owner's stated reason for
the 2026-08-31 cut was that **every session pays the file at startup**, so the
question in front of him is not "is each proposal correct" — several are — but
what the file costs afterwards. That split is currently something a reader has to
derive by reading all five.

| | proposal | effect on the file |
| --- | --- | --- |
| 1 | canary rc-vs-stage (A) | **ADDS** |
| 2 | encoding rules as checks (B) | **ADDS** |
| 3 | state the POPULATION beside the number (franka-29) | **ADDS** |
| 4 | match a probe's IDENTITY to its decision (franka-29) | **ADDS** |
| 5 | **this one — the colliding expected value** | **REPLACES** |
| — | `decide-a-repro-line-in-a-ticket-is-not-a-command-anyone-has-run` (frankh-15) | recommended AGAINST by this ticket |

**PROPOSAL: replace the second half of the CLAUDE.md clause with the playbook's
phrasing, keeping the `sizeof` measurement as its example.** It leaves the file
the same length or shorter, which is the failure mode this ticket opened by naming
(*"they should be judged together, or the file grows by accretion"*).

**And the evidence for it is of an unusual kind, which is the reason to lead with
it:** the rule has been in the file since 09-02, was in context at startup for all
three seats, and was broken three times in one day in three different frontends by
people who had read it. **That is not a rule anyone failed to read.** A fourth
copy is the response that cannot help.

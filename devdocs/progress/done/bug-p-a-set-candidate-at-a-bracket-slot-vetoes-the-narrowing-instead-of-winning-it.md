---
track: P
prio: 25
type: bug
status: done
owner: frankS
created: 2026-09-09
found-by: frankS
tags: [overload, sets, array-of-const]
blocked-by: []
summary: "FIXED 2026-09-09, hours after being filed, and the fix was two lines once the sibling landed. `BracketCandRank` gives a `tySet` parameter at a bracket slot rank 100 -- above `array of Integer`'s 90 -- when and only when the element list is all integer literals, which is fpc 3.2.2's measured rule in BOTH declaration orders: `set of Byte` against `array of Integer` runs the SET for `[7, 8]` and `[700, 800]`; against `array of string` it runs the SET for `[7, 8]` and the string array for `['a', 'b']`. THE PARSE SIDE NEEDED NO CHANGE, which is what this ticket had assumed it would and is why it was ranked as a coordinated two-site job: TryParseBracketArgForSlot is handed the CHOSEN Procs[] row, finds neither ParamIsVarRecArray nor ParamIsOpenArrayScalar on a set parameter, returns -1, and the argument reaches ParseExpr -- which parses `[7, 8]` as the set literal it now is. One row decides selection and parsing, so they cannot disagree. The veto still stands for every element list that cannot be classified, which is the case its own stated reasoning was about. CORRECTION CARRIED IN THE FIXTURE: against a set candidate fpc REFUSES a multi-character string element (\"Ordinal expression expected\") and accepts a one-character one -- \"string elements take the string array\" was generalised from single-character lists, the only ones measured. We accept the multi-character form and run the string body, which is us accepting what fpc rejects and not a defect. test_p_an_array_of_const_wins_a_bracket_argument now matches fpc on EVERY line; its `veto` row was the one pinned divergence in the file."
---

# A set candidate at a bracket slot vetoes the narrowing instead of winning it

```pascal
type TByteSet = set of Byte;
     TVeto = class
       procedure P(N: Integer; A: array of Integer); overload;
       procedure P(N: Integer; A: TByteSet); overload;
     end;
...
ve.P(2, [7, 8]);
```

| | |
| --- | --- |
| fpc 3.2.2 | `veto      set` |
| pxx | `veto      ints  cnt=2` |

Found while building the fixture for
[[bug-p-two-array-parameters-at-one-bracket-slot-are-decided-by-declaration-order]],
by including the veto path as a must-not-move control and comparing it against
fpc out of habit. The control was expected to be inert and turned out to be a
divergence.

## THE BLOCKER THIS TICKET SHARED WITH ITS SIBLING IS GONE — 2026-09-09

The sibling
[[bug-p-two-non-const-array-overloads-at-a-bracket-slot-cannot-be-ranked-by-element-type]]
is **closed**, and it closed by showing that the shared blocker was misnamed.
Both tickets said *"the probe cannot parse a `[...]`, so it cannot rank"*. True,
and it does not matter: fpc ranks by the elements' **class**, and a class is
readable from the tokens. `BracketArgElemClass` in `pasparser_call.inc` now
answers ORDINAL / REAL / STRING / CHAR / UNKNOWN, and `BracketCandRank` scores a
candidate against it.

**So the information this ticket was waiting for exists now.** What is left is
not a question about the argument; it is that the answer changes how the
argument is PARSED.

## The measured rule, so the next reader does not re-derive it

fpc 3.2.2, 2026-09-09, both declaration orders every row:

| set candidate against | elements | fpc picks |
| --- | --- | --- |
| `array of Integer` | `[7, 8]` | **the SET** |
| `array of Integer` | `[700, 800]` | **the SET** |
| `array of string` | `[7, 8]` | **the SET** |
| `array of string` | `['a', 'b']` | the string array |
| either | `[1.5, 2.5]` | refused — *"Ordinal expression expected"* |
| either | `[]` | refused — ambiguous |

So the rule is: **a set candidate takes a bracket slot whenever the elements are
ordinal, and loses when they are not.** That is `BEC_ORDINAL` → set, everything
else → set is not viable, which is two lines in `BracketCandRank`.

## Why it was NOT done with the sibling, and it is not effort

Naming the set candidate is not enough. `ParamIsVarRecArray` decides on the
PARSE side how `[...]` is read, and it applies the same veto so that *"the two
decisions cannot disagree about which spelling won"*. Rank the set here without
moving that, and the probe's reading and the committed parse disagree — which
is the single worst failure shape this file has, and the one
`devdocs/dev/debugging-playbook.md` records as a half-wired door: it does not
refuse, it agrees and then builds something else.

**The work is therefore: move the veto and the parse side together, in one
change, with a fixture that asserts the VALUE the set body sees.** A row that
only prints which body ran would pass with the argument built as an open array
and handed to a set parameter.

## Why the veto is not simply wrong

`ParamIsVarRecArray`'s comment states the rule: *"A SET parameter anywhere at
this slot vetoes it: then `[...]` really may be a set, and guessing the other
way would break a working call to buy this one."* That is still correct. What was
missing was the ability to look, and **that is no longer missing** — see the
section above. The veto's caution stays right for an UNKNOWN element list, which
is exactly where `BracketArgElemClass` still answers UNKNOWN.

## Why prio 15

The veto's comment claims nothing in the tree mixes the two spellings at one
slot. Re-measured 2026-09-09 and still true, so this costs nothing today. It is
recorded because the guard row now pins pxx's answer, and a pinned answer that
nobody has written down as a divergence is how a divergence becomes a belief.

## Not the case the parent ticket already settled

[[bug-p-two-array-parameters-at-one-bracket-slot-are-decided-by-declaration-order]]
records a NEIGHBOURING set case as settled and not a defect: with
`M(N: Integer; S: TCh)` and `M(N: Integer; A: array of const)` visible, fpc
calls `M(1, ['a'])` **ambiguous and refuses it** while we accept it as the set —
us accepting what fpc rejects is not a defect. Different candidate pair. Here
the competitor is `array of Integer`, fpc compiles it without complaint, and it
picks the SET. Re-measured against fpc 3.2.2 on 2026-09-09; both rows are true
and neither implies the other.

## Resolution, 2026-09-09 (frankS)

Two lines in `BracketCandRank`, once the sibling
[[bug-p-two-non-const-array-overloads-at-a-bracket-slot-cannot-be-ranked-by-element-type]]
had made the element class available:

```
if (cls = BEC_ORDINAL) and (ParamOwnKind(pi, pj) = tySet) then Result := 100;
```

100 rather than 90 is the whole rule — it has to beat `array of Integer` on the
same list.

### The expensive assumption this ticket carried, and it was wrong

The ticket said matching fpc *"changes how the argument is PARSED, not just
which candidate is named"*, and ranked itself as a coordinated two-site change
with a half-wired-door risk. **It is one site.**
`TryParseBracketArgForSlot` is handed the *chosen* `Procs[]` row; on a set
parameter it finds neither `ParamIsVarRecArray` nor `ParamIsOpenArrayScalar`,
returns -1, and the argument falls to `ParseExpr` — which parses `[7, 8]` as a
set. Selection and parsing read the same row, so the disagreement the ticket was
guarding against cannot occur.

**Both of this family's tickets over-estimated their blocker in the same
direction**, and both from reasoning about the machinery rather than reading it.
The sibling's blocker named the wrong input; this one named a second site that
does not need to move.

### The veto is not gone

It still applies to every element list `BracketArgElemClass` cannot classify —
anything that is not exactly one literal per element. That is precisely the
population the veto's own comment was written about: *"the `[...]` really may be
a set there, and guessing the other way would break a working call to buy this
one."* Where we can see the elements we no longer guess; where we cannot, we
still decline.

### A correction the fixture carries

Against a set candidate, fpc **refuses** a multi-character string element —
`['x', 'yz']` gives *"Ordinal expression expected"*, because it reads the
literal as a set and `'yz'` is not a member. It accepts `['a', 'b']` and runs
the string array. The rule as first written here, *"string elements take the
string array"*, was generalised from single-character lists, which were the only
ones in the 72-row matrix. We accept the multi-character form and run the string
body — us accepting what fpc rejects, so not a defect, but not a row an
fpc-oracle fixture may assert either. The fixture uses `['a', 'b']` and says
why.

### Guarded in two places

`test_p_a_bracket_slot_is_ranked_by_what_its_elements_are` gains six set rows,
both declaration orders, both directions of the rule; the set body **sums its
members** rather than announcing itself, because `set` alone would pass whether
the literal reached it as a set or as garbage handed to a set parameter.

And `test_p_an_array_of_const_wins_a_bracket_argument` now matches fpc on
**every** line. Its `veto` row held pxx's own answer under a loud label — the
file's one pinned divergence — and that is the argument for pinning a divergence
loudly rather than leaving it unwritten: it stayed exactly as long as it took to
measure the rule.

**Positive control, verified:** the pinned compiler answers `veto ints cnt=2`
for the same source where HEAD and fpc both answer `veto set`.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

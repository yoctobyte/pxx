---
track: P
prio: 25
type: bug
status: working
owner: frankS
created: 2026-09-09
found-by: frankS
tags: [overload, sets, array-of-const]
blocked-by: []
prio-note: "raised 15 -> 25 on 2026-09-09: the sibling landed and this is now the only bracket-slot divergence with a mechanism"
summary: "With `P(N: Integer; A: array of Integer)` and `P(N: Integer; A: TByteSet)` both visible, `c.P(2, [7, 8])` runs the ARRAY body in pxx and the SET body in fpc 3.2.2. Measured 2026-09-09. FindUMethOverloadAhead's bracket narrowing treats a tySet parameter at the slot as a VETO -- it declines to narrow at all and falls back to arity, i.e. first-declared -- where fpc treats the set as the answer. The veto's own comment states its reason and the reason is still sound: `[...]` really may be a set there, and guessing the other way would break a working call to buy this one. So this is NOT a one-line flip of the veto; it needs the probe to be able to say what the elements are, which is the same blocker as the element-ranked residual. Prio 15 because nothing in the tree mixes an array and a set overload at one slot -- the veto's comment says so and it was re-measured true. The behaviour is PINNED as a guard row in test_p_an_array_of_const_wins_a_bracket_argument, whose expected value for that row is pxx's own and is labelled as such, so a later change cannot move it silently."
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

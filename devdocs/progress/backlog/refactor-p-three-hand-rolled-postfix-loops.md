---
track: P
prio: 55
type: refactor
blocked-by: []
summary: "The `^ / .field / [i]` suffix chain is parsed by THREE hand-rolled loops — the shared one in pasparser_lval.inc plus private copies in pasparser_expr.inc for the record-name cast and the pointer-alias cast — and a fourth byte-identical copy sits in Track N's pyparser.inc. They have already diverged and produced silent wrong values at least four separate times, each fixed in one copy."
status: backlog
owner: unassigned
---

# P three hand-rolled copies of the postfix `^ / .field / [i]` loop

- **Track P** (`compiler/pasparser_lval.inc`, `compiler/pasparser_expr.inc`).
- Banked diagnosis from
  [[bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped]], per
  `devdocs/dev/root-cause-over-microfix.md`: that bug was fixed properly (in the
  shared `NodePtrElem` predicate, not at the call site) and this is the overhaul
  it exposed but deliberately did not attempt. **Not urgent** — nothing is
  broken today that is known; this is about the next one.

## The count

`while CurTok.Kind in [tkCaret, tkDot, tkLBrack] do`:

| file | what opens the chain |
| --- | --- |
| `pasparser_lval.inc` (~900) | an IDENT — the shared, most complete loop |
| `pasparser_expr.inc` (~5027) | a RECORD-NAME cast, `TRec(q)` |
| `pasparser_expr.inc` (~5223) | a POINTER-ALIAS cast, `PRec(q)` |
| `pyparser.inc` (~44092) | byte-identical copy of the third — Track N, see [[bug-n-inline-cast-deref-loses-a-pointer-fields-pointee]] |

`root-cause-over-microfix.md`'s own rule: *two mechanisms for one concept is a
smell, three is a design flaw.* This is four.

## The evidence that they diverge

Each of these was one copy knowing something the others did not, and each
produced a plausible wrong VALUE rather than an error:

- `bug-pascal-record-cast-field-offset` — the record-cast copy put an
  `AN_FIELD` straight on the `PTR_CAST`, so every field resolved at offset 0.
- `bug-pascal-record-cast-chain-drops-method-call` — the hand-rolled builder can
  only make `AN_FIELD`, so a METHOD at the end of a chain evaluated to the
  receiver instead of being called.
- `PPVmt(Self)^.__ClassRef.GetHashList(...)` — a metaclass-typed field is a
  RECEIVER, and the copy walked into it; the chain evaluated to the class
  reference.
- `bug-p-a-second-deref-on-a-typecast-pointer-field-is-dropped` — the
  pointer-alias copy answered every `^` from the cast's alias.

Note the shape of the last three fixes: each ADDED an escape from the private
loop back into a shared routine (`ParseClassRecordSelectors`,
`ParseMetaclassMemberTail`, `NodePtrElem`). The copies are already being
dismantled one arm at a time by whoever hits the next hole.

## The work

Finish that. Factor ONE suffix parser that takes the opening node plus its
`(tk, recName, pointee)` state, and have all three Pascal sites call it. Measure
by tickets-closed-per-change, not lines: the copies exist only because each cast
path needed "the same thing but starting from a different node", which is a
parameter, not a fork.

Watch for the genuine differences before merging them away — the `-1`/`-2`
adapter casts (`PChar(s)^`, the widening ordinal pun) carry no alias row and
need the fallback the alias-cast loop has; the record-name cast builds an
`AN_ADDR`-then-deref for the in-place `TRec(q).field` reinterpret. Both are real
behaviour, not accidents, and both must survive.

`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` is not a
counter-argument here: it says duplicate ACROSS languages, normalise WITHIN one.
These four copies are three within Pascal plus one in NilPy — the Pascal three
are exactly what it says to normalise, and the NilPy one is N's own call.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick`. This one is worth more than
the usual care: it is pure refactor of a path that has produced four silent
wrong-value bugs, so land it incrementally (one call site at a time, each
green) rather than as one swap.

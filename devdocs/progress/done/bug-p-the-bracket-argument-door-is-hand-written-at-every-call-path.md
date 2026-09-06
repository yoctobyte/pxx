---
slug: bug-p-the-bracket-argument-door-is-hand-written-at-every-call-path
track: P
prio: 45
type: bug
status: done
owner: frankB
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "CLOSED 1c8a6cfd5. Every Pascal call path now reaches TryParseBracketArgForSlot; the by-hand census greps in the body return NOTHING. THE NINTH VARIANT WAS A NINTH DEFECT AND THIS TICKET SAID IT WAS NOT: `TC.Create([10, 20, 30])` against `constructor Create(const A: array of Integer)` summed to 10 where fpc sums 60, while `o.M([10, 20, 30])` on the identical signature in the same file was correct. The earlier not-diverging measurement was taken on a METHOD call, which never reaches the constructor arm -- taken after this ticket's own line numbers had drifted, which is the failure the ticket warns about, committed by the person who wrote the warning. TWO DEFECTS FIXED, both from a guard that answered WHETHER instead of WHICH. (1) The constructor door's predicate was a Boolean, so every `[...]` became a TVarRec vector the callee read with the wrong stride; ClassCtorArraySigAt now returns the ctor's Procs[] row and the caller reaches the shared door. (2) ParamIsOpenArrayScalar excluded tyVariant from the feature's first commit (6d285d57a, 2026-06-23), whose subject and comment both say scalar/string and neither mentions Variant -- scope, not a constraint. `array of Variant` therefore got a set descriptor read as a length on the method doors and a TVarRec vector with the right COUNT and empty CONTENTS on the constructor one; removing the exclusion yields fpc's values. THE COUNT IS WHY IT SURVIVED: Length(A) is the same number for a correct open array and a TVarRec vector of the same arity, so a length assertion passes on empty elements. Fifteen rows, every one asserting a VALUE, all four shapes and both spellings in one file, green under fpc 3.2.2 and pxx. ClassCtorWantsVarRecAt is kept for pyparser.inc only -- NilPy is a separate frontend and duplicating the parser across languages is the deliberate pattern."
---

# Eight call paths, eight copies of one question

`[1, 2, x]` written at an argument position is ambiguous in the grammar and
unambiguous in the signature: a SET if the parameter is a set, an open-array or
`array of const` literal if it is an open array. The parser resolves it per
call path.

**DERIVE THE LIST; DO NOT READ THE ONE BELOW.** Four of the eight line numbers
this ticket was filed with had already drifted the same day — `call.inc` 2066 to
2115, `lval.inc` 5251 to 5252, `expr.inc` 7785 to 7632, `stmt.inc` 7910 to 7908.
A stale line number does not error, it points somewhere, and this ticket's whole
value is a COUNT, so a rotted table turns into a wrong census rather than an
obvious mistake. The two greps below are the census:

```sh
# arms that ask the question BY HAND
grep -n 'CurTok.Kind = tkLBrack) and ParamIsVarRecArray' compiler/pasparser_*.inc
# ...plus the one that asks a DIFFERENT, WEAKER question -- see the variation note
grep -n 'Params\[.*\].IsArray then' compiler/pasparser_lval.inc
# sites that DELEGATE (these are the fixed ones; the goal is for the first list
# to be empty and this one to be every call path)
grep -n 'TryParseBracketArgForSlot' compiler/pasparser_*.inc
```

| where (2026-09-06, re-derive before quoting) | shape it serves | asks |
| --- | --- | --- |
| `pasparser_call.inc:2115` | `GenMakeStaticMethodCall` — class/static methods | by hand |
| `pasparser_lval.inc:3452` | member call on a name receiver | by hand |
| `pasparser_lval.inc:3763` | member call, by-ref/array arm | **a weaker predicate** |
| `pasparser_lval.inc:5252` | member call, third shape | by hand |
| `pasparser_stmt.inc:7654` | direct call in statement position | by hand |
| `pasparser_lval.inc:88` | `TryParseBracketArgForSlot` itself | — |
| `pasparser_lval.inc:106` | `BuildIndirectCallAST` — indirect calls | delegates |
| `pasparser_expr.inc:7632` | direct call in expression position | delegates |
| `pasparser_stmt.inc:7908` | **implicit-Self bare method call** — had none until 2026-09-06 | delegates |

**The variation, flagged rather than claimed.** `pasparser_lval.inc:3763` guards
on `Procs[mpi].Params[mai].IsArray` — true of ANY open array — where every other
arm asks `ParamIsVarRecArray`, and then routes to `ParseVarRecLiteralAST`, the
TVarRec builder. **Measured 2026-09-06 and it does NOT diverge** on the shape I
could reach it with: `c.M([10, 20, 30])` for `const A: array of Integer` and the
`array of const` sibling both match fpc 3.2.2 exactly. So this is a ninth
variant of the predicate, not a ninth defect — and the scope of that negative is
one call shape, on x86-64, by one probe. A unification must not assume the four
hand-written arms ask the same question, because one of them does not.

## Why each one is found separately, by a corpus, months apart

**The wrong parse is usually silent.** A set item may be a single character or
an integer, so `Log('bare', ['x', 'y', 'z'])` through a door-less path
COMPILES:

```
qualified n=3 t0=2               { Self.Log -- the path that had the door }
bare      n=1026585632 t0=0      { Log      -- no diagnostic at all }
```

fpc prints `n=3 t0=2` for both. The callee reads its open-array length out of a
set descriptor and gets whatever is there.

Only an element a set cannot hold produces a diagnostic, and then it names the
set parser rather than the call: `set item must be one character`. fcl-passrc's
`Log(mtError, nErrInvalidCharacter, SErrInvalidCharacter, ['#0'])` fails that
way because `'#0'` is two characters — **an accident of the corpus, not a
property of the bug.**

So the reachable-and-silent population is much larger than the
reachable-and-refused one, and every instrument so far has found the refused
kind.

## The comments are the evidence this is a pattern, not an incident

Three of the eight arms already carry a note that some OTHER path lacked the
door:

- `pasparser_call.inc:2052` — *"The plain-routine call path has always checked
  for them; the method paths did not."*
- `pasparser_lval.inc:1725` — *"This block used to hand-roll its own arg loop,
  which parsed the '[' as a SET and died on `set item must be one
  character`."*
- `pasparser_call.inc:3204` — the same string again, for constructors.

Each was a real fix. None removed the next copy.

## Why the count GROWS — frankB, 2026-09-06, from the inside of a near miss

frankB had the ninth door half-written before a message stopped it: a fresh
argument loop beside the one at `pasparser_lval.inc:5251`, in the same function.
Their account of what made it feel correct is the mechanism this ticket is
really about:

> the surrounding code hand-rolls its argument loops five times; copying the
> local idiom is what produces the ninth copy, and **the local idiom is the most
> persuasive thing in view.**

So the copies are not carelessness and a reviewer will not catch them by reading
the diff — a sixth hand-rolled loop in a function holding five is the most
locally consistent thing anyone could write. **The count grows because each copy
is locally correct.** That is the argument for one shared loop rather than a
convention, a comment, or a check: nothing that relies on a reader noticing will
survive contact with five neighbours agreeing.

What they wrote instead was
`node := BuildIndirectCallAST(node, fldSig, tk = tyRecord)` (`f89f5ffec`), which
inherits `TryParseBracketArgForSlot` at `:106` and adds no door.

**And the boundary between that fix and this ticket is worth keeping, in
frankB's words, because it protects the count:** the eight below are paths that
ASK the bracket question and answer it by hand. The selector walker never asked
one — there was no door to duplicate, only a missing `(` arm — so it is not a
ninth address, it is a new consumer of the shared constructor. **This number is a
count of hand-written doors, and only that.**

## The fix

One argument loop, or failing that one predicate every loop must call — the
`TryParseBracketArgForSlot` extraction was a step and it currently has three
callers of eight. This is the same shape as
`bug-p-the-class-body-class-opener-is-a-hand-maintained-lookahead-list` and
frankA's five-dispatch-site work: an enumerated list of places that must each
remember something, with no diagnostic when one does not.

Check while writing it: the arms are NOT identical. Some also handle by-ref
arguments, NilPy keyword arguments and star-unpack, and default filling; the
implicit-Self one did none of those and still needs its defaults (verified
working after the door was added, but by a different mechanism). A unification
that assumes they are the same loop will drop one of those.


## Closed 2026-09-06 (frankB) — and the ninth variant was a ninth defect

**This ticket recorded `pasparser_lval.inc:3763` as a variant of the predicate
and not a defect, on a measurement I took myself, and it was wrong.** The
measurement was `c.M([10, 20, 30])` — a METHOD call, which does not reach that
arm at all. The arm is a CONSTRUCTOR door. The line numbers had drifted, which is
precisely what the ticket's own **DERIVE THE LIST** warning is about, and the
probe went to the address rather than to the code.

What it actually does, measured 2026-09-06 at `181576cdc`, in one file:

```
ctor  scalar n=3 sum=10      { TC.Create([10, 20, 30]) }
meth  scalar n=3 sum=60      { o.M([10, 20, 30])       }
```
fpc 3.2.2 prints 60 for both. `n` is right in both rows and only the SUM
separates them — a TVarRec vector and a correct open array have the same arity.

### Two defects, one shape: the guard answered WHETHER, not WHICH

frankD's phrasing from the slot-mask work, and it turned out to be the diagnosis
for both halves here.

1. **The constructor door.** `ClassCtorWantsVarRecAt` returns a Boolean, so the
   only thing the caller could do with a `[...]` was send it to
   `ParseVarRecLiteralAST`. New `ClassCtorArraySigAt` returns the constructor's
   `Procs[]` row instead, and the caller reaches `TryParseBracketArgForSlot` —
   the same door as everything else. First match still wins across an overload
   set, unavoidably: the bracket must be parsed **before** resolution can run,
   which is
   [[bug-p-two-array-parameters-at-one-bracket-slot-are-decided-by-declaration-order]]
   in the constructor's clothing and is not fixed here.

2. **`array of Variant` was excluded from the open-array arm at every door.**
   `ParamIsOpenArrayScalar` has carried `TypeKind <> tyVariant` since the
   feature's first commit (`6d285d57a`, 2026-06-23), whose subject and comment
   both say *scalar/string* and neither mentions Variant. Scope, not a
   constraint; nothing recorded a Variant element breaking the lowering, and it
   does not. `TC.CreateVar([11, 22, 33])` now yields 11 / 22 / 33.

### The census, re-derived at close

The two by-hand greps in the body **return nothing**. `TryParseBracketArgForSlot`
has nine call sites: `pasparser_lval.inc` :106 :3459 :3776 :5369,
`pasparser_stmt.inc` :7677 :7929, `pasparser_expr.inc` :7465 :7943,
`pasparser_call.inc` :2122. Re-derive rather than quote these.

`pasparser_call.inc` is included **before** `pasparser_lval.inc`, so the door
needed a forward in `frontend_forwards.inc`; pxx prescans and FPC's seed does
not, so that line is load-bearing for the seed build only.

`ClassCtorWantsVarRecAt` survives with exactly one caller, `pyparser.inc`. NilPy
is a separate frontend and
`devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md` says to duplicate the
parser across languages, so it was left alone rather than unified.

### The test, and why every row asserts a value

`test_a_bracket_argument_reaches_the_same_door_at_every_call_path.pas`: fifteen
rows — free routine in expression and statement position, `array of const`,
constructor (scalar / const / Variant), metaclass constructor, instance method,
implicit-Self bare call, method through a selector chain, class method, record
method, indirect call through a procedural type. Green under fpc 3.2.2 and pxx.

**Not one row asserts a length.** The `array of Variant` constructor row is the
argument: it had the right count and three empty elements, so any length check
would have certified it. Both spellings of every shape are in the same file
deliberately (frankD's rule) — two files each printing a plausible number both
pass; two numbers on adjacent lines of one output disagree.

Positive control run rather than reasoned: with the `tyVariant` line restored and
everything else kept, exactly the two Variant rows fail (`got 0 want 66`) and the
other thirteen pass. The constructor row was measured failing (`sum=10`) on the
pre-fix binary.

## Log
- 2026-09-06 — resolved by `1c8a6cfd5`. The ticket carried `status: working` and
  a summary reading `CLOSED` for a day: the fix landed, the resolve did not, so
  the board advertised it as in-flight and the placeholder was never filled.
  Filed under its own heading rather than fixed silently — see
  [[bug-t-a-resolve-that-never-wrote-a-placeholder-is-uncited-and-nothing-says-so]],
  which is the adjacent shape (no citation at all); this one is the third:
  a citation that exists, a summary that says CLOSED, and a status that says
  otherwise, with nothing comparing the two.

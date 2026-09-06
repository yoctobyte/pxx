---
slug: bug-p-the-bracket-argument-door-is-hand-written-at-every-call-path
track: P
prio: 45
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankD
blocked-by: []
summary: "`[...]` at an argument position is a SET to the expression parser and an `array of const` / open-array LITERAL to the callee, and only the PARAMETER can say which. That question is asked separately at EIGHT call paths and the arms are hand-written copies: pasparser_call.inc:2066, pasparser_lval.inc:88 (the one extracted helper) / :3452 / :3766 / :5251, pasparser_expr.inc:7785, pasparser_stmt.inc:7654, and -- until 2026-09-06 -- the implicit-Self bare method call, which hand-rolled its own loop with a bare `ParseExpr` and asked nothing. DERIVE THE SITES FROM THE GREPS IN THE BODY, never from a line number here: four of the eight had drifted the same day they were filed, and a rotted citation turns a COUNT into a wrong census rather than an obvious mistake. One of the hand-written arms also asks a WEAKER predicate than the others (`Params[].IsArray`, true of any open array) -- measured, not diverging on the one call shape I could reach it with, so it is a ninth variant and not a ninth defect. THE FAILURE IS USUALLY SILENT, WHICH IS WHY EACH ONE IS FOUND SEPARATELY BY A CORPUS: a single-character string or an integer is a LEGAL set item, so the call compiles and the callee reads Length off a set -- 1026585632 against fpc's 3, no diagnostic. Only an element a set CANNOT hold (`['#0']`, two characters) turns it into `set item must be one character`, and that is what fcl-passrc happened to pass. Three of the eight arms already carry a comment saying a previous path lacked the door. The fix is one predicate every argument loop calls, or one argument loop."
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

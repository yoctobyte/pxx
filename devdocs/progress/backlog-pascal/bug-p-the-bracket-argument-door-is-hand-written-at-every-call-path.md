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
summary: "`[...]` at an argument position is a SET to the expression parser and an `array of const` / open-array LITERAL to the callee, and only the PARAMETER can say which. That question is asked separately at EIGHT call paths and the arms are hand-written copies: pasparser_call.inc:2066, pasparser_lval.inc:88 (the one extracted helper) / :3452 / :3766 / :5251, pasparser_expr.inc:7785, pasparser_stmt.inc:7654, and -- until 2026-09-06 -- the implicit-Self bare method call at pasparser_stmt.inc:7910, which hand-rolled its own loop with a bare `ParseExpr` and asked nothing. THE FAILURE IS USUALLY SILENT, WHICH IS WHY EACH ONE IS FOUND SEPARATELY BY A CORPUS: a single-character string or an integer is a LEGAL set item, so the call compiles and the callee reads Length off a set -- 1026585632 against fpc's 3, no diagnostic. Only an element a set CANNOT hold (`['#0']`, two characters) turns it into `set item must be one character`, and that is what fcl-passrc happened to pass. Three of the eight arms already carry a comment saying a previous path lacked the door. The fix is one predicate every argument loop calls, or one argument loop."
---

# Eight call paths, eight copies of one question

`[1, 2, x]` written at an argument position is ambiguous in the grammar and
unambiguous in the signature: a SET if the parameter is a set, an open-array or
`array of const` literal if it is an open array. The parser resolves it per
call path.

| where | shape it serves |
| --- | --- |
| `pasparser_call.inc:2066` | `GenMakeStaticMethodCall` -- class/static methods |
| `pasparser_lval.inc:88` | `TryParseBracketArgForSlot`, the extracted helper |
| `pasparser_lval.inc:3452` | member call on a name receiver |
| `pasparser_lval.inc:3766` | member call, second shape |
| `pasparser_lval.inc:5251` | member call, third shape |
| `pasparser_expr.inc:7785` | direct call in expression position (via the helper) |
| `pasparser_stmt.inc:7654` | direct call in statement position |
| `pasparser_stmt.inc:7910` | **implicit-Self bare method call** -- had none until 2026-09-06 |

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

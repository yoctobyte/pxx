---
slug: bug-a-a-routine-local-procedural-type-eats-the-body
track: A
prio: 45
status: done
resolved: PENDING-COMMIT
---

# A routine-local procedural type makes the parser consume the rest of the program

```pascal
program t;
procedure Go; type TP = procedure(l: LongInt); var cb: TP; begin WriteLn('go'); end;
begin Go; end.
```

```
pascal26:3: error: unexpected token   { line 3 is `begin Go; end.` }
  near: end  begin Go  end >>>  unit builtinheap
```

fpc 3.2.2 prints `go`. The same type declared at **program** scope is fine; a
routine-local `record` or pointer type is fine. Only a routine-local
*procedural* type — named or anonymous, with or without a parameter list, in a
`type` section or straight in `var` — does it. Present on the pinned compiler,
so this is not new.

## Cause

`PreScanSkipRoutineBody` (`pasparser_proc.inc`) walks a routine's local
declaration part to find that routine's own `begin`, stepping over any nested
routine so an inner `begin..end` does not close the outer body. Its test for
"this is a nested routine" was the bare keyword:

```pascal
if CurTok.Kind in [tkProcedure, tkFunction] then
```

A procedural **type** starts with the same keyword. So the walk read
`procedure(l: LongInt)` as a nested routine header, skipped to the `;`, ate it,
and then went looking for that phantom routine's `begin` — finding the
*enclosing* routine's. From there every token was off by one body: `Go`'s real
statements were consumed as the phantom's, `Go`'s `end` closed the phantom, and
the walk kept going until it hit the end of the token stream.

The discriminating test already exists, two files over, with a comment that
states this exact case:

```pascal
function NestIsRoutineDecl(idx: Integer): Boolean;
{ True for a routine DECLARATION at idx. A procedural TYPE (`= procedure(x: T)`,
  `: procedure of object`) never has an identifier straight after the keyword,
  which is exactly what separates the two here. }
```

Every other walk over a declaration part uses it (`NestBodyBeginAt`,
`NestRoutineEndAt`, the shadow scan, the nested-routine lifter — seven call
sites). `PreScanSkipRoutineBody` was the one that hand-wrote the test and
dropped the guard. `devdocs/dev/normalise-dont-special-case.md`: the second copy
is the one that stays broken, and here the second copy even had the correct
version written down beside it.

## Fix

```pascal
if NestIsRoutineDecl(TokPos - 1) then
```

`CurTok` is `Tokens[TokPos - 1]`, so this is the same predicate on the same
token. One line, and one fewer copy of the rule.

## Verification

- `test/test_anonymous_procedural_type.pas` (shared with
  `bug-a-an-anonymous-procedural-type-is-not-accepted`): `Local` declares a
  routine-local named procedural type *and* anonymous ones in its var section;
  `Outer`/`Inner` proves the recursion into a genuine nested routine still finds
  its own `begin`. Byte-identical to fpc 3.2.2.
- Method implementations with a local procvar, and nested routines beside plain
  locals, both re-verified.
- `make compiler/pascal26` self-host fixedpoint, converged in 1 round.
- `tools/gate.sh quick` green.

## Found by

Fixing `bug-a-an-anonymous-procedural-type-is-not-accepted`: the anonymous form
started working at program scope and kept failing inside a routine, with a
completely different error. Reproducing on the pinned compiler showed the two
were unrelated and this one had been there all along — a routine-local
procedural type is rare enough that nothing in the tree or the corpora had one.

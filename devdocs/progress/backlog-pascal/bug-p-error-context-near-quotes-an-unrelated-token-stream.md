---
track: P
prio: 35
type: bug
status: backlog
found: 2026-09-01
found-by: claude-T
owner: ""
blocked-by: []
summary: "A compile error's `near:` excerpt can quote text from a completely unrelated token stream — RTL/builtin unit source with no relation to the file being compiled. The line number and the diagnosis are correct; only the excerpt is wrong, so it does not error and does not look wrong. Reproduces on a 10-line program: the same `undefined variable` error gives a CORRECT excerpt in a trivial program and a bogus one once the unit declares a generic specialization alias, which brackets it tightly."
---

# A `near:` excerpt can quote an unrelated token stream

## Repro

```
tools/../compiler/pascal26 --strict-case --strict-operator \
  library_candidates/fpc-testsuite/tests/test/tgeneric50.pp /tmp/x50
```

```
pascal26:30: error: undefined variable (TTestInteger)
  near: ; interface type PVarRecInt64 = ^ >>> Int64 ; PVarRecDouble
```

Line 30 of `tgeneric50.pp` is `t := TTestInteger.Create;` — so the **line number
is right** and the **diagnosis is right**. The `near:` context is the problem:
`PVarRecInt64` / `PVarRecDouble` are RTL declarations that appear nowhere in
`tgeneric50.pp`.

For contrast, the same compiler on the same file family produces a correct
excerpt when it does not go wrong this way:

```
pascal26:14: error: expected 'begin' before 'deprecated'
  near: < T > = class end >>> deprecated 'Message A' ;
```

## Why this is worth a ticket rather than a shrug

`near:` exists to save the reader from opening the file. When it is right it is
load-bearing; the two agents who worked `tgeneric32`/`tgeneric49` on 2026-09-01
both used it. An excerpt that is confidently drawn from another file is worse
than no excerpt: it does not error, it is not obviously wrong, and it invites
reasoning about a construct that is not there.

Same class as the stale-stamp trap that `test-selfcompile-odiff` exists to
catch, and as the `pin-shadow` verdict being read as authority — an instrument
that answers a question other than the one asked, without saying so.

## Likely shape

The error path appears to index a token buffer that is not the one for the unit
under compile — probably the RTL/system unit's, left over or shared — while the
line number comes from the correct source position. Whoever takes it: the two
outputs above are enough to bracket it, since one file produces both a correct
and an incorrect excerpt depending on which error fires.

## Note

Found while triaging `regression-test-pascal-conformance-shard0-6-4`. Not
related to that regression's cause; the residual `tgeneric50` failure that
surfaces it is the specialization-alias hint-directive gap, which is separate
again.


---

## Repro REPLACED 2026-09-01 — the original one was fixed out from under it

The first repro used `tgeneric50.pp`, which **now compiles clean** (the
specialization-alias hint-directive gap was fixed the same evening). That file no
longer produces any error, so the original evidence is unreproducible.

**The defect itself is not stale — it still reproduces**, and the replacement is
smaller and a better bracket, because it pairs a correct excerpt with an
incorrect one from the same compiler in the same session.

### Control — excerpt is CORRECT

```pascal
program n1;
begin
  x := 1;
end.
```
```
pascal26:3: error: undefined variable (x)
  near: program n1 ; begin x >>> := 1 ;
```

### Repro — same error class, excerpt is from another token stream

```pascal
program n2;
{$mode delphi}
type
  TTest<T> = class end;
  TAlias = TTest<Integer>;
var
  t: TAlias;
begin
  t := TNotDeclared.Create;
end.
```
```
pascal26:9: error: undefined variable (TNotDeclared)
  near: ; end . unit builtinheap ; >>> interface type PVarRecInt64
```

Line 9 is right, the diagnosis is right, and `unit builtinheap` /
`PVarRecInt64` appear nowhere in the program.

### What the pair narrows it to

The difference between the two is that `n2` declares a **generic specialization
alias**. So the excerpt goes wrong only once the unit's token stream has been
extended by specialization minting: the position used for `near:` appears to
index past the end of the user's tokens and into the builtin/RTL stream, while
the line number is carried separately and stays correct.

That also explains why the original `tgeneric50.pp` sighting looked like a
generics bug and is not one — generics are how you *get* an extended token
stream, not what is broken. Any construct that appends tokens should reproduce
it.

### Note on staleness

Filed 2026-09-01 and already re-verified once the same day, because generics
were changing hourly. Anyone picking this up should re-run the pair first: the
control is the part that makes it a bracket rather than an anecdote.

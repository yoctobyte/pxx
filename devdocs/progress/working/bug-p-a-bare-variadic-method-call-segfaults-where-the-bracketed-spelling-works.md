---
track: P
prio: 40
type: bug
status: working
owner: frankH
created: 2026-09-09
found-by: frankS
tags: [array-of-const, methods, variadic]
blocked-by: []
summary: "`Desc('a', 1)` — variadic bracket-elision against `Desc(const a: array of const)` — SEGFAULTS when written bare inside the class that declares it, while the bracketed spelling `Desc(['a', 1])` of the same call runs correctly in the same program. Measured 2026-09-09 at 1180aa627: `Desc(['a',1])` prints `n=2: chr=a int=1`, then `Desc('a', 1)` crashes. The elision is a pxx extension (feature-writeln-as-library) and fpc refuses the source, so there is no oracle for the ACCEPTED behaviour — the defect is that we accept it and then crash, which is the one outcome nobody can act on. AbsorbVariadicTailArgs hooks ExpectCallRParen; the bare implicit-Self site hand-rolls its own argument loop and never reaches it, which is the same structural cause the BRACKET DOOR comment already records at that loop. NOT the arity bug fixed in bug-p-a-bare-method-call-inside-its-own-class-ignores-arity: that fix deliberately carves this shape OUT rather than converting the crash into a diagnostic, because a fix aimed elsewhere must not hide it."
---

# A bare variadic method call segfaults where the bracketed spelling works

- **Type:** bug — **Track P** (`compiler/pasparser_stmt.inc`, the implicit-Self
  call site's hand-rolled argument loop).

## The repro

```pascal
type TC = class
  procedure Desc(const a: array of const);
  procedure Go;
end;
procedure TC.Go;
begin
  Desc(['a', 1]);   { prints  desc n=2: chr=a int=1 }
  Desc('a', 1);     { SEGFAULT }
end;
```

Both are the same call. The bracketed one is built correctly; the elided one
crashes at run time, having compiled clean.

## Why it is here rather than in AbsorbVariadicTailArgs

`AbsorbVariadicTailArgs` is called from `ExpectCallRParen`. The bare
implicit-Self statement path does not go through it — it hand-rolls its
argument loop, which is the **same structural cause** the `THE BRACKET DOOR`
comment already sitting in that loop records: *"Every other call path asks;
this one hand-rolled its loop and asked nothing."* That comment fixed the
bracket case at this site; the elision case is the next one along.

## Relationship to the arity fix

[[bug-p-a-bare-method-call-inside-its-own-class-ignores-arity]] closed the loose
arity fallback at this exact site, and **deliberately carves this shape out**
(`UMethNameCanAbsorbVarRecTail`). Refusing it would have turned a segfault into
a compile error, which reads as a fix and is not one — the extension is
supposed to work here, and the bracketed spelling proves the machinery exists.

## No oracle for the accepted behaviour

fpc refuses `Desc('a', 1)` outright ("Wrong number of parameters"), so this is
`us accepting what FPC rejects`, which **is not a defect** — the defect is the
crash. The expected output is the bracketed spelling's, which is measured and
in the ticket above.

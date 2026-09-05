---
slug: bug-p-a-two-argument-write-to-a-text-file-inside-a-class-with-a-write-member-silently-writes-nothing
title: "`Write(f, s)` on a Text handle, inside a class declaring a 2-parameter Write, binds to the MEMBER and writes nothing — no diagnostic"
track: P
prio: 60
type: bug
status: done
found: 2026-09-05
found-by: frankB
owner: frankB
blocked-by: []
summary: "An unqualified Write/Read inside a method binds to a same-named member of the enclosing class when the ARITY matches, and the arity test does not look at whether the first argument is a FILE HANDLE. So `Write(f, 'payload')` on a `var f: Text`, inside a class declaring `function Write(const Buffer; Count: Longint): Longint`, is compiled as a call to that member: the file is created and stays EMPTY, no diagnostic, exit 0. PRE-EXISTING and identical on pinned. fpc 3.2.2 refuses the same source outright (`Wrong number of parameters specified for call to Write`), because it gives the member absolute priority and never falls back to the intrinsic. We do NEITHER -- we neither refuse it nor perform it -- which is the one outcome that loses the program's intent silently. The 3-and-more-argument form already falls through to the intrinsic correctly, so the defect is confined to calls whose arity happens to match a member's."
---

# Repro

```pascal
program w; {$MODE OBJFPC}
type
  TS = class
    function Write(const Buffer; Count: Longint): Longint;
    procedure P;
  end;
function TS.Write(const Buffer; Count: Longint): Longint; begin Result := Count; end;
procedure TS.P;
var f: Text; s: AnsiString;
begin
  Assign(f, 'w.txt'); Rewrite(f); Write(f, 'payload'); Close(f);
  Assign(f, 'w.txt'); Reset(f); Readln(f, s); Close(f);
  writeln('got=[', s, ']');
end;
var s: TS; begin s := TS.Create; s.P; end.
```

| compiler | result |
| --- | --- |
| pxx HEAD | compiles, runs, prints `got=[]`, exit 0 — **w.txt is created and empty** |
| pxx pinned | identical — pre-existing, not a regression |
| fpc 3.2.2 | **refuses**: `Wrong number of parameters specified for call to "Write"` |

# Why it happens

`pasparser_stmt.inc`'s `tkwriteln/tkwrite/tkReadln/tkRead` arm binds an
unqualified call to a member of the enclosing class when
`FindUMethOverloadAhead` / `FindUMethArityStrict` accept it. Neither asks
whether the FIRST ARGUMENT IS A FILE HANDLE — the one fact that makes a call
unambiguously the intrinsic, since no ordinary member takes a `Text` or a
`FileRec` in that position by accident.

`Write(f, 'payload')` is two arguments and the member takes two, so the arity
gate passes and the type-directed `FindUMethOverloadAhead` is not decisive
enough to reject it (`const Buffer` is an untyped formal and accepts anything).

# What makes this the bad kind of bug

**We are neither compiler.** FPC refuses; a fall-through-to-intrinsic design
performs the write. We accept the program and perform a different operation,
with the same exit code as success. Nothing in the output distinguishes it from
a working program — the file exists, it is just empty. This is the shape
CLAUDE.md calls out: *"the expensive bugs here do not crash; they produce a
plausible wrong value far from the cause."*

# The design fork, and a recommendation rather than a Track U ticket

FPC's rule is "member always wins, qualify with `System.Write` to reach the
intrinsic". **We already diverge from that deliberately** and should not adopt
it now: the arity fall-through was installed by
[[bug-p-a-write-call-inside-a-method-named-write-binds-to-the-member-whatever-its-arity]]
precisely so `lib/rtl/configparser.pas` — written in exactly this shape — would
build, and FPC rejects that file outright.

So the consistent completion of the existing choice is **route on the first
argument**: if it is a `Text` or a `FileRec` handle, it is the intrinsic,
whatever any member's arity says. That rule needs no new policy, it makes the
2-argument case behave like the 3-argument case already does, and the parser
already has both predicates — `TextIOFileSym` and `FileIOFileSym` — that answer
exactly this question by lookahead, which is how the file arms of
`ParseReadArgsAST` / `ParsewriteArgsAST` find their handle today.

Reaching a member that genuinely wants a file handle as its first parameter
stays possible by qualifying (`Self.Write(f, n)`), which is what FPC makes you
do for the intrinsic and is the same escape hatch pointed the other way.

# Gate

The repro, asserting `got=[payload]`, plus BOTH controls, because this sits
between two mechanisms that can each eat the other:

* the member must still win for a call with NO file handle —
  `Write(buf, 4)` inside the same class must call the member and not print to
  the console;
* the 3-argument fall-through must stay working — `Write(f, 'x', 'y', 'z')`
  writes `xyz`, which `test_read_write_as_method_name.pas` already pins.

`test_read_write_as_method_name.pas` documents this defect in the comment above
its `TReaderOnly` class, which exists only because `TStreamish` cannot host the
Text round-trip row while this bug is open. **Fold that class back in when this
is fixed** — its presence is a marker.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

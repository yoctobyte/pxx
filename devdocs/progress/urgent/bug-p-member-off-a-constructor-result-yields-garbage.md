---
summary: "`TThing.Create(2).n` in an expression compiles and yields garbage; the same shape on an ordinary function result (`Make(4).n`) is correct, and in a writeln argument it is a parse error instead"
type: bug
track: P
prio: 70
---

# A member read off a CONSTRUCTOR result silently yields garbage

- **Type:** bug — Track P (Pascal frontend, shared `compiler/parser.inc`)
- **Status:** urgent — **silent wrong value**
- **Opened:** 2026-08-05
- **Found by:** writing `test/test_procedure_as_value_ok.pas`. The line meant to
  prove constructors stay usable as values printed junk, which is how this
  surfaced at all.
- **Pre-existing:** reproduced identically with the pinned stable
  (`stable_linux_amd64/default`, VERSION 243), so it is not a regression from
  the no-result-call check landed the same night.

## Repro

```pascal
program mem;
type
  TThing = class
    n: Integer;
    constructor Create(k: Integer);
    function Val: Integer;
  end;
constructor TThing.Create(k: Integer); begin n := k; end;
function TThing.Val: Integer; begin Result := n; end;
function Make(k: Integer): TThing; begin Result := TThing.Create(k); end;
var a, b, c, d: Integer;
begin
  a := TThing.Create(2).n;
  b := TThing.Create(3).Val;
  c := Make(4).n;
  d := Make(5).Val;
  writeln(a, '|', b, '|', c, '|', d);
end.
```

| | output |
| --- | --- |
| FPC | `2\|3\|4\|5` |
| **pxx** | **`-801112056\|-801112032\|4\|5`** |

## What the split says

`Make(4).n` and `Make(5).Val` — a member off an ordinary **function** result —
are **correct**. Only the **constructor** result is wrong, for both a field and
a method. So the machinery for "bind a member to a call result" works; the
constructor path is not producing (or not keeping) the instance pointer the
member access then reads through.

Two more facts worth having before touching it:

- The **same expression in a different position is a parse error**, not garbage:
  `writeln(TThing.Create(2).Val)` gives `Expected: ), but got: ... unexpected
  token`. Two positions, two different wrong answers, which points at the
  postfix-after-a-call handling being duplicated per position rather than shared
  — the same smell as
  [[compat-pascal-index-a-function-call-result]], which is that family's
  parse-error half.
- `t := TThing.Create(10); t.n` is fine. Only the un-named intermediate is lost.

## Relationship to the neighbours

- [[compat-pascal-index-a-function-call-result]] — `Copy(s,2,3)[1]`,
  `b.ArrP(3)[0]`. Same "postfix off a call result" family, but those fail
  LOUDLY (parse error / IR_UNSUPPORTED). This one is silent, which is why it is
  filed as a `bug-` in its own right per CLAUDE.md's escape rule rather than
  folded into the compat ticket.

## Gate

Track P: `make test` + self-host fixedpoint (byte-identical). Track P catch —
the Pascal frontend lives in the shared `lexer.inc`/`parser.inc`, so this must
not be edited concurrently with Track A.

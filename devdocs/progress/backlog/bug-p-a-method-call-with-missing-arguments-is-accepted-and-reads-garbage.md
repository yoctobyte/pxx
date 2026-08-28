---
prio: 80
track: P
owner: unassigned
---

# A METHOD called with missing arguments compiles and reads garbage (free routines are checked)

- **Type:** bug — **silent wrong behaviour**, broad surface. Compiles clean,
  runs, prints garbage. No crash to notice.
- **Track P** (Pascal frontend, call resolution).
- **Pre-existing:** identical on **pinned**.
- **Binary:** `4157f75831bb`. Oracle: FPC 3.2.2.

## The defect

A bare method reference — `s.IPick` where `IPick(A: LongInt)` needs an argument
— is compiled as a **zero-argument call**, with whatever happens to be in the
argument register read as `A`. FPC rejects it:

```
Error: Incompatible types: got "TSvc.IPick(LongInt):LongInt;" expected "LongInt"
```

## It is ONE ARM of a double case, and the other arm is correct

| shape | pxx | FPC |
| --- | --- | --- |
| **free** function, missing arg — `n := FPick;` | **compile error** | rejects |
| **method** function, missing arg — `n := s.IPick;` | `1459617816` | rejects |
| **method** procedure, missing arg — `s.IDo;` | `IDo -941621240` | rejects |
| **method** function, missing arg, inside an expression — `n := s.IPick + 1;` | `-1319108583` | rejects |
| method, correct arity — `n := s.IPick(4);` | `12` | `12` |

Free routines are arity-checked. Methods are not, in every position tried. This
is the exact shape `normalise-dont-special-case.md` is about: one concept, two
paths, and the second path is the one that stayed broken.

## Why prio 80

Every one of these compiles and produces a plausible number. There is no
diagnostic, no crash, and nothing at the call site that reads as wrong — a
missing argument list looks like a property read or a parameterless call. In a
corpus the size of `lib/pcl` or Synapse, a single dropped argument list is
invisible and produces a wrong value forever.

Note the two failing shapes that are *not* assignments: a bare `s.IDo;` statement
and a method inside an arithmetic expression. So this is not reachable only
through a method-pointer context — it is any mention of a method without its
arguments.

## It is also the mechanism under the method-pointer bug

[[bug-p-a-class-method-cast-to-a-method-pointer-inline-segfaults]]'s remaining
half ("defect B", the inline cast) is downstream of this. `TSel(s.IPick)` works
in FPC because `s.IPick` without arguments **cannot** be a call there, so it can
only be a method reference. In pxx it silently *can* be a call, so the parser
takes that reading, produces an `Int64`, and the cast reinterprets that integer
as a `Code`/`Data` pair — which is the segfault.

**So fix this first.** Once a bare method mention with missing arguments is no
longer a viable call, the cast site has only one reading left and defect B may
fall out rather than needing its own arm. Worth checking before writing that arm:
there are already **four** near-identical `AN_METHODREF` construction sites
(`pasparser_expr.inc` ×2 for the `@` forms, `pasparser_stmt.inc` ×2 for the
Delphi `@`-optional forms), and a fifth would be past the point where
`root-cause-over-microfix.md` says to count mechanisms rather than add one.

## Repro

```pascal
program ar;
{$MODE DELPHI}{$H+}
type
  TSvc = class
    function IPick(A: LongInt): LongInt;
  end;
function TSvc.IPick(A: LongInt): LongInt; begin Result := A * 3; end;
var s: TSvc; n: LongInt;
begin
  s := TSvc.Create;
  n := s.IPick;      { no argument supplied }
  WriteLn(n);        { FPC: compile error.  pxx: a garbage number }
end.
```

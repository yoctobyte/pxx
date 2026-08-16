---
track: A
prio: 45
type: bug
---

# bug(A): a doubly-nested routine cannot capture ANY enclosing variable, and the error blames the call site

Found 2026-08-16 by an FPC oracle sweep (nested procedures / `array of const` /
open arrays — the other two were clean). FPC compiles every shape below.

## The boundary, measured

| shape | pxx |
| --- | --- |
| depth 1, captures enclosing local + param | **OK** |
| depth 2, captures NOTHING | **OK** |
| depth 2, captures depth-0 local | `undefined variable (C)` — *at B's call to C* |
| depth 2, captures depth-0 param | `undefined variable (C)` — *at B's call to C* |
| depth 2, captures depth-1 local | `undefined variable (lb)` — inside lifted `B$13` |
| depth 2, captures depth-1 param | `undefined variable (k)` |

So it is not "depth 2 is unsupported" and not "capture is unsupported" — it is
**capture AT depth 2, of any level, in any direction**. Minimal repro:

```pascal
procedure A;
var la: Integer;
  procedure B;
    procedure C;
    begin la := la + 1; end;     { the only line that matters }
  begin C; end;
begin la := 0; B; writeln(la); end;
begin A; end.
```

FPC prints 1; pxx refuses with `undefined variable (C)`.

## Why — the diagnosis, not a guess

Nested routines are **lifted**: the free-variable scan in `ParseNestedRoutine`
(parser.inc, the block around the `capNm`/`capCount` arrays) classifies each
identifier in the body and turns each captured enclosing local/param into an
extra by-reference parameter. That scan says of itself:

> *Inner nested routines are skipped wholesale — their captures are resolved
> when they are themselves lifted.*

That is the bug. Skipping the inner routine is right for finding B's OWN
captures, but it means nothing ever threads A's variables through B so that C
can reach them. When C is lifted in turn, the enclosing slots it needs either
belong to a scope that is no longer current (the depth-0 cases, where C's lift
fails outright and B's body is then left with no `C` to call — hence the
call-site error) or belong to B's own frame, which C has no link to (the depth-1
cases, which surface as the captured name being undefined inside lifted B).

**Two symptoms, one cause.** Note the depth-0 diagnostic names the callee, `C`,
which is the one identifier in the program that is NOT the problem — a reader
will look for a typo or a missing forward declaration. Whatever the fix, that
message has to move to the capture.

## Not a microfix

Lifting is a whole-scheme choice (`devdocs/dev/root-cause-over-microfix.md`), and
the shapes above are one gap, not six. The fix is to make the lift **transitive**:
when scanning a routine's body, do NOT skip its inner routines — collect their
free variables too and add them to the enclosing routine's own capture set, so
each level threads through what the levels below it need. That is a change to the
free-variable scan plus the call-site rewrite that passes the extra by-ref
arguments, and it deletes the special case rather than adding one. Depth 3+ then
falls out by construction; a per-depth patch would not.

Related and probably to be fixed in the same pass, since it is the same capture
path: `feature-nested-routine-fixed-array-capture` (a fixed-size array local is
refused at depth 1 already). Worth checking whether transitive lifting makes that
one harder or easier before starting.

## Repro files

Kept minimal on purpose; each isolates one row of the table. See the session's
scratch probes `n1`–`n8` — or rebuild from the table, they are four lines each.

## Gate

`make compiler/pascal26` + a new positive test per row of the table with FPC's
own output as `.expected` + `tools/gate.sh quick`. Self-host fixedpoint is the
real risk here: the compiler's own source is full of nested routines, so a change
to the lifting scheme must reproduce byte-identically before anything else counts.

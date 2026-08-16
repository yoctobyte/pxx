---
track: A
prio: 45
type: bug
status: done
owner: claude-A-P
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

## Resolution — TWO causes, and the ticket only had one

The diagnosis above (the free-variable scan skips inner routines, so nothing
threads an enclosing frame down) is real and is half the bug. Measuring first
turned up the half that was doing the visible damage:

**`NestScanSpans` took the FIRST `begin` after the header as the routine's own
body.** At depth 2 that `begin` belongs to the INNER routine. So for

```pascal
procedure B; var lb: Integer;
  procedure C; begin lb := lb + 1; end;
begin lb := 5; C; writeln(lb); end;
```

the lifter believed B's body was `begin lb := lb + 1; end;` and that B ended at
C's `end;` — it stashed B cut in half and left B's real body orphaned in the
enclosing declaration section. That is why the depth-1 rows reported the
captured name undefined *inside lifted B*, and why the depth-0 rows blamed the
call site: the identifiers in those messages were fallout from a mis-parse, not
from a missing capture. A purely transitive-lifting fix would not have moved
either row.

Fixed together, in `compiler/parser.inc`:

- New `NestIsRoutineDecl` / `NestBodyBeginAt` / `NestRoutineEndAt` — index-driven
  mirrors of `PreScanSkipRoutineBody`, which already did this correctly for the
  CurTok/Next walk. `NestScanSpans` now steps OVER inner routine declarations to
  find its own `begin`, and the sibling-call scan that locates the enclosing
  `begin` uses the same helpers. A procedural TYPE is told from a declaration by
  requiring an identifier straight after the keyword. Body depth counting also
  gained `tkTry`/`tkAsm` (it counted only `begin`/`case`), which had truncated
  the span of any nested routine containing a `try`.
- The free-variable scan is now **transitive**: an inner routine is walked, not
  skipped, and its free variables become the enclosing routine's captures. An
  inner routine's own name, params and locals shadow ours for the length of its
  span (a small shadow stack), so `procedure C(k: Integer)` neither captures nor
  suppresses an enclosing `k`. Depth 3+ falls out by construction.
- The own-names scan of the declaration part now steps over inner routine
  declarations too. It previously swept through them, so an inner routine's
  parameter names were being read as locals of the enclosing routine — which
  would have suppressed exactly the captures this fix adds.

The diagnostic complaint stands but is now moot: with the span fixed, no row of
the table produces a message naming the callee, because none of them fail.

## Verified

All six rows of the table, plus depth 3 capturing a local and a param from every
enclosing level at once, by-ref write-back two levels down, an inner local
shadowing an enclosing one, a depth-2 sibling call, a depth-2 self-recursive
capturing function, and `Self`/field capture through two levels inside a method.
Every one matches FPC's output for the same source, recorded as
`test/test_nested_routine_depth2_capture.pas` + `.expected` (wired into
`make test`).

Self-host fixedpoint converged and `tools/gate.sh quick` is GREEN. Neutrality
was expected and holds: every shape the change affects was previously a compile
error, so no working program's parse moves.

`feature-nested-routine-fixed-array-capture` is untouched and still open — the
refusal at the capture site is unchanged, it can just now be reached from depth
2 as well.

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.

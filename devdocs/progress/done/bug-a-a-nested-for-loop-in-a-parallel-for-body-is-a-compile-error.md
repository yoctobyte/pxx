---
track: A
prio: 55
type: bug
blocked-by: []
summary: "A `for` loop inside a `parallel for` body was refused with `error: expected ':='` against lib/rtl/palthread.pas. The cause is NOT a token that vanished: the inner control variable is an enclosing local, so the capture rewrite turned it into `for j^ := 1 to 3`, which the grammar cannot accept. That refusal was the only thing protecting the program -- the two spellings that COMPILED are both broken: the same capture written as `j := 0; while j < 3` returns 299674 of 300000 and varies per run, and a GLOBAL control variable HANGS, because a worker resetting it keeps the others' loops alive. Fixed by making the control variable of an inner `for` a worker-PRIVATE local whatever its storage was outside, as OpenMP does inside a parallel region. Test test_parallel_for_nested_for_body.pas; all 14 existing parallel tests still green. The `while` shape is still shared and still racy -- that is feature-a-a-private-clause-for-parallel-for, whose priority this raised from 25 to 50."
status: done
owner: frankA
---

# A nested `for` in a `parallel for` body is a compile error

## Repro

```pascal
program nest;
uses palparallel;
function F(n: Integer): Int64;
var i, j: Integer; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked) for i := 0 to n - 1 reduction(+: acc) do
  begin
    for j := 1 to 3 do acc := acc + 1;
  end;
  F := acc;
end;
begin WriteLn('acc=', F(1000)); end.
```

```
$ ./compiler/pascal26 -O2 --threadsafe nest.pas nest
pascal26:7: error: expected ':='
  in: ./compiler/../lib/rtl/palthread.pas
  near:  __pfhi  begin for j >>>
```

Compiler `ba2efc846790`. Two things are wrong at once: the construct is refused,
and the diagnostic names an RTL file the user did not write, at a line number
from their own file.

## The boundary — measured, and it is narrow

Same harness, same body slot, one statement swapped each time:

| body statement | |
| --- | --- |
| `acc := acc + 1;` | compiles |
| `if i > 0 then acc := acc + 1;` | compiles |
| `j := 0; while j < 3 do begin ... end;` | compiles |
| `j := 0; repeat ... until j >= 3;` | compiles |
| `case i mod 2 of 0: ...; else ...; end;` | compiles |
| `begin acc := acc + 1; end;` | compiles |
| **`for j := 1 to 3 do acc := acc + 1;`** | **REFUSED** |
| **`for j := 3 downto 1 do acc := acc + 1;`** | **REFUSED** |

So it is not nesting, not block structure, and not a second loop — `while` and
`repeat` are both fine. It is specifically the `for` STATEMENT.

## Suspected site — a hypothesis, not a diagnosis

The worker is built by replaying captured tokens rather than by lowering an AST:

```
procedure __pf_<n>(__pfctx: Pointer; __pflo, __pfhi: NativeInt);
var V: NativeInt; begin for V := __pflo to __pfhi do BODY end;
```

(`pasparser_stmt.inc:3744`, stashed via `PFStash` around 4195-4330.) The error
text is what makes this the first place to look: the parser reports `expected
':='` while positioned at `for j`, and the `near:` window shows `__pfhi begin
for j` — the INNER loop's `:=` is not where the parser expects it. The user's
source plainly has `j := 1`, so the token that vanished or moved did so during
capture or replay.

**Do not take that as established.** The window is a rendering of the
synthesized stream and could equally be showing a `do` that went missing after
`__pfhi`. Dump the replayed tokens before theorising further — this is the class
of bug `devdocs/dev/debugging-playbook.md` says to print rather than reason
about.

## Why it matters

A loop nest is the ordinary shape of the work `parallel for` exists to speed up,
and the workaround — hoisting the inner loop into a called function, which is
what the regression test for
`bug-a-a-shared-ansistring-handle-in-a-parallel-loop-is-11x-slower` had to do —
changes the code rather than the schedule. `while` compiling is what makes this
survivable and also what makes it confusing: the feature looks like it supports
nested loops.

## Gate

`make compiler/pascal26` + the repro above compiling and printing `acc=3000`,
plus the existing `parallel for` tests in the Makefile. Keep a `downto` case:
both arms are refused today and only one is likely to be exercised.

Found while measuring the heap-handle half of
[[bug-a-a-shared-ansistring-handle-in-a-parallel-loop-is-11x-slower]] — the
integrity test wanted an inner loop and could not have one.

## Resolved 2026-09-02 — the hypothesis was wrong, and the refusal was load-bearing

The ticket suspected the inner loop's `:=` had gone missing from the token
replay, and said not to take that as established. It had not. **A `^` was
ADDED.** `j` is an enclosing local, so it is a capture, so every reference in
the worker body gets a trailing `^` — including the one the `for` statement
uses as its control variable. `for j^ := 1 to 3` is not a for-loop the grammar
has, and the parser reports `expected ':='` pointing at that `^`.

The discriminating experiment was one line: make the inner control variable a
**global**, which is never captured, and the same program compiles. That
separates "the `for` statement" from "the capture rewrite" in a single build,
and it is what the boundary table could not do — every row in it used a local.

**Then the global version hung.** Which is the real finding: the two spellings
that compiled are both broken, and the refused one was the only safe one.

| spelling | before | why |
| --- | --- | --- |
| `for j := 1 to 3` (j local) | compile error | capture rewrite → `for j^ :=` |
| `j := 0; while j < 3` (j local) | **299674 / 299015 / 295718** of 300000 | one `j` shared through a pointer by every worker |
| `for g := 1 to 3` (g global) | **HANG** | a worker resetting g to 1 keeps the others' loops alive |

## The fix, and why it is not "allow `for p^ :=`"

Widening the grammar to accept a dereference as a control variable would have
made the reported program compile and then race exactly like the `while` one.
The construct is wrong for a reason that has nothing to do with syntax: **a
loop's control variable is written by the loop, so N workers sharing one is a
race by construction.**

So the control variable of an inner `for` becomes a worker-private local,
whatever its storage was outside — the rule OpenMP applies to loop variables
inside a parallel region, and the only reading under which all three rows above
come out right. A pre-scan over the captured body tokens collects every
`for <ident> :=`, declares each in the worker's own `var` section (reusing the
reduction accumulators' type-keyword rule, which exists because a bare
`tkIdent('Integer')` does not resolve as a named type), and excludes them from
the capture list, so the `^` is never appended.

Privatising a **global** control variable changes what that global holds after
the loop. Under parallelism that value was never defined, and the measured
alternative is a hang.

## What is still broken, deliberately

A variable the body merely WRITES — the `while` shape — is still a shared
capture and still racy. That is
[[feature-a-a-private-clause-for-parallel-for]], raised from 25 to 50 with the
numbers above: it was filed as "a class of body you cannot write", and it is
really "a class of body that compiles and quietly returns a short answer".

## Log
- 2026-09-02 — resolved, commit 4c94d248d.

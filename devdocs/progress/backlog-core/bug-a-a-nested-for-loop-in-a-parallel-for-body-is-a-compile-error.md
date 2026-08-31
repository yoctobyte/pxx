---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`parallel for` refuses a body containing an ordinary `for` loop — `error: expected ':='`, reported against lib/rtl/palthread.pas rather than the user's file. Measured boundary: `for` and `for ... downto` are the ONLY refused shapes; while, repeat, if, case and a nested begin/end all compile. The worker is synthesized by replaying captured tokens (PFStash, pasparser_stmt.inc ~3744-4330), and the inner loop's `:=` appears to be missing from the replay, so the defect is in the body token capture, not in the lowering."
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

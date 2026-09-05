---
slug: bug-p-a-generic-template-in-a-unit-may-reference-a-non-global-symbol
title: "A generic template declared in a unit can bind a symbol from the USING program, and nothing says no"
track: P
prio: 30
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "tgeneric4.pp specializes a generic declared in ugeneric4 at a point where the program has its own LocalFill; the template must bind the unit\'s, and FPC refuses the whole construct with `Global Generic template references static symtable`. pxx accepts it silently. It scored as a pass until 2026-09-05 only because the parser could not read ugeneric4 at all — the accidental-pass shape, third instance."
---

# The shape

`ugeneric4.pp` declares `generic TList<_T>` whose `Fill` method calls
`LocalFill`. The program `tgeneric4.pp` declares its OWN `LocalFill`, then
specializes. FPC refuses at the DECLARATION:

```
ugeneric4.pp(28,4) Error: Global Generic template references static symtable
```

The test is `{ %fail }` — the compile must be rejected. pxx compiles it and runs
it. **We have no diagnostic for a generic template referencing a symbol that is
not global**, so the binding is decided silently and the test's own comment says
what that costs in FPC's model: the assembler symbol is not global and would
fail at link time.

# Why it only became visible now

**It was passing for a reason unrelated to what it tests.** Pin v403 refuses the
file with:

```
pascal26:8: error: expected '>' before '>='
  in: ugeneric4.pp
```

— the unit spells its header `generic TList<_T>=class(...)` with no space, which
lexed as one `tkGe` token. A `%FAIL` row scores ANY refusal as a pass, so the
row was green because the parser stopped at the header. Fixing that lexing
detail (feature-pascal-corpus-fpc-testsuite) removed the accident and the row
went red the moment the compiler could read the file.

**Third instance of this exact shape**, and the two before it are
[[bug-p-a-generic-routines-implementation-type-parameters-are-not-checked-against-its-interface]]
(tgenfunc17, tgenfunc18, exposed the same way by `71deb21d4`). A `%FAIL` row is
a pass-by-refusal, so every parser capability we add can turn one red, and each
one is a missing diagnostic that was always missing.

# What to do

Decide first whether we WANT the diagnostic. CLAUDE.md ranks a differing
diagnostic as deferred, and this is not a differing one — it is an absent one on
a construct FPC rejects outright, so a program relying on it is relying on
something FPC will not build. That makes it closer to `accepts-invalid` than to
compat.

If the answer is no, this belongs in `pxx.skip` tagged `accepts-invalid:` and in
`known-incompat/`, NOT left as a red row — a permanently red conformance row is
a single-slot channel that hides the next real regression behind it.

**Do not "fix" it by re-breaking the header parse.** That is what was providing
the green.

# Gate

`tools/run_pascal_conformance.sh` — tgeneric4.pp must move from
`fail(accepted-invalid)` to pass-by-rejection, with the refusal naming the
template/symtable problem and not something incidental. Check WHY it refuses,
not that it refuses.

## 2026-09-05 (frankS) — a corpus-free repro, and the question this ticket has not asked

**First, a reproducibility gap nothing in this ticket says.** `tgeneric4.pp` and
`ugeneric4.pp` live in `library_candidates/fpc-testsuite/tests/test`, which is
**not fetched in every checkout** — mine has only `busybox` and `sqlite`. A
ticket whose evidence is a corpus path is reproducible only by whoever already
has the corpus, and the reader cannot tell from the ticket. So here is the shape
rebuilt from scratch, in two files anyone can paste. It reproduces FPC's exact
error, at the call site, so it is faithful:

`ug4.pas`:

```pascal
unit ug4; {$mode objfpc}
interface
type
  generic TList<_T> = class(TObject)
    procedure Fill;
  end;
implementation
procedure LocalFill;               { the UNIT's LocalFill }
begin WriteLn('UNIT LocalFill'); end;
procedure TList.Fill;
begin LocalFill; end;
end.
```

`tg4.pas`:

```pascal
program tg4; {$mode objfpc}
uses ug4;
procedure LocalFill;               { the PROGRAM's own LocalFill }
begin WriteLn('PROGRAM LocalFill'); end;
type TIntList = specialize TList<Integer>;
var l: TIntList;
begin
  LocalFill;                       { control: must print PROGRAM }
  l := TIntList.Create;
  l.Fill;                          { must print UNIT }
end.
```

FPC 3.2.2 refuses at the unit, never reaching the program:
`ug4.pas(11,21) Error: Global Generic template references static symtable`.

**Second, and this is the part that decides the ticket: it does not say which
`LocalFill` pxx binds.** "pxx accepts it silently" is a statement about
acceptance, and the disposition turns entirely on the value:

| if `l.Fill` prints | then | disposition |
| --- | --- | --- |
| `UNIT LocalFill` | pxx resolved the template in its declaring context, which is what the source MEANT | FPC's refusal is an **implementation limit**, not a language rule — `wontfix: dialect-pass` |
| `PROGRAM LocalFill` | the template captured the **caller's** namespace; its meaning depends on who specializes it | a real wrong-observable bug, and a bad one |

The first row has a standing precedent in the very same skip list:
`tgeneric14.pp wontfix: dialect-pass — test header says %fail is an FPC
IMPLEMENTATION limitation ("assembler symbols not global"), not a language rule
— PXX passing is correct`. FPC's objection here is the same family: a *global*
generic template is re-expanded in the importer's context, where a unit-private
`LocalFill` has no global assembler symbol. That is a fact about FPC's expansion
model, and this ticket's own body already concedes it — *"the assembler symbol is
not global and would fail at link time"*.

**Not yet measured, and it must be measured before either bucket is written
down.** The pin cannot answer: it refuses `ugeneric4.pp` at the header
(`expected '>' before '>='`), which is the accidental-%FAIL trap this ticket
already documents. It needs a HEAD build.

Note the trap in reading the control: the program's own `LocalFill` call MUST
print `PROGRAM`. If both lines print `PROGRAM`, check the control before
concluding capture — a probe where the wrong answer and one right answer share a
spelling is the collision this repo has been bitten by before.

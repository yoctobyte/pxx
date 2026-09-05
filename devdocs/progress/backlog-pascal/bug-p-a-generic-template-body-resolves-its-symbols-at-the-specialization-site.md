---
slug: bug-p-a-generic-template-body-resolves-its-symbols-at-the-specialization-site
title: "A generic template body resolves its symbols at the SPECIALIZATION site, so it captures the caller and cannot see its own unit"
track: P
prio: 55
type: bug
blocked-by: []
status: backlog
owner: ""
created: 2026-09-05
summary: "MEASURED 2026-09-05 (frankS), and the direction is the OPPOSITE of what this ticket said. A generic template body resolves its symbols AT THE SPECIALIZATION SITE, in the specializing scope, and the declaring unit's scope is never consulted. Two defects, not one. (1) WRONG OBSERVABLE: a unit template calling its own LocalFill runs the PROGRAM's LocalFill when the program happens to declare that name -- the method's meaning depends on who specializes it. (2) LEGAL SOURCE REFUSED: remove the program's LocalFill and the unit no longer compiles at all -- `undefined variable (LocalFill)` against a procedure ten lines above the template method IN THE SAME FILE. So a template can never use its own unit's private helpers. Identical on pin v403, so pre-existing and not fallout from the template-visibility work. NOT `wontfix: dialect-pass`: FPC refusing this (`Global Generic template references static symtable`) is FPC diagnosing a limit its expansion model has; pxx has the SAME limit and silently rebinds instead of diagnosing. Raised 30 -> 55: a silent wrong answer plus a refusal of legal code is not a missing diagnostic. Corpus-free two-file repro in the body."
---

**RENAMED 2026-09-05** from `bug-p-a-generic-template-in-a-unit-may-reference-a-non-global-symbol`, which asserted the OPPOSITE of what was
measured. Grep that name to find older citations; it is recorded here so they
still resolve. The rename was affordable because the old slug had ZERO code
citations and one live ticket reference, and it was WORTH doing because
`ready`/`next` print the slug and nothing else, so the queue was advertising a
false claim at p55 to every reader choosing work.

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

## 2026-09-05 (frankS) — MEASURED, and the ticket had the direction backwards

The discriminating question this ticket had not asked — *which* `LocalFill` does
pxx bind — turns out to have a third answer that neither row of my own table
predicted. Both probes use the corpus-free pair above.

**Probe A — the program declares its own `LocalFill`:**

```
PROGRAM LocalFill        <- the control: the program's direct call. Correct.
PROGRAM LocalFill        <- l.Fill, which must print UNIT. IT DOES NOT.
```

**Probe B — the control that settles it. Same unit, same template call, but the
program's `LocalFill` is DELETED:**

```
pascal26:11: error: undefined variable (LocalFill)
  in: ug4.pas
  near: TIntList . Fill ; begin LocalFill >>> ; end ;
```

The unit no longer compiles. `LocalFill` is a procedure **ten lines above the
template method in the same file**, and the template body cannot see it.

**So the mechanism is: a generic template body resolves its symbols AT THE
SPECIALIZATION SITE, in the specializing scope, and the declaring unit's scope is
never consulted at all.** Probe B is what makes that a measurement rather than an
inference — without it, Probe A is equally consistent with "the unit's
`LocalFill` was shadowed", and the two have different fixes.

**Identical on pin v403** (both probes, same output, same error), so this is
pre-existing and not fallout from the template-visibility work.

### This is two defects, and the ticket counted one

1. **A wrong observable.** A template method's meaning depends on who specializes
   it. The unit's author writes `LocalFill` meaning their own; a program that
   happens to declare that name silently substitutes its own. No diagnostic.
2. **Legal source refused.** A template body can never call its own unit's
   private helpers — the ordinary way anybody would factor a unit. This is not a
   divergence at all; it is a refusal of code that has to work.

The second is the one that moves the rank, and it is the half the original
framing could not see, because *"pxx accepts it silently"* is a statement about
the accepting case only. **Raised 30 → 55.**

### Why it is NOT `wontfix: dialect-pass`, despite the tgeneric14 precedent

I went looking for that precedent and it does not hold. FPC's `Global Generic
template references static symtable` **is FPC diagnosing a real limit of its own
expansion model** — a global template re-expanded in the importer's context
cannot reach a unit-private symbol. The precedent case (`tgeneric14.pp`,
*"assembler symbols not global"*) is an FPC limit that pxx **does not share**, so
pxx passing is correct there. Here pxx has **the same limit FPC has** and, rather
than diagnosing it, silently rebinds to whatever the specializer's scope offers.
Sharing a limit and hiding it is the opposite of the dialect-pass argument.

### Two notes for whoever repairs it

- The title and summary were wrong in a specific and instructive way. *"may
  reference a non-global symbol"* had the direction backwards — it **cannot**
  reference its own non-global symbols, and instead reaches the caller's. Fixed
  in place; the slug stays as the citation key.
- Read Probe B before designing anything. A fix that only stops the capture
  (defect 1) and does not give the body its declaring scope will convert every
  such template into `undefined variable`, turning a silent wrong answer into a
  refusal — which is *better*, but is not the whole job and should be a
  deliberate choice rather than a surprise.

## 2026-09-06 (frankZ) — independently reproduced, and the SHARD has a second row

Reached this from the other end — `test-pascal-conformance#shard1/6` went red in
the tier — and arrived at the same defect with the same repro shape before
finding this ticket. **Everything above stands; nothing here corrects it.** The
independent reproduction is worth one line only because it came from a different
starting point and a different box, and agreed: a unit template's `Fill` calling
its own `Helper` runs the PROGRAM's `Helper`, silently, exit 0.

Also confirmed pre-existing by compiler rather than by pin — the shape compiles
and misbinds at `b8e3b3010`, at `f4f5cfee0~1`, at `f4f5cfee0` and at master, so
"identical on pin v403" is not a pin artefact.

### What this ticket does not cover: the shard is TWO rows

The disposition section above would move `tgeneric4.pp` to pass-by-rejection.
**That alone does not green the shard.** Measured either side:

| | pass | fail | skip |
| --- | --- | --- | --- |
| `b8e3b3010` | 63 | **0** | 24 |
| master | 70 | **2** | 15 |

    test-pascal-conformance: FAILURES: tgeneric4.pp(accepted-invalid)
                                       tgenfunc14.pp(accepted-invalid)

**`tgenfunc14.pp` is a different construct with a different question.** It is a
unit declaring `generic procedure Test<T: class>` in the interface and repeating
the constraint in the implementation; its own comment is *"constraints must not
be repeated in the definition"*. That is a REDUNDANCY FPC forbids, not a wrong
observable — accepting it produces no wrong answer and refuses no legal code, so
unlike `tgeneric4` it looks like a genuine `wontfix:`/`known-incompat` under
CLAUDE.md's *"us accepting what FPC rejects is not a defect"*. **Recommendation
only — not ruled on here, and deliberately not classified by me**, because a
row's classification is Track P's call and this ticket is the one that will be
read when someone touches the shard.

### The skip entries were burned CORRECTLY — do not go looking there

Both rows were skip-listed and both entries were removed by
`5d6c169d1 feat(P): conformance 347 -> 368 — 21 skip entries had outlived the
gaps they describe`. That commit is **not** at fault and should not be revisited:
the harness routes a `%FAIL` row that COMPILES to `bump_fail`/`stillgap`, never
to "stale", so `--retry-skips` could not have recommended burning these. They
were genuinely passing — correctly rejected — when the entries went. Checked
because the retry summary's own wording (*"$stale now EXIT-CLEAN"*) reads as
though it inverts on `%FAIL` rows; only that summary line is loose, the routing
is right.

The acceptance flipped for BOTH rows somewhere in `b8e3b3010..f4f5cfee0~1`, 192
commits dense with legitimate generic-routine work. **Not pinned further on
purpose**: the acceptance is an improvement nobody should revert, so naming the
exact commit buys nothing, and the defect it exposed is older than the bracket.

### The trap this row sets, stated because I nearly walked into it

Every visible signal said "classify and move on": CLAUDE.md's *"us accepting
what FPC rejects is not a defect"*, a matching `wontfix:` category in the
harness, and the test's own comment blaming an FPC linker limitation
(*"the assembler symbol is not global"*). **The discriminator was RUNNING the
binary** — it prints `Program` and halts 1 where the test demands `Unit`, and
none of that evidence required running anything. A `wontfix:` on `tgeneric4`
without this ticket in place would have converted a silent wrong-code bug into a
green row with a reason attached.

---
slug: bug-p-an-unqualified-call-to-a-user-routine-named-read-or-write-is-eaten-by-the-intrinsic
title: "PARTLY FIXED — a GLOBAL routine still cannot be NAMED Read/Write; the expression-position call is done"
track: P
prio: 40
type: bug
status: backlog
found: 2026-09-05
found-by: frankB
owner: ""
blocked-by: []
summary: "EXPRESSION-POSITION HALF IS FIXED (c7632de85): an unqualified Read/Write naming a METHOD of the enclosing class now resolves in expression position, through one predicate shared with the statement arm. WHAT REMAINS is row 6 of the table below -- a GLOBAL (non-method) routine cannot be NAMED Read/Write/Readln/Writeln at all: `function Read(var B; C: Longint): Longint;` is refused at the DECLARATION with `expected name`, because IsMethodNameKind in pasparser_name.inc admits these tokens in METHOD-name position and the routine-name path never got the same predicate. FPC accepts it -- `read` is not a reserved word there, which is the premise pasparser_name.inc is already written around. Ranked BELOW the fixed half on evidence rather than on shape: the FPC compiler corpus wanted the METHOD spelling, and no unit in it declares a global routine by these names, so nothing measured is blocked on this today."
---

# The measurement — the FPC compiler-source march, re-run 2026-09-05

Re-run by frankB after `feature-pascal-typed-and-untyped-files` landed, against
compiler `62fa62403452` (self-host fixedpoint verified) at master `2316f7058`.
Corpus is FPC 3.2.2's own compiler sources, `/usr/share/fpcsrc/3.2.2/compiler`,
which IS installed on this box even though `library_candidates/` has no copy —
the previous note on the typed-files ticket said it was unavailable in the
checkout, which was true of the checkout and wrong about the box.

**Invocation matters and the earlier march was missing a define.** pxx has no
standalone-unit output, so each unit is reached through a three-line driver
program that `uses` it, and FPC's own build passes `-dx86_64` — without it
`globtype.pas` stops at `unknown type: PInt`, because `PInt` is declared inside
`{$ifdef cpu64bitaddr}` and `fpcdefs.inc` derives that from `x86_64`. That is a
CORPUS SETUP defect, not a pxx one, and it masked everything behind it:

```
pxx -Mobjfpc -dx86_64 -Fu$C -Fi$C -Fu$C/x86_64 -Fi$C/x86_64 drv_<unit>.pas
```

| unit | before (2026-08-27) | now |
| --- | --- | --- |
| `cutils`, `globtype`, `constexp`, `version` | OK | OK |
| `cclasses` | `file types are not supported` | **`cstreams.pas:227 expected expression`** |
| `cstreams` | `file types are not supported` | **`cstreams.pas:227 expected expression`** |
| `comphook` | `file types are not supported` | **`cstreams.pas:227 expected expression`** |
| `finput` | `file types are not supported` | **`cstreams.pas:227 expected expression`** |
| `cfileutl` | `file types are not supported` | `conditional directive: comparison requires integer operands` |
| `cmsgs` | `TMessage = object` (predicted) | `unknown type: TSystemCodePage` |

**Claim only what was checked: these units no longer stop THERE. None of them
BUILDS.** The typed-file refusal is gone from every row that had it, which is
what the typed-files ticket predicted and is all it predicted.

Two side-findings worth carrying: `cmsgs` does NOT stop where the old table
said it would — it never reaches `TMessage = object`, so the row that was used
to keep [[decide-old-style-object-types]] closed was measured through a define
gap. And `cfileutl`'s conditional-directive refusal is a separate defect that
has never had a ticket.

# The defect

`cstreams.pas:227`, in `TCStream.ReadBuffer`, and the sibling at `:236`:

```pascal
procedure TCStream.ReadBuffer(var Buffer; Count: Longint);
  begin
     CStreamError:=0;
     if Read(Buffer,Count)<Count then     { <-- refused }
       CStreamError:=102;
  end;
```

`Read` is `TCStream.Read`, declared in the same class. This is not an obscure
spelling — it is the shape of `TStream.ReadBuffer` in FPC's and Delphi's own
RTL, and `TStream.Read`/`Write` is one of the most-used method pairs in the
Pascal world.

## The boundary, varied rather than assumed

22-line repro, and five neighbours run against `62fa62403452`:

| # | shape | verdict |
| --- | --- | --- |
| 1 | unqualified `Read(B,C)` in EXPRESSION position, inside a method | **`expected expression`** |
| 2 | `Self.Read(B,C)`, same place | accepted |
| 3 | `s.Read(B,C)` from outside the class | accepted |
| 4a | unqualified `Read(B,C);` as a BARE STATEMENT, inside a method | accepted |
| 4b | unqualified `n := Read(B,C)` (assignment RHS) | **`expected expression`** |
| 4c | unqualified `writeln(Read(B,C))` (argument) | **`expected expression`** |
| 5 | unqualified `Write(B,C)` in expression position | **`expected expression`** |
| 6 | global `function Read(var B; C: Longint): Longint;` | **`expected name`, at the DECLARATION** |

**CORRECTION to this ticket's first draft, which labelled row 4 "statement
position" and had it failing.** It does not: a bare `Read(B,C);` statement is
ACCEPTED, because `pasparser_stmt.inc`'s intrinsic arm already grew exactly this
test for `bug-bare-read-write-in-method-hits-intrinsic`. What I had written as
one statement-position row was an assignment whose RHS is an expression. The
defect is **EXPRESSION POSITION ONLY**, which makes it the textbook
`devdocs/dev/normalise-dont-special-case.md` case rather than a general
name-resolution gap: the statement path was fixed, twice, and the expression
path was never built, so the second path is the one that stayed broken.

So it is **QUALIFICATION plus POSITION**: rows 2 and 3 go through the member
path, which `IsMemberNameTok` already admits these tokens to, and row 4a goes
through the statement arm that already asks. Rows 1, 4b, 4c and 5 reach
`ParseFactorCore`, whose 8000-line `case CurTok.Kind of` has no arm for
`tkRead`, so they land on its `else Error('expected expression')`.

**Row 6 is a SECOND, EARLIER defect and should not be folded into the first.**
`IsMethodNameKind` admits `tkRead` in method-name position, so the class member
declares fine — but a global routine name does not use that predicate, so
`function Read(...)` cannot be declared at unit or program level at all. FPC
accepts it; `read` is not a reserved word in FPC, which is the premise
`pasparser_name.inc` is already written around.

# Where it lives

`compiler/paslexer.inc:122,152` makes the tokens. `compiler/pasparser_name.inc`
holds the two predicates that already re-admit them, and its comment states the
principle: *"Read/Write/Readln/Writeln are intrinsics resolved by context at the
call site, not true reserved words — FPC lets a user declaration shadow them."*
**Context at the call site is exactly what is missing** — the statement dispatch
at `pasparser_stmt.inc:5346` has one narrow instance of it already (a function
assigning its own result by a name that lexes as an intrinsic), which is the
precedent for the general rule and shows the shape of the check.

# Gate

The repro above, both directions: the six rows, with 2/3 still accepted so the
fix cannot be a blanket "never treat it as an intrinsic". Plus a POSITIVE
CONTROL that the intrinsic still wins where nothing shadows it — an ordinary
`Read(f, x)` and `Write(f, x)` on a Text and on a typed file, which is what
`test_typed_file_of_t.pas` already asserts, so that test is the control and
must stay green. Then re-run the march and record which row moves.

## The march after the fix, 2026-09-05 — `cstreams.pas` BUILDS

Re-run with compiler `946502b21167`, same invocation as above.

| unit | before this ticket | after the expression fix | after `FileMode` |
| --- | --- | --- | --- |
| `cstreams` | `cstreams.pas:227 expected expression` | `cstreams.pas:396 undefined variable (filemode)` | **OK — compiles** |
| `cclasses` | `cstreams.pas:227` | `cstreams.pas:396` | `cclasses.pas:676 unknown type: TFPCHeapStatus` |
| `comphook` | `cstreams.pas:227` | `cstreams.pas:396` | (behind `cclasses`) |
| `finput` | `cstreams.pas:227` | `cstreams.pas:396` | (behind `cclasses`) |
| `cfileutl` | — | — | `conditional directive: comparison requires integer operands` |
| `cmsgs` | — | — | `unknown type: TSystemCodePage` |

**`cstreams.pas` is the first FPC compiler unit to compile end to end here.**
The two steps were a parser fix and an RTL variable, in that order, and the
second was only visible once the first landed — which is the argument for
walking a corpus rather than triaging a backlog: `FileMode` was not on anyone's
list, and it was one line of real blocking.

The three remaining walls are all RTL/preprocessor gaps rather than parser gaps
(`TFPCHeapStatus`, `TSystemCodePage`, and a `{$if}` comparing non-integer
operands), so the next holder is looking at Track B or the directive evaluator,
not at `pasparser_*`.

## RETRACTION, 2026-09-05 — two of this ticket's findings were artefacts of MY invocation

**`--mimic-fpc-compiler` exists and I was hand-rolling a worse version of it.**
`defs.inc:2943` documents it precisely: *"Its sources are not standalone: every
unit does `{$i fpcdefs.inc}`, whose branches are dead without the build-time CPU
define ... One define is the whole profile — fpcdefs.inc derives the rest."*
That is exactly the `PInt` failure I diagnosed and patched around with
`-dx86_64`. My workaround set ONE of the defines the profile sets; the flag sets
the profile. **The correct invocation is:**

```
pxx --mimic-fpc-compiler -Fu<C> -Fi<C> -Fu<C>/x86_64 -Fi<C>/x86_64 driver.pas
```

Two findings recorded above do not survive it:

**1. The `cfileutl` conditional-directive wall IS NOT A DEFECT.** I wrote that it
*"is a separate defect that has never had a ticket"*. It is
`{$if FPC_FULLVERSION < 20701}` at `cfileutl.pas:155`, and `FPC_FULLVERSION` is
defined — as 30202, in `paslexer.inc:954` — **by the profile my invocation was
not applying.** Under the flag, `cfileutl` does not stop there at all. There is
no ticket to file and there never was.

What that episode DID produce is real and is fixed in the same commit as this
retraction: the diagnostic said `comparison requires integer operands`, which is
true about the value stack and useless about the program, because an identifier
with no value pushes as a BOOLEAN and so a missing define presents as a type
mix. It now names the symbol. **The bug was in the message, not in the
evaluator, and the message is what sent me into the evaluator.**

**2. THE `cmsgs` CORRECTION WAS ITSELF WRONG, AND THE ORIGINAL TABLE WAS
RIGHT.** I wrote that the old march table's `cmsgs -> TMessage = object` row
*"was never a measurement of what it has since been cited for"*, on the strength
of `cmsgs` stopping at `unknown type: TSystemCodePage`. Under the correct
invocation, with `TSystemCodePage` added, `cmsgs` stops at **`cmsgs.pas:59`, an
object type cannot have a constructor** — `TMessage = object` with
`constructor Init`, exactly as the original table said. **The citation in
[[decide-old-style-object-types]] stands.** I relayed the retracted version to
two peers before measuring it under the right flag; both have been told.

The general lesson is the one this ticket already carries about `-dx86_64`,
turned on its author: **a corpus result is a statement about an INVOCATION.** I
found the first setup gap, patched it by hand, and then read every subsequent
wall as a property of the compiler — including one that contradicted a standing
citation. A hand-rolled substitute for a flag is a configuration nobody else
runs, so every number it produces is unshared.

## The march, re-measured under `--mimic-fpc-compiler` — ONE compiler, ONE run

**Compiler `108f95a7f278`** (self-host fixedpoint, `rounds 1`, srchash
`edbd7f597bca`), at master `3b60635ec` plus the `TSystemCodePage` and `{$if}`
diagnostic changes in this commit. Three different compiler shas appeared in
this ticket's earlier reports as the work advanced; **every row of the table
below is from a single run of that one binary**, so nothing here is stitched
together from different trees.

| unit | verdict |
| --- | --- |
| `cutils`, `globtype`, `constexp`, `version`, **`cstreams`** | **OK — compile** |
| `cclasses`, `comphook`, `finput`, `cfileutl` | `cclasses.pas:676 unknown type: TFPCHeapStatus` |
| `cmsgs` | `cmsgs.pas:59 an object type cannot have a constructor` — DECIDED, not a gap |

So there is exactly **ONE** open wall on this corpus, not three, and `cmsgs` is
behind a decision rather than behind work. See
[[feature-b-getfpcheapstatus-needs-always-on-heap-accounting]].

## 2026-09-05 (frankB) — this is the CALL side of a DECLARATION defect

Measured: the call never happens. `procedure Write;` / `procedure SysOpen;` is
refused at the DECLARATION with `expected name`, so the user name cannot exist
to be shadowed, and the call-site framing above is downstream of that.

Root cause and the whole cluster — nine spellings, one mechanism, with the
blast radius enumerated — is
[[bug-p-nine-intrinsic-spellings-are-hard-keywords-so-they-cannot-be-user-names]].
**Work that one, not this one**: a fix aimed at the call site is aimed at the
wrong half, and fixing only the declaration would leave a routine that is
declared and then silently never called, which is worse than today's refusal.

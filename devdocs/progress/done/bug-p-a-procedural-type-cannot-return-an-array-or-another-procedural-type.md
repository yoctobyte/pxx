---
slug: bug-p-a-procedural-type-cannot-return-an-array-or-another-procedural-type
track: P
prio: 30
type: bug
status: done
blocked-by: []
owner: frankB
created: 2026-09-04
found-by: frankH (ProcRet* column census)
summary: "RESOLVED 2026-09-06. `TF = function(n: Integer): TIA` (dyn array), `: TA3` (fixed array) and `TOuter = function: TInner` (procedural) all parsed as DECLARATIONS and refused at the CALL; fpc 3.2.2 answers 14, 12 and 42 and pxx now matches on 13 rows. ONE cause as this ticket said -- ParseProcTypeSignature parsed its return with a bare ParseTypeKind -- and the fix is the LIFT it asked for: ParseSubroutine's entire return-type region is now ParseFuncReturnTypeShape (pasparser_decl.inc) and both callers share it, so all 19 ProcRet* columns are written from one block. THREE THINGS THE TICKET DID NOT HAVE. (1) Its own DIRECT-call control was false: `MkOuter()(41)` was refused too, which is what moved the `(` arm from BuildIndirectCallAST (where the repro lives, and where it went green) into ApplyCallResultPtrSuffix, the one materialisation point that serves both spellings. (2) The whole-value assignment `b := fq(4)` COMPILED and answered 4310400 0 0 against fpc 104 204 304, on pin v404 too -- ir.inc's aggregate-assign arm knew AN_CALL and AN_VIRTUAL_CALL and not the other three; now ASTNodeIsCall. (3) The same closed-world list in both postfix index arms excluded AN_CALL_IND on a stated reason that was FALSE, so `rc.fn()[1]` through a record FIELD answered IR_UNSUPPORTED kind 53 while the proc-VARIABLE spelling was correct -- harmless until this commit filled the columns that made the kind reachable. Split out: nothing."
---

# A procedural type cannot return an array, or another procedural type

Found 2026-09-04 by a census of the `ProcRet*` columns, not by a report. The
census was prompted by frankA after `ProcRetRecId` turned out to be the third
dropped field in a row in the same function, all three between the same two
existing comments.

## The census, and it is the useful part of this ticket

`ParseSubroutine` (the ordinary routine header, `pasparser_proc.inc`) fills all
17 `ProcRet*` columns. The three declaration paths in `pasparser_decl.inc` fill
the same 11 and drop the same 6:

| column group | reachable? | measured |
| --- | --- | --- |
| `EnumId` | **was LIVE** | fixed — prints the ordinal, not the member name |
| `RecId` (`ParseProcTypeSignature`) | **was LIVE** | fixed — selector at offset 0 |
| `RecId` (`ParseRecordMethodDecl`) | **NO** | `v.M(8).c` already answers 24 |
| `ProcSig` | **LIVE** | `fo()(41)` refused; FPC 42 |
| `IsDynArray` `DynDepth` `ElemTk` `ElemRec` | **LIVE** | `fp(3)[2]` refused; FPC `3 14` |
| `FixedArrBytes` `ArrAi` | **LIVE** | `fp(4)[2]` refused; FPC `12` |

The `RecId`-on-`ParseRecordMethodDecl` row is why the census was worth running
rather than reasoning about: it is a real asymmetry in the matrix and **not** a
defect, because a record method's row is filled again when its BODY goes through
`ParseSubroutine`. Only a routine that is declaration-ONLY — an interface
method — stays unfilled, which is exactly the row that was still wrong after the
`EnumId` reader was fixed.

## Repro

```pascal
type TIA = array of Integer;      TF1 = function(n: Integer): TIA;
     TA3 = array[0..2] of Integer; TF2 = function(k: Integer): TA3;
     TInner = function(k: Integer): Integer; TOuter = function: TInner;
```

`fp1(3)[2]` → `expected ')' before '['` · `fp2(4)[2]` → same · `fo()(41)` →
`expected ')' before '('`. FPC 3.2.2 `-Mdelphi` answers `14`, `12`, `42`.

**Each has a DIRECT-call control that passes**, which is what says this is the
signature path and not the feature: `Mk(3)[2]`, `Mk(4)[2]` and a direct chained
call all work today.

## Why it is one cause and not three

`ParseProcTypeSignature` parses its return type as a bare `ParseTypeKind`.
`ParseSubroutine` does not — it has a whole block ahead of that call which
recognises `array of T`, a named array type and a fixed array, and sets
`retIsDynArr` / `retArrAi` / `retElemTk` before the type name is consumed. The
signature path has none of it, so an array return type is not merely unrecorded,
it is **unparseable**: `mRetType` comes back as the ELEMENT kind with no way to
tell it from a scalar.

`ApplyCallResultPtrSuffix` then reads `ProcRetIsDynArray` / `ProcRetFixedArrBytes`
/ `ProcRetArrAi` to pick its suffix arm, finds a scalar, and declines — which is
the refusal above.

`ProcSig` is the cheaper half and may be separable: the column fill is one line
(the shape `ProcRetRecId` now uses), but `fo()(41)` also needs the parser to try
an argument list after a call whose result is procedural. `PasNodeProcSig`
(`pasparser_call.inc`) is the natural place — it answers "is this NODE a
procedural value" for AN_IDENT / AN_FIELD / AN_INDEX today and a call node is
the missing kind.

## Shape of the fix

Lift the array-return recognition out of `ParseSubroutine` so both paths share
it, rather than copying the block. That is the same normalisation the three
already-fixed columns wanted and did not get — this function has now produced
four dropped fields, which is the count `root-cause-over-microfix.md` calls a
design flaw rather than a smell.

## Gate

The three repros above with their direct-call controls, each **reading an
element or calling through**, never merely compiling: two of the three fixed
columns in this family turned a refusal into a silent wrong value when only half
the fix was in, so a compiles-or-not check certifies nothing here. Oracle: FPC.

## Reproduces at HEAD, at the CALL — and the near miss is worth recording (frankS, 2026-09-05)

At `0bbd82cd7` (compiler/pascal26 sha `7fca108e4b85`), with all three return
types NAMED, as this ticket writes them:

```pascal
type
  TIA = array of Integer;  TA3 = array[0..2] of Integer;
  TInner = function(n: Integer): Integer;
  TF = function(n: Integer): TIA;  TF3 = function(n: Integer): TA3;
  TOuter = function: TInner;
var fp: TF; fq: TF3; fo: TOuter;
begin WriteLn(fp(3)[2]); WriteLn(fq(4)[2]); WriteLn(fo()(41)); end.
```

`pascal26:11: error: expected ')' before '['` — the declarations all parse and
the first CALL is where it refuses, exactly as the summary states.

**The first probe of this pass got it wrong in a way that would have read as a
result.** It spelled the return type inline (`function: array of Integer`) and
got `pascal26:3: error: unknown type: array` — a refusal at the DECLARATION, for
an anonymous array type, which is a different and genuinely illegal construct.
Same ticket, same slug, plausible error, wrong claim. A staleness pass that
accepted it would have recorded "refuses at declaration" over a ticket whose
whole point is that declarations parse and calls do not — and the next reader
would have gone looking in `ParseProcTypeSignature`'s declaration path, where
there is nothing wrong.

## RESOLVED 2026-09-06 — the parse was lifted, not copied, and the ticket's own control was false

Test: `test_a_procedural_type_returns_an_array_or_another_routine`, 13 rows,
`fpc -Mobjfpc` 3.2.2's own output byte for byte.

**THE SHAPE OF THE FIX IS THE ONE THIS TICKET ASKED FOR.**
`ParseSubroutine`'s entire return-type region — the parse AND the enum / set /
managed-string / record / procedural-signature / pointer arms that read the
`LastType*` channels it leaves — is now `ParseFuncReturnTypeShape`
(`pasparser_decl.inc`), and both callers use it. 170 lines out of
`ParseSubroutine`, 13 in. `ParseProcTypeSignature` then writes all nineteen
`ProcRet*` columns from one block instead of one at a time from whichever
channel survived. That is what closes the class: this one function had dropped
**six** columns, each found separately by its own silent-wrong-value bug over
five weeks.

**THE FIRST EXTRACTION WAS WRONG AND THE COMPILER DID NOT SAY SO.** I took the
block from `if CurTok.Kind = tkArray then` down to the last
`retType := ParseTypeKind;`, which *reads* like the whole recognition. It is
not: the third arm is `else begin`, and that `begin` closes ~80 lines further
down, past every consumer. So the helper had an unclosed `begin` and
`ParseSubroutine` an orphan `end` — and what came back was **`undefined variable
(NestStrOff)` in `pasparser_stmt.inc`**, a file I had not touched, naming a
function defined 2600 lines *below* my edit in the file I had. PXX prescans
headers; the desynced brace ended the prescan early, so everything declared
after my insertion point stopped existing, and the error surfaced in the first
file that *used* one of them. **A brace error reported as a name error in
another file.** The control that named it was reverting my two files and
rebuilding: green. `begin`/`end` counting over the comment-stripped block is now
how I choose an extraction boundary.

**THE TICKET'S OWN DIRECT-CALL CONTROL WAS FALSE, AND IT CHANGED WHERE THE FIX
GOES.** This ticket says *"each has a DIRECT-call control that passes"* and names
`fo()(41)`'s direct spelling among them. `MkOuter()(41)` was refused too —
`expected ')' before '('`. I found it because the test file asserts the controls
rather than citing them. It matters structurally: I had already put the arm in
`BuildIndirectCallAST`, where my repro lives, and it was **green**. An arm there
greens the ticket's repro and leaves the ticket's own control red — a one-site
fix wearing a full green. The arm belongs in `ApplyCallResultPtrSuffix`, which
its own forward declaration calls *the ONE materialisation point for a suffix on
a call RESULT*, and from there the direct and indirect spellings are fixed
together.

**`(` WAS A MEMBER OF A CLOSED-WORLD SET NOBODY HAD LISTED.** The suffix set was
`.`, `[`, `^` — what you can do to a returned VALUE. `(` is what you can do to a
returned ROUTINE, and it needs no materialisation at all: the result IS the code
address, so it is the callee of one more indirect call. `f()()()` falls out
because `BuildIndirectCallAST` comes back through the same door. `ProcRetProcSig`
had been filled on a procedural type's row since the `RecId` work — **the reader
was missing, not the column.**

**AND A FOURTH CLOSED-WORLD GUARD, THIS ONE IN `ir.inc`, HOLDING A SILENT WRONG
VALUE.** The whole-static-array-from-a-call assign arm spelled its own
`(AN_CALL) or (AN_VIRTUAL_CALL)` — two of the five kinds. With the array columns
now filled, `b := fq(4)` for `TF3 = function(k: Integer): TA3` fell through to
the **scalar store** and printed `4310400 0 0` where fpc prints `104 204 304`.
Measured on **pin v404 as well**, so it is not a consequence of this fix — it is
a defect this fix made *reachable through a second spelling* and would otherwise
have shipped alongside it. It is now `ASTNodeIsCall`, whose own comment says it
exists because that test was copied five times and the copies drifted. **This arm
was the sixth copy and drifted the same way.** Only `AN_CALL_IND` is measured;
`AN_CLASS_VIRTUAL_CALL` and `AN_INTF_CALL` come with the helper, and the comment
says which is which.

**THE ROWS THAT WOULD HAVE BEEN OMITTED ARE THE ONES THAT MATTER.** Indexing was
refused *outright* — loud, and the half the ticket is written about. The
whole-value assignment **compiled** and answered garbage. A test asserting only
the indexed spellings goes green with the silent half still broken. Rows G and H
print every element, because element 0 alone passes while 1 and 2 are garbage,
and rows J/K index 0 deliberately — 0 is exactly where a scalar store leaves a
plausible number.

**THE ORACLE IS `fpc -Mobjfpc` AND THAT IS NOT A WEAKENING.** fpc 3.2.2 raises an
**internal compiler error** on `fn := fo()` under `-Mdelphi` — *"Compilation
raised exception internally"*, no output at all — and compiles the identical
program under `-Mobjfpc`. Isolated to that one statement rather than inferred
from the line number the first failing run reported, which pointed at a
different line. pxx's default mode is the objfpc-shaped one and every procedural
assignment in the test is written with `@`, so `-Mobjfpc` is the *matching*
oracle. Nothing is worked around in the compiler for it.

**TWO COMMENTS IN ONE FILE DISAGREED AND THE FALSE ONE WAS LOAD-BEARING.**
`pasparser_lval.inc` excluded `AN_CALL_IND` from both index arms *"on purpose —
its IVal is a signature, not a Procs[] index, so there is no return shape to
read"*, while `BuildIndirectCallAST`, in the same file, says *"It takes a Procs[]
index and a signature row IS one"*. The second is right:
`ParseProcTypeSignature` returns a `RegisterProc('$proctype')` row. I had left it
alone — I had no repro that reached the arm, and deleting a guard on a *reading*
is what "verified, not believed" forbids — and reported it to frankA instead.
frankA came back with a repro, I ran it, it **passed**, and running it produced
the SIBLING that does not:

    f()[1]        6                                  fpc 6    proc VARIABLE
    rc.fn()[1]    IR_UNSUPPORTED ... kind 53         fpc 6    record FIELD
    av[0](3)[1]   (same compile)                     fpc 6    array ELEMENT

**One construct, three builders.** A proc-variable call goes through
`BuildIndirectCallAST` and reaches the shared suffix handoff; a field and an
element each build their `AN_CALL_IND` inline at their own site and land in the
postfix loop's index arm. So the only spelling on the fixed path was the one my
repro used. Rows A..K are green with L and M broken.

**AND THE EXCLUSION WAS HARMLESS UNTIL THIS COMMIT MADE IT A BUG.** The gate
beside it is `ProcRetIsDynArray or ProcRetFixedArrBytes > 0`, and those columns
were never filled on a signature row — so the guard was false for every
`AN_CALL_IND` anyway and its wrong reason cost nothing. **Filling the columns is
what made the kind reachable.** A comment that had been false since the day it
was written started mattering the moment an unrelated hole was closed, which is
the same shape as *a hole in a shared path is invisible until someone widens an
unrelated guard into it* — read from the other end.

Both arms are now `ASTNodeIsCall`, the third and fourth site in this commit that
spelled its own call-kind list and knew four of five.

**Gate:** `tools/gate.sh quick` with the tree DIRTY (FPC seed canary PASS; 16
rows PASS; the only RED is `pinned builds live lib/rtl`, which is frankZ's
`8374118ec` waiting on an owner-only pin). AND `PXX_ALLOW_FULL_SUITE=1 make
test`, lifted deliberately and stated here rather than in a rule: this changed
the return-type parse for **every routine in the compiler** and one arm of the
IR assign path, so the blast radius is the whole frontend and quick's coverage
of it is partial in the way that looks total.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1aee0f035.

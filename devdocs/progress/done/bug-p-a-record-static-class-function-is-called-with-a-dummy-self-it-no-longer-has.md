---
track: P
prio: 75
type: bug
status: done
owner: frankS
resolved-by: frankS
created: 2026-09-09
found-by: frankZ
tags: [abi, records, static, managed-types, regression]
blocked-by: []
summary: "REGRESSION I INTRODUCED IN b0d53c73a. A record's `class function ... static` called through the type name was still passed a by-value dummy Self it no longer has: that commit removed the Self parameter and left a call site which hand-rolls its own argument loop still prepending the dummy, so the argument chain was one longer than the signature. The lowering pairs by POSITION, so the dummy took parameter 0 and every real argument took the parameter before its own -- visible ONLY in the managed-argument temp, which was therefore built for the dummy while the real string was passed as a bare literal. Measured against fpc 3.2.2 across eight signatures: one AnsiString argument gave Length = 1073741824, a second argument of any kind after it SEGFAULTED, and every unmanaged spelling stayed correct. That is why the self-host fixedpoint and gate.sh quick both missed it -- compiler.pas never writes this shape -- and why it surfaced as a segfault in test_generic_nested_inline_specialize, three subsystems away, with no generics in the defect at all. Fixed by not building the dummy when UMthNoSelf, i.e. by making the chain the right LENGTH; retyping the dummy was tried first and measured to change nothing, because the lowering does not read the AST node's kind. Fixture asserts VALUES on all eight rows and the PINNED pre-regression compiler matches it too."
---

# A record's static class function is called with a dummy Self it no longer has

- **Type:** bug (regression) — **Track P** (`compiler/pasparser_expr.inc`).
- **Introduced by** `b0d53c73a`, mine.
- **Found by** frankZ, as a segfault in `test_generic_nested_inline_specialize`;
  reduced by frankZ to seven lines with no generics in them.

## The repro (frankZ's)

```pascal
program y1; {$mode objfpc}{$H+} {$modeswitch advancedrecords}
type TP = record K: Integer; V: AnsiString;
  class function Make(const a: Integer; const b: AnsiString): TP; static; end;
class function TP.Make(const a: Integer; const b: AnsiString): TP;
begin Result.K := a; Result.V := b; end;
var p: TP;
begin p := TP.Make(3,'three'); WriteLn('y1 ', p.K, '/', p.V); end.
```

fpc and the pin print `y1 3/three`. HEAD segfaulted.

## The mechanism

`b0d53c73a` made the `static` directive mean **no Self parameter**. The call
site at `pasparser_expr.inc` — the one an assignment's right-hand side takes —
hand-rolls its own argument loop and kept prepending a by-value dummy Self,
which before that commit was correct and lined the chain up with the parameter
list. Afterwards the chain was one argument longer than the signature, and the
lowering pairs by **position**.

Nothing about that is visible until an argument is **managed**, because the only
thing that reads the pairing is the managed-argument temp. IR for
`TP.Make('three')` against `Make(const b: AnsiString)`:

```
pinned   const_int 0 tk=17 -> arg                 the dummy, a pointer
         const_str -> store_sym tk=23 -> arg      the STRING gets the temp
HEAD     const_int 0 tk=23 -> store_sym -> arg    the DUMMY gets the temp
         const_str -> arg                         the string gets none
```

So the callee read a length word behind a bare literal.

## Measured, eight signatures, values not exit codes

| parameters | fpc | HEAD |
| --- | --- | --- |
| `(Integer)` | 3/0 | 3/0 |
| `(AnsiString)` | 5/0 | **1073741824/0** |
| `(Integer; AnsiString)` | 3/5 | **SEGFAULT** |
| `(AnsiString; Integer)` | 5/3 | **1073741824/3** |
| `(AnsiString; AnsiString)` | 5/2 | **5/1073741824** |
| `(Integer; Integer)` | 3/4 | 3/4 |
| `(Integer; Integer; AnsiString)` | 7/5 | **SEGFAULT** |
| `(Integer; AnsiString; Integer)` | 7/5 | **SEGFAULT** |

**Three of the eight exit 0 and print the wrong number.** Both frankZ and I
first published a rule that was wrong because our probes read `rc` or printed a
literal `ok`: mine said "the second argument", frankZ's said "any managed
argument after the first". The truth is **any managed argument at all**, and it
only became visible once every row printed its value. frankZ caught my version;
the corrected matrix caught frankZ's.

## Why nothing caught it

- **The self-host fixedpoint cannot**: `compiler.pas` is a deliberately
  procedural subset that never writes a record static factory with a managed
  argument. That is the documented scope limit of that gate, and this is a live
  instance of it.
- **`gate.sh quick` cannot**: the only in-tree program that reaches the shape is
  in `test-core`, which is not in the quick tier — so every seat's per-fix gate
  was green over it for hours (frankZ's observation, recorded here rather than
  in two places).
- It surfaced **three subsystems away**, as a generics segfault, because
  `TPair<Integer, AnsiString>` is the only thing in that test carrying a managed
  field into a static factory.

## What was tried and did not work

Retyping the dummy — `StaticDummySelfTk` instead of `ParamOwnKind(mpi, 0)` at
all three sites that hand-build it. **Measured: changes the AST node's `tk` and
changes nothing else**, because the lowering pairs arguments with the parameter
list by position and never reads that node's kind. Recorded because it is the
obvious fix and it is wrong: the chain has to be the right LENGTH, not the right
types. Reverted rather than landed beside the real fix.

## Not fixed here

`TP.Make('three').Bump` — a selector chained onto a record static's result —
is refused with `expected ')' before '.'`. **The pin refuses it too**, so it is
pre-existing and out of scope.

## Two notes carried from frankZ rather than written twice

- **A bisect that SKIPS is not being careful, it is answering a different
  question.** `git bisect run` with a plain `make compiler/pascal26` skipped
  four commits in a row: the build seeds from the local binary, which at each
  step came from a tree hundreds of commits away, so the failures were seed
  drift. The fix is `make seed-from-stable` before each build, `touch` on the
  sources, and removing `compiler/.pascal26.fixedpoint`.
- **`test-core` sits outside `gate.sh quick`**, and a regression in ordinary
  Pascal survived in-tree because of it. Recorded as an observation with its
  evidence; widening a gate spends Track T's machine and is not a call to make
  from inside a fix.

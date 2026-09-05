---
prio: 45
track: P
status: done
summary: "FIXED 2026-09-05. `for x in p` over a set PARAMETER was refused for all three element kinds (`set of TEnum`, `set of Char`, `set of Byte`) and all three passing modes (value, const, var), named or anonymous, while the identical loop over a set LOCAL had always worked. THE METADATA WAS THERE AND THE READER WAS READING A DIFFERENT COLUMN: ptypesSetEnum was already captured in the correct per-parameter window, but only ever flowed to ProcParamSetEnumId, which the CALLER reads to check arguments -- nothing stamped the parameter's own SYMBOL, and ParseForInSetAST reads SymSetEnumId/SymSetElemTk off the symbol. A set parameter therefore had SymSetEnumId=-1 and SymSetElemTk=0 inside the body, which is byte-identical to `no element kind recorded`, so the diagnostic named three supported cases while describing a set that was all three. Fixed by staging the other three columns (ElemTk/Lo/Hi) in the same window and stamping all four after AllocParam, exactly as the enum, frozen-string and typed-file params already do. Found as the FIRST wall of corpus rung 7 (fcl-passrc pastree.pp:1890), reached in 1.06s -- the rung's wall then MOVED to :2101, which is the corpus-level evidence the fix is load-bearing."
---

# A set parameter lost its element kind, so `for x in p` refused it

- **Type:** bug — Track P (Pascal frontend)
- **Status:** DONE 2026-09-05 (frankB)
- **Fix:** `compiler/pasparser_proc.inc` — `ptypesSetElemTk/Lo/Hi` staged beside
  the existing `ptypesSetEnum`, and all four stamped onto the parameter symbol
  in the allocation loop.
- **Tests:** `test/test_set_param_for_in.pas` (+ `.expected`, byte-identical to
  fpc 3.2.2) and `test/test_set_param_for_in_anon.pas` (+ `.expected`, no fpc
  oracle by construction — see below). Both wired into `make test`.

## What it looked like

```pascal
type TM = (mA, mB, mC); TMs = set of TM;
procedure P(const q: TMs); var m: TM; begin for m in q do Write(Ord(m)); end;
```
`error: for-in: set iteration supports set of <enum>, set of Char or an ordinal
set constructor` — for a parameter that is precisely `set of <enum>`.

The message was not wrong about its own inputs. `BuildForInSetLoop` reaches its
`else Error(...)` when the symbol carries neither an enum id nor an element
kind, and that is what a parameter carried. It described the value stack
faithfully and said nothing about the program, which is the same shape as the
`comparison requires integer operands` note in `paslexer.inc`.

## The boundary, which is what identified the cause

| shape | before |
| --- | --- |
| local, anonymous `set of TM` | works |
| local, named `TMs` | works |
| value / const / var param, named or anonymous | **all refused** |
| `set of Char` param, `set of Byte` param | **refused** |
| set as a record FIELD | works |

Locals and record fields both worked, which ruled out the type alias and the
element kinds and left exactly one thing in common: the parameter symbol. So
this was never the alias-identity family it first resembled
([[bug-p-a-type-alias-drops-the-enum-identity-and-a-set-drops-its-char-element-kind]]);
varying the shape before touching anything is what separated them.

## Why only one of four columns had been captured

`ptypesSetEnum` exists and is captured correctly — its window discipline was
already right. It just goes somewhere else: `ProcParamSetEnumId`, the
argument-check column the CALLER reads. Nothing wrote the callee-side symbol.
And because only the *enum id* was staged, `set of Char` and `set of 1..9` had
no representation at all even if someone had stamped it — hence four columns,
not one.

Same family as the four notes already in that file (`ptypesStrCap`,
`ptypesFileRecSize`, `ptypesStrElemTk`, `ptypesEnum`), all of which exist
because the allocation loop runs *after* every parameter's type is parsed and
therefore reads the LAST one. `test_set_param_for_in.pas`'s `2nd of 3` row is
the control for exactly that.

## Two notes on the tests

- The `local named` row is a **control that passed before the fix**. A test
  declaring only locals would have been green either way.
- The anonymous-set spelling is in its own file because **fpc refuses it**
  (`Type identifier expected`), so it has no oracle. Keeping it in the main file
  would have cost that file its oracle for all seven other rows. Us accepting
  what fpc rejects is not a defect.

## Left open, deliberately

[[bug-p-for-in-over-a-set-returning-function-call-is-refused]] — found in the
same pass, a different mechanism (the container dispatch, not the element-kind
test), and this fix did not move it. Filed rather than folded in.

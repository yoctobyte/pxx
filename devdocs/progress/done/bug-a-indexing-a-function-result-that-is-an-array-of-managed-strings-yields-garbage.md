---
track: A
prio: 58
type: bug
blocked-by: []
summary: "`FS[0]` where `function FS: array[0..2] of AnsiString` yields the empty string with Length 1, and `FS[1]` yields a single garbage character, where FPC yields the strings that were assigned. Indexing the same function's result after assigning it to a variable is correct, and the identical shape with an Integer element or a `string[8]` element is correct. Only a MANAGED string element, only when the call result is indexed directly."
status: done
owner: frankS
---

# Indexing a function result that is an array of managed strings yields garbage

- **Type:** bug — **Track A** (the AN_INDEX-over-a-call-result lowering in
  `compiler/ir.inc`).
- **Found:** 2026-08-30 by frankwasm, while measuring `feature-unicodestring-model`
  step 6b against `pinned`. Wrong on **both** `pinned` and the step-6b build, so
  it is not that work.

## Measured, against FPC 3.2.2

```pascal
type TSA = array[0..2] of AnsiString;
     TIA = array[0..2] of Integer;
     TFA = array[0..2] of string[8];
function FS: TSA; begin FS[0] := 'ret'; FS[1] := 'two'; end;
function FI: TIA; begin FI[0] := 42;    FI[1] := 7;     end;
function FF: TFA; begin FF[0] := 'frozen';              end;
var t: TSA;
```

| expression | FPC | pxx |
| --- | --- | --- |
| `FS[0]` , `Length(FS[0])` | `ret` , `3` | **`` (empty) , `1`** |
| `FS[1]` | `two` | **`p`** — one garbage character |
| `FI[0]` , `FI[1]` | `42` , `7` | `42` , `7` |
| `FF[0]` | `frozen` | `frozen` |
| `t := FS;` then `t[0]` , `t[1]` | `ret` , `two` | `ret` , `two` |

Four controls, one broken cell. The element type is the variable that matters:
an **Integer** element and a **frozen `string[8]`** element are both correct
through the identical call-and-index shape, and the managed-string array is
correct as soon as the result is assigned to a variable first. So the array, the
function, the assignment inside the function and the indexing are all fine
individually — it is specifically *indexing the call result* when the element is
a **managed** string.

`Length` answering **1** and `FS[1]` answering a single character are the tell
worth keeping: a one-character answer from a managed string is what reading a
byte of a HANDLE looks like, which is the shape of
[[bug-p-a-char-array-is-not-a-string-in-any-direction]] and of the C-side
`bug-c-a-string-literal-row-of-a-2d-char-array-stores-its-address`. **That is a
resemblance, not a diagnosis** — do not write it into this ticket as the cause
without a probe.

## Suggested first measurements

- `PXXDBG=a.ir:<caller>` around the `FS[0]` expression: is the call result being
  treated as the string itself rather than as an array of handles?
- Whether the result temp is materialised at all, given that the whole-result
  assignment path works — the difference between the two is where to look.

Per `devdocs/dev/root-cause-over-microfix.md`, vary the shape before choosing a
fix: try a `record` element and a dynamic-array element to find the real
boundary of "managed", since AnsiString may not be the only element type
affected.

## Gate

`make compiler/pascal26` + the program above matching FPC on all five rows.

---

## FIXED (frankS, 2026-08-30)

### The site is not `ir.inc`, and it is not Track A's file

The ticket guessed *"the AN_INDEX-over-a-call-result lowering in
`compiler/ir.inc`"*. The AST is already wrong before lowering runs, so `ir.inc`
was never involved. The decision is made in the suffix parser —
**`compiler/pasparser_lval.inc`**, whose header reads *"Owned by Track P (Pascal
frontend)"*. Flagged rather than re-laned: it was dispatched as A, no agent held
P, and the fix is one arm of a Pascal-only designator rule.

### Measured, not reasoned — the AST carries the wrong type

`s := FS[0]` in a named `Probe`, `PXXDBG=a.ir:Probe`, broken build vs the
working `t := FS; s := t[0]`:

```
BAD   5: index a=3 b=4 c=1 ival=1 tk=3  [lo=1 size=1]
GOOD  6: index a=4 b=5 c=0 ival=8 tk=23 [lo=0 size=8]
```

`tk=3` is `tyChar`, `tk=23` is `tyAnsiString` (`defs.inc:1620`). `lo=1 size=1` is
**string** indexing — 1-based, one byte per element. So `FS[0]` was lowered as
"character 0 of a string", which is below a 1-based lower bound: it reads the
byte before the data, hence `Length` **1** and one garbage character. The AST
dump shows the same `tk=3` on the `AN_INDEX` node before lowering, which is what
moved the search out of `ir.inc`.

### The mechanism: a double case where one arm grew the guard and its sibling did not

`pasparser_lval.inc`, the call-result suffix chain, in source order:

```pascal
else if (tk = tyAnsiString) and (CurTok.Kind = tkLBrack) then   { <- no array exclusion }
  node := GenMakeStringValueIndex(node);
else if ((tk = tyClass) or (tk = tyRecord)) and (...) and
        not ((CurTok.Kind = tkLBrack) and
             (ProcRetIsDynArray[procIdx] or (ProcRetFixedArrBytes[procIdx] > 0))) then
else if ((ProcRetFixedArrBytes[procIdx] > 0) or ProcRetIsDynArray[procIdx]) and ...
```

`Procs[].RetType` carries the **ELEMENT** kind, so `function FS: array[0..2] of
AnsiString` reads as `tyAnsiString` at the first arm and is consumed by it before
the array arm below is ever reached. The record arm in between already carries
the exclusion, and its comment states the rule outright — *"What decides the arm
is whether the RESULT is an array, not what its elements happen to be."* The
AnsiString arm needed the identical guard and never got it.

`NodeIsIndexableStringValue`'s header documents this same trap for the *other*
two shapes it handles, and closes by asserting that *"every other node kind that
can reach here with a string tag is a string VALUE (a literal, a concatenation, a
call result…)"*. **That last item is the false premise** — a call result is a
string value only when the return type is not an array — but that function was
never in the path here, so the assertion was load-bearing one level up rather
than where it was written.

Textbook `devdocs/dev/normalise-dont-special-case.md`: an array of RECORDS was
excluded by hand, an array of STRINGS was not.

### The fix

The same exclusion the record arm carries, added to the AnsiString arm. Excluded,
the call falls through to the fixed/dyn-array arm, which materialises a **shaped**
temp — so the N-D spelling comes free, as that arm's comment predicted.

### Boundary — the sweep that explains why this survived

| element type | node's `tk` | arm taken | before |
| --- | --- | --- | --- |
| `AnsiString` | 23 `tyAnsiString` | string-value | **broken** |
| `ShortString` | 26 | fixed-array (`copy_rec`) | ok |
| `string[8]` | 26 `tyFixedString` | fixed-array (`copy_rec`) | ok |
| record | 5 `tyRecord` | record arm — **has the guard** | ok |
| dynamic `array of AnsiString` | 17 `tyPointer` | dyn-array | ok |

Only `tyAnsiString` reaches the unguarded arm. That is why
`test_index_a_call_result_directly` — which already covered Integer, 2-D Integer,
`string[8]`, record, N-D record, computed subscript, call-once and `Copy` — could
not catch it: its frozen-string row is `tyFixedString` and never enters that arm.
**A managed-string element was the one shape the existing differential test did
not have.**

### Verification

- `make compiler/pascal26` — `converged after 1 round(s)`, fixedpoint verified,
  binary `e6de8cdf1198`.
- All five of the ticket's rows now match FPC 3.2.2 exactly.
- The three string-VALUE index paths `GenMakeStringValueIndex` exists for —
  `Up('x')[1]`, `(a+b)[2]`, `'hello'[1]` — all unchanged and matching FPC.
- `tools/gate.sh quick` GREEN.

### Regression test

Extended `test/test_index_a_call_result_directly.pas` rather than adding a file —
it is this feature's own FPC-differential test and the gap was inside it. Four
rows added (1-D managed, its `Length`, and the N-D managed spelling both ways).
`.expected` regenerated by **FPC compiling the file**, per the test's own header,
and pxx matches it byte for byte.

The pre-fix compiler fails the new rows **two** ways: the 1-D row yields
`Length` 1 and one garbage character, and the N-D managed spelling
`MkMStr2[1, 0]` does not compile at all (`expected ']' before ','`). Both are
fixed, the second as a free consequence of the shaped temp.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.

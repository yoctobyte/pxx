---
track: A
prio: 58
type: bug
blocked-by: []
summary: "`FS[0]` where `function FS: array[0..2] of AnsiString` yields the empty string with Length 1, and `FS[1]` yields a single garbage character, where FPC yields the strings that were assigned. Indexing the same function's result after assigning it to a variable is correct, and the identical shape with an Integer element or a `string[8]` element is correct. Only a MANAGED string element, only when the call result is indexed directly."
status: new
owner: ""
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

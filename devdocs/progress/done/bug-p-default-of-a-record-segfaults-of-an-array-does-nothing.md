---
track: P
prio: 75
type: bug
blocked-by: []
summary: "`Default(T)` yielded the integer 0 for every T, so an aggregate had no zero value: `a := Default(TRec)` copied RecSize bytes from address 0 and SEGFAULTED, and `ar := Default(TArr)` silently did nothing at all -- a dirty array stayed dirty with no diagnostic."
status: done
owner: frank1-ACP
---

# `Default(TRecord)` segfaults; `Default(TArray)` silently does nothing

- **Track P** (`compiler/parser.inc`, the `tkDefault` factor).
- Found 2026-08-20 by an FPC differential probe over records.

## The measurement

`fpc -O- -Mobjfpc` 3.2.2 vs pxx at `907f18d9e`:

```pascal
type TArr = array[0..2] of Integer;
     TPt  = record x, y: Integer; end;
var ar: TArr; a: TPt; i: Integer;
begin
  for i := 0 to 2 do ar[i] := 7;
  ar := Default(TArr);   writeln(ar[1]);
  a.x := 3;
  a := Default(TPt);     writeln(a.x);
```

| step | FPC | pxx |
| --- | --- | --- |
| `ar := Default(TArr)` then `ar[1]` | 0 | **7** — the assignment did nothing |
| `a := Default(TPt)` | 0 | **SIGSEGV** |

The scalar forms — `Default(Integer)`, `Boolean`, `Double`, `Pointer`, an enum,
`string`, a dynamic array, a class — were all correct.

## Root cause

The factor produced one node for every type:

```pascal
{ Default(T): zero value of the type — ordinals/pointers/chars in v1
  (records/strings later). }
node := AllocNode(AN_INT_LIT);
ASTIVal[node] := 0;
ASTTk[node] := Ord(tyInt64);
```

then skipped the type name to the closing paren without ever looking at it.
"records/strings later" describes the intent; what it actually did was hand an
Int64 to a record assignment, which copies `RecSize` bytes from the source
address — 0. For a static array the integer went into the first slot's store
path and the array was left alone, with no diagnostic, which is the worse of
the two failures: a crash has a location.

## The fix

Zero of an aggregate is a whole zeroed **object**, not a number, so materialise
one. When the type names a record (or a one-dimensional fixed-array alias), the
parser mints a hidden **static** variable of that exact type and yields an
`AN_IDENT` to it. Static means BSS, which the loader zero-fills, and nothing
can ever write to it because `Default()` is an rvalue — it cannot be passed by
reference or assigned through. The ordinary record/array copy then does all the
real work, managed fields included, with no new codegen anywhere.

Two deliberate exclusions:

- **A class is not an aggregate here.** `IsRecordType` returns `REC_NONE` for
  one, so `Default(TCls)` keeps the integer 0 — which is exactly its `nil`.
- **A multi-dimensional or row-element array alias errors loudly** rather than
  falling back to the integer 0. `AllocArray` cannot rebuild that shape from
  `lo`/`hi` alone, and falling back is precisely what made this a silent bug
  the first time. `Default: multi-dimensional array types are not supported
  yet` is a compile error, not a wrong answer.

## Test

`test/test_default_of_aggregate.pas`, 29 FPC-verified rows: every scalar form
(so the fix is proved not to have moved them), the record that segfaulted, the
array that did nothing, a record with nested-record + managed + array fields,
a record whose first field is a record, an array of strings, the hidden zero
used twice and inside a loop (it must still be zero the second time),
`Default(T)` as a value argument, and the whole set again from inside a routine
— where the hidden zero has to be static BSS and not a stack temp. The pinned
binary cannot even compile it: `SumArr(Default(TArr))` reports `argument types:
(Int64)`.

## Gate

`make compiler/pascal26` fixedpoint converged after 1 round; `tools/gate.sh
quick` GREEN. The full record differential probe (packed vs unpacked SizeOf,
variant-record overlay, `with`, typed consts, by-val/var/const params, advanced
record methods, `Default`) now matches FPC line for line.

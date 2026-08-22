---
slug: bug-a-indexing-a-parenthesised-string-compiles-and-segfaults
track: A
prio: 50
status: done
commit: c8b6c6690
---

# Indexing a parenthesised string compiles clean and segfaults

```pascal
var s: string;
begin s := 'abcd'; WriteLn((s)[3]); end.
```

```
ok: … [code=60267B data=1688B bss=42452B procs=123]
Segmentation fault (core dumped)
```

No diagnostic. The compiler reports success and the program dies. fpc 3.2.2
prints `c`.

Three shapes, one cause, in descending order of how bad the failure is:

| shape | before |
| --- | --- |
| `(s)[3]` | **compiles, then SEGFAULTS** |
| `(s + 'x')[3]` | `IR_UNSUPPORTED` — loud, at least |
| `'hello'[1]` | syntax error — loud |
| `K[1]` (named const) | worked |
| `UpperCase(s)[1]` (call result) | worked |
| `s[3]` (direct) | worked |

## Cause

`AN_INDEX` needs an **addressable base**. A string variable has one — the slot
holding its handle. A string *value* does not.

`pasparser_lval.inc`'s string-returning-call arm already knew this and said so:

> AN_INDEX needs an addressable base, so materialise the result into a hidden
> temp first and yield `(tmp := call, tmp[i])` via AN_COMMA.

`pasparser_expr.inc`'s **grouped-expression** suffix loop had its own copy of
index handling, written for arrays, which builds a raw `AN_INDEX` and copies the
base's type across:

```pascal
indexNode := AllocNode(AN_INDEX);
ASTLeft[indexNode] := node;
…
ASTTk[indexNode] := ASTTk[node];      { tyAnsiString, not tyChar }
```

For a string that indexes the **handle** rather than a slot holding one, i.e. it
reads a char out of whatever the handle's bits happen to address. Hence the
segfault, and hence its silence: nothing along the path is wrong enough to
notice.

`(s + 'x')[3]` failed one step earlier at lowering, and the bare literal simply
had no trailing-`[` loop at its primary — a named string constant has had one
since `bug-const-string-index-miscompiles`, and a literal is the same
`AN_STR_LIT` node lowered the same way.

This is `devdocs/dev/normalise-dont-special-case.md` with a crash attached: the
comment in the file even notes that the grouped-expression tail was already
"the THIRD copy of member/index dispatch", and that duplication was the bug.
Indexing was the arm nobody had gone back for.

## Fix

Extract `GenMakeStringValueIndex(valNode)` in `pasparser_lval.inc` — consume
`[`, materialise into a hidden temp, index that, wrap in `AN_COMMA`, yield
`tyChar` — and call it from **both** the call-result arm (which loses its inline
copy) and the grouped-expression arm. Forward-declared in `pasparser_name.inc`
because one caller sits above the definition.

The bare literal deliberately does **not** route through it: a literal's storage
*is* addressable (`IRLowerAddress` reaches its `IR_CONST_STR`), so it needs no
temp, and it gets the same trailing-`[` loop the named constant already has.

## Verification

`test/test_indexing_a_string_value.pas`, wired into `test-core`,
byte-identical to fpc 3.2.2. The row that justifies the temp is **`once`** — a
function with a side effect, indexed as `(Counted)[2]`, must run exactly once
(`y 1`), which a naive re-evaluation would get wrong while still printing the
right character. The `named` / `fncall` / `direct` / `arr` rows pin the shapes
that already worked, including array indexing through parentheses, which shares
the arm that was changed.

Also verified: nested parentheses `((s))[3]`, a computed index `'hello'[i + 2]`,
and a variable index over a literal in a loop.

`make compiler/pascal26` fixedpoint converged in 1 round; `tools/gate.sh quick`
green.

## Follow-up in the same ticket: the first fix was too broad, and regressed one row

The first commit (`e7d8667c3`) tested `IntToTypeKind(ASTTk[node]) = tyAnsiString`
to decide "this is a string value". That is not a sound test, and a
grouped-expression sweep run immediately afterwards caught it:

**An ARRAY node carries its ELEMENT kind in `ASTTk`.** So an
`array of AnsiString` and a plain `AnsiString` read *identically* there, and
`(sa)[2]` — indexing an array of strings — went down the materialise-into-a-
string-temp path and produced the wrong value. It had worked before. Fixed
within the hour, in `NodeIsIndexableStringValue`:

- an **identifier** is decided by its symbol (`Syms[].IsArray`);
- a record **field** by its declaration (`RecFieldIsArray`, keyed on the same
  source span codegen re-resolves it by);
- every other node kind that can reach here with a string tag *is* a string
  value — a literal, a concatenation, a call result, an element already selected
  out of an array.

The same sweep surfaced two more pre-existing rows in the same arm, both
confirmed against the **pinned** compiler, both now fixed by widening the kind
test rather than by adding arms:

| shape | before | why |
| --- | --- | --- |
| `('hello')[2]` | printed a **chunk of the data segment** | a parenthesised literal is tagged `tyString`, not `tyAnsiString` |
| `(ss)[2]` (ShortString) | printed nothing | tagged `tyShortString` |
| `(r.s)[2]` (string field) | **segfault** | `AN_FIELD` was never considered |

So the arm had four broken spellings and one correct one, and the correct one
(`(a)[i]` over an array) is what the code had been written for. Materialising
through an `AnsiString` temp is right for every string flavour, so all four go
through one path.

Lesson worth keeping: **a type TAG is not a type.** `ASTTk` answers "what kind
of value does indexing this yield", which is the element kind for an array and
the string kind for a string — the very question being asked collapses the two.
The symbol table is what distinguishes them.

## Found by

A 37-program string differential — concatenation, `Copy` with out-of-range /
zero / negative arguments, `Pos`/`PosEx`, `Delete`/`Insert` at the edges,
character read and write, copy-on-write through aliases and `SetLength`, empty
strings, comparison and `CompareText`, `Trim` family, `ShortString` and
`string[N]` truncation, `PChar` round trips including the empty case, records
and arrays of strings, `const`/`var` string parameters, quoting. **36 of 37
matched FPC**; the 37th was the literal-index row, and narrowing *that* found
the segfault, which no row of the sweep had covered.

---
slug: bug-p-an-implicit-deref-over-a-typed-pointer-cast-is-dropped
track: P
prio: 50
type: bug
status: backlog
blocked-by: []
created: 2026-09-06
found-by: frankD
owner: ""
summary: "`PRec(x).field` — a typed pointer CAST used with `.` — drops the implicit dereference and reads the field at an offset into the pointer VALUE, printing a silent wrong number with no diagnostic. `PRec(x)^.field` one character to the left is correct. NOT depth-related and NOT the pointer-to-pointer bug it was found beside: it reproduces at depth 1, and the Aug 29 pin fails it identically, so it is pre-existing. fpc 3.2.2 prints 55, pxx prints 0."
---

# A typed pointer cast used with `.` loses the implicit dereference

```pascal
type TRec = record a, b, c, d, e: Integer; end;
     PRec = ^TRec;
var r: TRec; x: Pointer;
begin
  r.e := 55; x := @r;
  WriteLn(PRec(x).e);    { fpc: 55    pxx: 0  }
  WriteLn(PRec(x)^.e);   { fpc: 55    pxx: 55 }
```

One character apart, one correct. The cast spelling reads the field at an offset
into the pointer value instead of through it — the same silent-wrong-value
signature as `bug-p-an-implicit-deref-over-an-explicit-caret-is-dropped`, and a
DIFFERENT cause.

## It is not the bug it was found beside, and that took one probe to establish

Found while fixing the pointer-to-pointer implicit deref. The natural reading was
that the cast case was the same defect not yet fully repaired — the fix went in,
the variable spellings went green, and the cast spelling did not move. **The
probe that separated them was a SINGLE-level cast**, `PRec(x).e`: it fails too,
and depth-1 has nothing to do with pointer-to-pointer.

So `ResolveNodeRec`'s deref chain was never the blocker here. Whatever declines to
insert the implicit deref for a cast base declines at depth 1.

**Pre-existing:** `stable_linux_amd64/default/pinned` (Aug 29) prints `0` for the
same program.

## Where to start, and what NOT to assume

The implicit-deref arm is `compiler/pasparser_lval.inc:2564` — it fires on
`tk = tyPointer`, builds an `AN_DEREF`, and inserts it only if
`ResolveNodeRec` answers a record that really has the member. For a cast base the
AST is `AN_FIELD → AN_PTR_CAST → AN_IDENT` with no deref at all, so the question
is whether that arm is reached and declines, or is never reached because an
earlier arm claims an `AN_PTR_CAST` base first. **Measure which; do not read it
off the arm order.**

Two tables carry what a fix will need, and they come in immediate/ultimate pairs
that read identically at the call site:

| immediate pointee | ultimate base |
| --- | --- |
| `AliasElemRec` | `AliasPtrBaseRec` |
| `Syms[].PtrElemRec` | `SymPtrBaseRec` |

Both are written on the same fifteen lines of `pasparser_decl.inc` (~7151).
The sibling fix used the wrong half of **both** before measuring, once each —
`AliasElemRec`/`PtrElemRec` are `REC_NONE` for a pointer-to-pointer, so the wrong
choice makes a fix silently do nothing rather than fail loudly.

`PXXDBG=a.symptr:<name>` prints the pair for a symbol and is the instrument that
settles it: for `q: PPRec` it says `depth=2 ptrElemTk=17 baseTk=5 baseRec=23` —
pointee is a POINTER, base is the record.

## Trap for the test

**Assert a LATE field.** Offset 0 is what a lost base resolves to, so a probe on
the first field cannot tell a correct answer from a dropped deref. Use a record
wider than a pointer, too, or a size row can collide with 8.

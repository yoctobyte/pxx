---
slug: bug-p-an-implicit-deref-over-a-typed-pointer-cast-is-dropped
track: P
prio: 50
type: bug
status: done
blocked-by: []
created: 2026-09-06
found-by: frankD
owner: frankB
summary: "RESOLVED 2026-09-06 by the SAME ARM as bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref: the two are the depth-1 and depth-2 faces of one absent step, and each ticket says explicitly it is not the other. The cause is neither depth nor the cast: ParseClassRecordSelectors -- the SHARED selector walker that the three hand-rolled postfix cast loops delegate to -- has no implicit-deref arm, while ParseLValueAST 2100 lines above it in the same file has had one since `p.a` first worked. Its builder makes AN_FIELD and nothing else, so `PRec(x).field` applied the offset to the POINTER VALUE. Fixed there, plus the C4 loop's delegation guard widened so a pointer-valued `.` reaches the walker at all. THIS TICKET'S 'NOT depth-related and NOT the pointer-to-pointer bug' was right about the depth and wrong about the partition -- same cause, same line. Test: test_a_pointer_cast_dereferences_implicitly_for_a_selector (rows A/B/D), fpc 3.2.2's own output byte for byte; row B is a METHOD through the implicit deref, which a fields-only fix would leave calling with a pointer as Self while every number still printed correctly."
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

## RESOLVED 2026-09-06 — see the sibling ticket for the full write-up

Fixed by the same arm as
[[bug-p-a-cast-to-a-pointer-to-pointer-drops-the-implicit-second-deref]], which
carries the measurement, the 2x2 that located it and the scope error that cost
the most time. Both faces are in one wired test,
`test_a_pointer_cast_dereferences_implicitly_for_a_selector`.

**The one line worth having here rather than only there:** this ticket's
`NOT depth-related and NOT the pointer-to-pointer bug it was found beside` is
correct about the DEPTH and wrong about the PARTITION. Depth really is
irrelevant — the arm is missing at every depth — and that is exactly why the two
reports are one defect. Establishing that two symptoms differ on one axis does
not establish that they differ in cause, and both tickets made that step
independently, in opposite directions.

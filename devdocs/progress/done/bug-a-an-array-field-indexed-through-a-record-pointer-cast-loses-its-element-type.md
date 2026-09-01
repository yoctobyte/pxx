---
slug: bug-a-an-array-field-indexed-through-a-record-pointer-cast-loses-its-element-type
title: "`PR(raw)^.m[3]` prints the double's bit pattern; `r.m[3]` and `pv^.m[3]` print 6.00"
track: A
prio: 50
type: bug
status: done
found: 2026-09-01
found-by: frankB
owner: frankB
blocked-by: []
summary: "FIXED 2026-09-01 (frankB). The record-cast chain's `[` arm in pasparser_expr.inc resolved the element kind for a pointer-to-array base and for a scalar alias, then clobbered tk with tyUnknown for every OTHER base -- including the common one, an array FIELD, whose element kind the field builder had already left in tk. So an indexed array field reached through a record-pointer cast came out untyped: `WriteLn(PR(raw)^.m[3]:0:2)` printed 4618441417868443648, the double's bit pattern, with the format spec silently ignored; `PR(raw)^.s[2]` printed 1869376613, the bytes of \"ello\". Both correct through `r.m[3]` and `pv^.m[3]`. Exit 0, wrong value, one of three spellings. PRE-DATES the 2026-08-27 pin -- verified by running stable_linux_amd64/default/pinned, which prints the same wrong value -- and is NOT multi-dim-specific. Pinned by test/test_index_through_record_pointer_cast.pas."
---

# An array field indexed through a record-pointer cast loses its element type

## Measured

Same record, same field, three spellings, at binary `1beb5391ebf6`:

| spelling | `WriteLn(... .m[3]:0:2)` |
| --- | --- |
| `r.m[3]` (direct) | `6.00` |
| `pv^.m[3]` (pointer VARIABLE) | `6.00` |
| `PR(raw)^.m[3]` (pointer CAST) | `4618441417868443648` |

`4618441417868443648` is `0x4018000000000000` — the IEEE-754 bits of `6.0`. The
bytes were always right; only the TAG was wrong, so `:0:2` was silently dropped
and the integer path printed the payload. The string face is the same clobber:
`PR(raw)^.s[2]` printed `1869376613` = `0x6F6C6C65` = `"ello"`, where `r.s[2]`
printed `e`.

## Cause

`pasparser_expr.inc`, the cast chain's `else if CurTok.Kind = tkLBrack` arm. It
asked `DerefPtrArrayElem` (right answer for `TP(raw)^[i]`), then the scalar
alias table (right answer for `PChar(s)[i]`), and then:

```pascal
else begin tk := tyUnknown; recName := REC_NONE; end;
```

An array FIELD is neither of those two, and the answer was already in hand:
`UFldTk` holds the ELEMENT kind for an array field (`defs.inc:4838`), so the
field builder one loop iteration earlier had left `tk = tyDouble`. The `else`
threw it away. Now the arm keeps it when the base `IsNodeArray`, and applies the
same string-index rule `ParseLValueAST` applies — one index rule, stated once.

## How it was found, which is the transferable part

**Not by a matrix row and not by this ticket's shape.** It came out of probing
the SIBLING `[`-arms after fixing the comma-subscript parse in the arm next
door ([[bug-a-a-comma-indexed-multi-dim-subscript-is-not-parsed-through-a-cast-or-call-result]]) —
`normalise-dont-special-case.md`'s "fixed one arm of a double case? grep for
the sibling before closing", run literally.

The first probe was ND, because that is what I had just been fixing, and it
looked like fallout of my own change. It is not: the 1-D form fails identically,
and `stable_linux_amd64/default/pinned` (2026-08-27) prints the same wrong value
for it. **Checking against the pin is what separated "I broke this" from "I made
this reachable enough to see"** — the two are indistinguishable from the failing
output alone, and only one of them is a revert.

# Gate

`make compiler/pascal26` (converged, `1beb5391ebf6`), `tools/gate.sh quick`
GREEN with the FPC seed canary PASS, `tools/derefshape_matrix.sh` 30/30,
`test/test_index_through_record_pointer_cast.pas`. Fixed in commit `62540cc27`.

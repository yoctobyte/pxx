---
track: A
prio: 30
type: feature
blocked-by: []
summary: "`w := 'lit'` on a WideString calls PXXWideFromStr at runtime and allocates, where the narrow `s := 'lit'` is a bare pointer store into a static block InternStr already laid down complete with [meta][rc][len]. The wide literal could be the same — transcoded at compile time, zero allocation — but InternStr unconditionally stamps MSTR_FLAG_ASCII|MSTR_FLAG_ASCII_KNOWN, which builtinwide.pas DELIBERATELY refuses to stamp on a wide block, so a folded literal would carry a flag its runtime twin rejects, marked KNOWN so nothing rescans. Needs a wide-aware intern entry point and an MSTR_KIND_WIDESTR constant in defs.inc."
status: new
owner: ""
---

# A wide string literal should be a static block, not a runtime transcode

- **Type:** feature — **Track A**, tagged **O** (optimisation).
  `compiler/emit.inc` (`InternStr`), `compiler/defs.inc` (one constant),
  `compiler/ir.inc` (`IRStrWidthConv`'s literal arm).
- **Deferred from** `feature-unicodestring-model` step 7c, deliberately and
  with the reason recorded there.

## What is paid today

7c lowers `w := 'abcd'` to `PXXWideFromStr('abcd')` — a call and a heap
allocation on **every evaluation**, including inside a loop. The narrow
equivalent `s := 'abcd'` costs neither: `InternStr` lays down a complete static
managed block in the data section (`[meta][rc][len]` at handle−24/−16/−8, the
refcount born saturated), so the assignment is a pointer store.

There is no reason the wide literal cannot be the same object with different
bytes. The transcode is compile-time work being done at runtime.

## Why 7c did not do it

`InternStr` computes the ASCII answer from the bytes and stamps it
unconditionally:

```pascal
meta := MSTR_KIND_LEGACY or MSTR_FLAG_STATIC or MSTR_FLAG_ASCII_KNOWN;
if (orAll and $80) = 0 then meta := meta or MSTR_FLAG_ASCII;
```

For a UTF-16 `'abcd'` the bytes are `61 00 62 00 …` — no byte ≥ $80 — so it
would set **ASCII**. `builtinwide.pas` refuses to, and says why:

> *No ASCII flag is stamped. `PXX_FLAG_ASCII` means "no byte >= $80", which for
> UTF-16 is true of any ASCII text and says nothing useful, while
> `PXXStrAsciiCached`'s contract is about BYTE positions equalling CHARACTER
> positions — false here for every string.*

So a folded literal and a runtime-built wide string — **the same kind of
object** — would disagree on a flag, with `ASCII_KNOWN` set so no consumer
rescans to discover the truth. That is a silent divergence between two
producers, in the direction that skips the check.

It is unreachable *today* for a Pascal WideString, because Pascal's indexing
lowers off the element type and never consults the flag; only NilPy's
character-position machinery reads it. **That is not a reason to ship it.** It
is the exact shape of the `UFldStrElemTk := Ord(tyChar)` comment that 7b proved
wrong — "tyChar is the only thing reachable today" was true when written and
false the moment a reader existed.

## What it needs

1. A wide-aware intern path — a separate entry point, **not** a parameter:
   `InternStr` has ~100 call sites.
2. `MSTR_KIND_WIDESTR` in `defs.inc`, mirroring `builtinheap.pas`'s
   `PXX_KIND_WIDESTR = 5`. (`defs.inc` documents that its copies of these
   constants are pinned to the runtime's by `test_static_string_literals`
   asserting behaviour rather than values — extend that test.)
3. The 2-byte NUL terminator. `InternStr` writes one explicit NUL then pads to
   8; a wide length is always even, so `len+1` is never 8-aligned and at least
   one pad byte always follows. **True, but currently by accident** — state it,
   the way that function already states its alignment property rather than
   inheriting it.
4. `IRStrWidthConv` grows a literal arm; the runtime path stays for the
   variable case, so this is a constant-fold on top of a correct mechanism and
   not a second mechanism.

## Watch out

`InternStr` dedupes by byte value. A wide `'ab'` is `61 00 62 00`; a *narrow*
literal containing those bytes needs `#0` in the source, which is exotic but
legal — and the two would then share one entry and one meta word, whichever
producer got there first. Either key the table on width as well as bytes, or
prove the collision unreachable and say so.

## Gate

`make test` + self-host byte-identical, `test_widestring_lowering` and
`test_widestring_surrogate_pair` unchanged, `test_static_string_literals`
extended to the wide block, and a loop benchmark showing the allocation gone.

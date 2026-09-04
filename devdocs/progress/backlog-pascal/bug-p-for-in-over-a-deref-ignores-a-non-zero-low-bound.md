---
slug: bug-p-for-in-over-a-deref-ignores-a-non-zero-low-bound
title: "for-in's synthesised AN_INDEX does not subtract a low bound, so `p^` over `array[1..4]` would read shifted garbage"
track: P
prio: 40
type: bug
status: backlog
found: 2026-09-04
found-by: frankA
owner: ""
blocked-by: []
summary: "BuildForInArrayLoop builds a bare AN_INDEX over the container node and relies on lowering to subtract the array's low bound. That works for the AN_IDENT container it was written for and NOT for a pointer deref: the subtraction keys on tags the lvalue walk stamps on a parser-built `p^[i]`, and the synthesised node carries none. Measured with the bound admitted: array[1..4] holding 11 22 33 44 iterated as `22 33 44 4310536`. Currently INERT — the p^ for-in arm refuses a non-zero bound rather than shipping the shift, and the Makefile asserts that refusal — so this ticket is the price of lifting that restriction, not a live defect."
---

# for-in's synthesised index does not carry the deref's low bound

Found while fixing
[[bug-p-for-in-over-a-dereferenced-pointer-to-array-is-refused]], by testing the
low-bound case rather than assuming the comment.

## The comment that is true of one container and false of another

`BuildForInArrayLoop` says:

> *iterate the array's OWN index range: `for i in r` over array[1..3] /
> array[5..7] used a hardwired 0..count-1 and read SHIFTED garbage, silently.
> **AN_INDEX subtracts the low bound itself**, so `__i` in [lo..hi] is the
> correct domain.*

That is correct for the AN_IDENT container it was written for — `for x in a1`
over `array[1..4]` prints `11 22 33 44` today. It is **not** correct for a
deref. The builder synthesises a bare `AN_INDEX` whose left is the container
node and whose right is the loop counter, and the low-bound subtraction for a
pointee keys on tags (`ASTSOffset`/`ASTSLen`, the deref-chain depth and base)
that the lvalue walk stamps on a parser-built `p^[i]` and that this node has
none of.

## Measured — with the restriction temporarily lifted

`p: ^array[1..4] of Integer` holding `11 22 33 44`, and `^array[5..7]` holding
`55 66 77`:

| | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `for x in a1` (direct, lo=1) | `11 22 33 44` | `11 22 33 44` |
| `for x in p1^` (deref, lo=1) | **`22 33 44 4310536`** | `11 22 33 44` |
| `for x in a5` (direct, lo=5) | `55 66 77` | `55 66 77` |
| `for x in p5^` (deref, lo=5) | **`0 0 4`** | `55 66 77` |

The loop domain is right (`lo..hi`); the subtraction never happens, so the
offsets run `lo..hi` instead of `0..hi-lo` — one element off the front and one
past the end.

**The discriminator that says it is the synthesised node and not the index
path:** `p1^[1]` written out by hand answers `11` correctly, on this binary AND
on `pinned`. Same pointer, same array, same low bound.

## Status: inert, deliberately

`d9604ea59` gates the `p^` for-in arm on `lowBound = 0`, so a non-zero bound
keeps the loud refusal it already had — not a regression, and no program can
reach the shift. The Makefile asserts that refusal, so **lifting the restriction
without fixing this turns a green test red rather than shipping silent garbage.**
That is the whole reason this is filed as a separate ticket instead of a comment.

Prio 40 rather than lower because the observable, once reachable, is a silent
wrong value in a loop — but nothing reaches it today.

## The two candidate fixes

1. **Stamp the tags.** Have the builder ask `DerefPtrArrayInfo` for the low
   bound and emit `__i - lo` as the subscript, keeping the domain `lo..hi`.
   Local, and leaves the tag asymmetry in place for the next caller.
2. **Make the subtraction node-keyed rather than tag-keyed**, so any AN_INDEX
   over a deref answers the same as a parser-built one. That is the
   `normalise-dont-special-case.md` answer and it is Track A ground (IR
   lowering / the shared index path), so it wants A's agreement before starting.

Prefer (2) if a sweep shows other synthesised AN_INDEX sites with the same
asymmetry — that sweep has not been done and is the first step either way.

## Gate

The four-row table above against fpc 3.2.2, with the restriction lifted, plus
the existing `test_forin_deref_ptr_array.pas` staying green (lo=0 must not
regress) and the Makefile's low-bound refusal row updated rather than deleted.

---
slug: bug-p-for-in-over-a-deref-ignores-a-non-zero-low-bound
title: "for-in's synthesised AN_INDEX does not subtract a low bound, so `p^` over `array[1..4]` would read shifted garbage"
track: P
prio: 40
type: bug
status: done
found: 2026-09-04
found-by: frankA
owner: ""
blocked-by: []
summary: "BuildForInArrayLoop builds a bare AN_INDEX over the container node and relies on lowering to subtract the array's low bound. That works for the AN_IDENT container it was written for and NOT for a pointer deref, because the low bound is answered by TWO mechanisms and a deref uses the other one: the PARSER folds it into the subscript for `p^[i]` (measured `AN_INDEX(AN_DEREF, 1 - 1)`), while for `a[i]` IR lowering subtracts Syms[].ConstVal, and ir.inc's lo ladder correctly has no deref arm. The synthesised node went through neither: array[1..4] holding 11 22 33 44 iterated as `22 33 44 4310536`. FIXED 2026-09-04 by emitting `__i - lo` for a deref container, matching the parser for that shape; the underlying two-mechanism design flaw is Track A's and is filed as bug-a-an-array-low-bound-is-answered-by-two-mechanisms-and-a-deref-uses-the-other."
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

---

## 2026-09-04 (frankA) — FIXED, and the summary above was wrong by the time you read it

**The `Currently INERT` clause in the summary is retired.** It was true when
filed — the arm refused a non-zero bound and the Makefile asserted the
refusal — and this note is what makes it false. The summary is rewritten in the
same commit.

### The mechanism, which is not what the summary guessed

The summary says the subtraction *"keys on tags the lvalue walk stamps on a
parser-built `p^[i]`"*. That was a guess and it is wrong. Measured with
`PXXDBG=a.ast`, one program, `array[1..4]`:

| source | AST | who subtracted the bound |
| --- | --- | --- |
| `x := a1[1]` | `AN_INDEX(AN_IDENT, 1)` | IR lowering, from `Syms[].ConstVal` |
| `x := p1^[1]` | `AN_INDEX(AN_DEREF, 1 - 1)` | **the parser**, folded into the subscript |

No tags. **Two different mechanisms, chosen by the container's spelling.**
`ir.inc`'s `lo` ladder (~2774) has an `AN_IDENT` arm and an `AN_FIELD` arm and
**no `AN_DEREF` arm** — and that is correct, because for a deref the parser has
already paid. `BuildForInArrayLoop` synthesises its `AN_INDEX` without going
through either, so it got neither subtraction.

### The fix, and why it is the smaller of the two available ones

`BuildForInArrayLoop` now emits `__i - lo` when the container is a deref,
matching what the parser already does for that exact shape. **One answer per
shape rather than a third answer** — but it is still teaching a third site a
spelling-keyed rule, which is the wrong shape of repair, and it is commented as
such at the site. The right repair is to make the bound node-keyed the way
`FrozenStrElemCapOf` (eight lines above that ladder) already made the
frozen-string capacity node-keyed across the identical three shapes. That is
Track A ground and it is now genuinely filed as
[[bug-a-an-array-low-bound-is-answered-by-two-mechanisms-and-a-deref-uses-the-other]].

### Measured, against fpc 3.2.2, every row generated from FPC's own output

| array type | pxx | fpc |
| --- | --- | --- |
| `array[1..4]` | `11 22 33 44` | identical |
| `array[5..7]` | `55 66 77` | identical |
| `array[-2..2]` | `-200 -100 0 100 200` | identical |
| `array[0..3]` (unregressed) | `0 10 20 30` | identical |

**I nearly shipped the shift.** The first version of this fix printed
`22 33 44 4310536` for `array[1..4]` — the exact garbage in the summary — and
the only reason it was caught is that the test varies the low bound instead of
trusting `BuildForInArrayLoop`'s comment about it.

**The assertion shape matters and is deliberate:** the rows compare the DEREF
spelling against the DIRECT spelling of the same array, never against a
literal, so a change shifting both identically cannot pass. The `aliased=139`
row is still there and still load-bearing — it writes through the pointer
before iterating, so a materialised private copy fails it. (Materialising is
correct for a call result and wrong here; see the sibling ticket.)

### Positive control

`stable_linux_amd64/default/pinned` on the same source:
`pascal26:48: error: for-in: not a generator, enum type, or iterable variable`.
The test fails on the pre-change binary, so it is measuring the fix.

Test: `test/test_forin_deref_ptr_array.pas` (+`.expected`, which IS fpc 3.2.2's
output), wired; the Makefile's inline `forinlo` row is flipped from asserting
the refusal to asserting `11223344`, and the pinned compiler rejects that row.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit ca1e6effb.

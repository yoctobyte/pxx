---
slug: feature-d-a-representation-contract-because-there-is-no-spec-to-appeal-to
title: "Document the representation contract — sizes, layout, and what a file can hold — because there is no formal spec to appeal to"
track: D
prio: 60
type: feature
status: backlog
created: 2026-09-02
found-by: owner (2026-09-02)
owner: ""
blocked-by:
  - feature-p-implement-the-real-tyshortstring-byte-prefix-layout
summary: "OWNER'S FRAMING, and it is the reason this is not ordinary doc work: *'there is no formal OOP specification. delphi just does as they see fit, FPC did the same, trying to emulate delphi.. and we take (most of) their design decisions as FPC is de-facto standard in 2026.'* So for representation questions THERE IS NOTHING TO APPEAL TO, and our documentation IS the specification for pxx. NOT starting from zero: `docs/language/types.md` (393 lines) already documents sets as a 32-byte bitset and `Real` per target — and the `Real` section is the MODEL to copy, because it states size, STRIDE and the file/wire consequence together. The gap is that the contract is scattered and never separates GUARANTEED from incidental. What to add: fixed strings (`cap+8` today, `cap+1` for `string[N<=255]` once the byte-prefix work lands — hence the blocker), plain `string` as a managed handle, record padding and packing (measured to match FPC exactly), and what `file of T` can blit versus must marshal. Plus a named list of deliberate divergences from FPC with the reason, since `known-incompat/` is internal and a user never sees it."
---

# A representation contract

## Why this is not ordinary doc work

Owner, 2026-09-02: *"there is no formal OOP specification. delphi just does as
they see fit, FPC did the same, trying to emulate delphi .. and we take (most
of) their design decisions as FPC is de-facto standard in 2026. C is more
defined — and even then we found plenty discrepancies."*

For representation there is **no document to be right or wrong against**. That
makes ours the specification, and it changes what the page owes: not "here is
how it works today" but **"here is what you may rely on."**

## Start from what is already right

`docs/language/types.md` is 393 lines and already correct on several points —
sets as a 32-byte bitset supporting up to 256 elements, `string` as managed and
reference-counted. **Copy the `Real` section's shape**, which is the best thing
in the file:

> *"`SizeOf(Real)` is 4, and an `array of Real` strides by 4. A `Real` written
> to a file or sent over a wire is 4 bytes."*

Size, **stride**, and the file/wire consequence in three lines. Stride is the
part that is usually missing and the part that actually bites.

## What to add

- **Fixed strings.** `string[N]` is `N+8` today (8-byte length word + chars).
  Once [[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]] lands,
  `N<=255` becomes `N+1` and `N>255` stays `N+8` — **and pxx accepts `N>255`
  where FPC rejects it outright**, which is a capability worth advertising.
- **Plain `string`** is a managed handle, `SizeOf` 8. FPC's default `string` is
  a 256-byte shortstring. Say so plainly; users WILL hit this.
- **Sets.** 32 bytes, bitpacked, one bit per ordinal 0..255, and the width does
  **not** follow the declared bounds — that is chosen, not pending. Our mask is
  a byte-exact zero-extension of FPC's, so the first 4 bytes ARE FPC's small set.
- **Records.** Padding and packing measured to match FPC exactly (`Byte+LongInt`
  is 8 with the field at offset 4; `packed` is 5 at offset 1).
- **`file of T`.** What blits and what must be converted, and the trap:
  `SizeOf(s)` can exceed the on-disk width, so `BlockWrite(f, s, SizeOf(s))`
  desynchronises the file.

## Divergences need a user-facing home

`known-incompat/` is an internal folder a user never sees. Where we deliberately
differ from FPC — `SizeOf(set)`, `SizeOf(string[N])`, plain `string` — the doc
must say **what we do, that it is deliberate, and why**, not leave a reader to
discover it against FPC. Sources: `known-incompat/README.md` and
[[decide-a-what-a-set-costs-bits-bytes-bounds-and-what-file-of-t-writes-to-disk]].

## Gate

Track D's own: prose only, never `compiler/**` or `lib/**`, and **every snippet
compiles against `$(PXX_STABLE)`**. Sizes quoted here are claims — measure each
one against the pinned compiler and say which pin, rather than copying the
numbers out of this ticket.

**Blocked on the shortstring work for the string half only.** The set, record
and `file of T` sections are writable now and do not change.

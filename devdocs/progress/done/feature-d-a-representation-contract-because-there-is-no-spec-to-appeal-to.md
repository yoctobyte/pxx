---
slug: feature-d-a-representation-contract-because-there-is-no-spec-to-appeal-to
title: "Document the representation contract — sizes, layout, and what a file can hold — because there is no formal spec to appeal to"
track: D
prio: 60
type: feature
status: done
created: 2026-09-02
found-by: owner (2026-09-02)
owner: frankD
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

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit c3895a009.

## Delivered 2026-09-05 — `docs/reference/representation.md`

226 lines, wired into the reference index and cross-linked from
`docs/language/types.md` (top, Strings, Sets). Guaranteed-vs-incidental is
separated throughout, as the ticket asked for.

**Every number measured, not derived.** Probes run natively on x86-64 and under
qemu on i386, arm32, riscv32 and aarch64, plus an FPC 3.2.2 oracle for each
divergence row.

**The target sweep changed the content, which is why it was worth doing.**
`string[300]` is **308** on the 32-bit targets and **312** on the 64-bit ones,
so the rule for `N > 255` is `N+8` rounded to the target's *pointer alignment*
— and such a string is not portable across word sizes in a file or a record.
Measured on x86-64 alone it is 312 and reads like a constant. That row is now a
warning in the page rather than a table entry. `string[N <= 255]` is `N+1` on
every target and byte-identical to FPC, so that guarantee is real.

**Two of the ticket's own claims did not survive measurement:**

- The `file of T` trap it names — *"`SizeOf(s)` can exceed the on-disk width, so
  `BlockWrite(f, s, SizeOf(s))` desynchronises the file"* — is no longer true.
  Post-byte-prefix, `BlockWrite` writes exactly `SizeOf`: verified at 11 bytes
  for a `string[10]` and 312 for a `string[300]`. The real current trap is that
  **`file of string[N]` does not compile at all**, refused with a width that
  contradicts `SizeOf` — filed as
  [[bug-p-file-of-string-n-refuses-with-a-width-sizeof-contradicts]] and
  documented in the page as a current limitation.
- The set claim — *"the first 4 bytes ARE FPC's small set"* — is right but
  mode-dependent, and the ticket did not say so. FPC's `set of 0..7` is 4 bytes
  under `{$mode objfpc}` and **1** byte under `{$mode delphi}`. Confirmed
  byte-exact in both directions: `[1, 3, 7]` is `138` in byte 0 under all three,
  with the rest zero. The page states the mode.

Records needed no correction: 8 with the field at offset 4, `packed` 5 at offset
1, identical on all five runnable targets and to FPC.

**The page is gated, not just asserted.** It carries a complete self-check
program that `docsnip.py` compiles against the pin — the run went 39→40 complete
programs and 30→31 compiled, so the snippet was demonstrably seen rather than
skipped. It compiles under the pin and prints the same rows there as at HEAD.

Verified with PXX at `ce19e5482`, binary `9bcfd2b4da30`, and the pin
`stable_linux_amd64/default/pinned`.


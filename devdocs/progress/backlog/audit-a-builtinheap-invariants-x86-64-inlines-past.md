---
track: A
type: audit
prio: 60
status: open
found: 2026-08-29
found-by: claude-N
---

# A helper's comment is a claim about every caller, written where one caller cannot see it

Three times in one day, a `compiler/builtin/builtinheap.pas` helper documented an
invariant that x86-64 does not uphold — because x86-64 does not **call** that
helper, it open-codes past it. Each was found separately, and twice the finder
named it "the same asymmetry" without the general rule being written down
anywhere a later session would read.

**The rule, so it stops being rediscovered:**

> When a `builtinheap.pas` helper's comment asserts an invariant, check whether
> x86-64 calls it.

Three of three so far did not.

## Why this shape is durable, and not really about x86-64

A comment asserting an invariant is a claim about **every caller**, and it is
written in the one place where only *some* of them can see it.

`PXXStrUnique` says of itself:

> this is the single choke point for byte mutation, which is what makes the
> cache sound.

And it **is** that — on i386, arm32, aarch64, riscv32 and xtensa, all of which
`FindProc('PXXStrUnique')`. The sentence is true on five targets and false on
the sixth. The sixth is the one everybody develops and tests on. So the target
where the invariant fails is the target where nobody reads the sentence that
asserts it, which is why three instances took three separate discoveries rather
than one.

The generalisation is not "x86-64 is untrustworthy". It is: **a documented
invariant is only as strong as the narrowest gate that enforces it, and a
comment enforces nothing.** Where the flagship target open-codes a helper for
speed, the helper's comment becomes documentation of a path that target never
takes.

## The three instances

| # | helper / invariant asserted | how x86-64 gets past it | found |
| --- | --- | --- | --- |
| 1 | `PXXStrSetLen` — a NilPy `""` publishes a REAL zero-length block | inlines the symbol-target `SetLength`; the two `{$ifdef PXX_NILPY_STR}` arms in the helper are never reached. Called "the THIRD collapse site and the only one that is not in builtinheap" at the fix site | `8be3c6d06` |
| 2 | `PXXStrSetLen` — *"it always allocates a fresh block and `PXXHdrInit` zeroes its meta"*, which `PXXStrUnique`'s comment explicitly leans on | same inline resize, but the **in-place** arm: reuses the block and kept its stale ASCII verdict | `df19c72a7` (frankA) |
| 3 | `PXXStrUnique` — *"the single choke point for byte mutation, which is what makes the cache sound"* | indexed writes reach `AnsiStrUniqueAddr`, a hand-emitted blob in `ir_codegen.inc`; never touches the meta word, on either the in-place or the clone arm | `b71690c40` |

Instances 2 and 3 are the same defect (a stale cached ASCII answer) reached
through two different sites, and #2's write-up said the fix covered "everyone"
— true of the `SetLength` route, and #3 needs no `SetLength` at all.

## The census — what this ticket asks for

Enumerate every helper in `builtinheap.pas` whose comment asserts an invariant,
and for each determine whether x86-64 reaches it or open-codes past it. Pure
measurement, read-only, so it collides with nobody's live checkout.

Turning "three of three" into a bounded number is the whole point: if the answer
is "three, and they are now all fixed", that closes a worry cheaply. If it is
larger, each entry is a latent wrong-answer bug on the flagship target.

**Results are appended below.**

## Follow-up carried here rather than dropped

`df19c72a7` spells the ASCII-cache mask as four literal `EmitB` bytes;
`b71690c40` added a named `PXX_ASCII_CACHE_BITS` in `defs.inc` for the same mask
at the sibling site. Folding the first onto the constant leaves one spelling
instead of two — the ordinary normalise-don't-special-case call. It was not done
at the time because those lines had landed minutes earlier in a file another
agent was live in. **Free for whoever holds A next while already in that file;
not worth its own dispatch.**

## Gate

Read-only census: none. Any fix it produces takes A's gate — `make
compiler/pascal26` (self-host byte-identical) plus the repro for that entry.

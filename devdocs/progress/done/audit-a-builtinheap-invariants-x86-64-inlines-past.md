---
track: A
type: audit
prio: 60
status: done
found: 2026-08-29
found-by: claude-N
owner: frankD
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

---

## CENSUS 2026-08-29 (claude-N) — read-only, and it corrects the rule above

Measured on `compiler/builtin/builtinheap.pas` at `5df38d84e`, by stripping
Pascal comments from all six backends plus the shared `ir.inc`, then matching
`FindProc('<name>')` against every routine that has an implementation body.

| | |
| --- | --- |
| routines defined in `builtinheap.pas` | 135 |
| reached by x86-64 (directly or via `ir.inc`, which lowers for every target) | 45 |
| **called by at least one cross backend, never by x86-64** | **30** |
| of those, whose own comment names an x86-64 inline twin | **9** |

The nine documented pairs — one concept, two implementations:

| concept | portable half | x86-64 half |
| --- | --- | --- |
| COW / writable handle | `PXXStrUnique` | `AnsiStrUniqueAddr` blob |
| `SetLength(ansistring, n)` | `PXXStrSetLen` | inline symbol-target resize |
| string equality | `PXXStrEq` | inline compare |
| ordered string compare | `PXXStrCmp3` | inline compare |
| variant binary op | `PXXVarBinOp` | `EmitVarBinOp` |
| variant clear | `PXXVarClear` | `EmitVariantClear` |
| variant write | `PXXWriteVariant` | `EmitWriteVariant` |
| console read / readln | `PXXReadLine` + 5 | `EmitReadLine` / `EmitReadVarParse` |
| float → text | `PXXWriteFloat{Nat,Fixed,Sci}` | `EmitWriteFloat*` |

### The rule above is HALF the rule

I filed this ticket saying "check whether x86-64 calls it", from three instances
that all broke on the x86-64 side. The census says the defects split evenly, and
the other three are already in the tree's own comments:

- **`PXXStrCmp3`** — *"the four cross backends had NO ordered-string arm at all
  ... `a < b` fell through to the ordinary integer compare and compared the two
  heap HANDLES ... `'zzz' < 'aaa'` reported by allocation order"*, on i386,
  arm32, aarch64 and riscv32. x86-64 was the correct one.
- **`PXXVarBinOp`** — *"x86-64's inline `EmitVarBinOp` has had them for as long
  as NilPy has needed machine-word masking; this function — the dispatch every
  OTHER target uses — did not"*. `v(12) and v(10)` answered -524095488 on i386,
  4358436 on aarch64, 1082138624 on arm32, where x86-64 and FPC say 8.
- **`PXXWriteVariant`** — reading an Int64 payload through `PWord` (a *machine*
  word) threw away the high half on i386 and arm32, *"while x86-64 and aarch64 —
  where a machine word happens to BE eight bytes — printed both correctly."*

So **3 known defects on the x86-64 side, 3 on the portable side.** The correct
statement is not about x86-64 at all:

> **Where a `builtinheap.pas` helper has an inline twin, that is one concept
> with two implementations, and either one can be the half that is wrong.
> Fixing a defect in one half is not evidence about the other — go look.**

That is `devdocs/dev/normalise-dont-special-case.md`'s "if you fix a bug on one
arm of a double case, grep for the sibling" applied to a split the tracks
already know about. It is also why every one of these six took its own
discovery: each was found from the side that was broken, and finding it there
tells you nothing about the other side, so nobody looked.

x86-64 dominates the *discovery* rate rather than the defect rate — it is the
target everyone runs, so its half is exercised constantly and its bugs surface
as visible reds, while the portable half's bugs sit until someone runs a cross
target. Both halves broke three times; only one kind gets found the same day.

### Status of the nine

- **Fixed and pinned:** COW (`b71690c40`), in-place resize (`df19c72a7`),
  `SetLength(s,0)` collapse (`8be3c6d06`) — the x86-64 side of three pairs.
- **Fixed on the portable side:** `PXXStrCmp3`, `PXXVarBinOp`,
  `PXXWriteVariant` — each has a `bug-a-*` slug in its comment.
- **Known deliberate divergence, already ticketed:** `PXXWriteVariant` spells an
  EMPTY slot `None` and an OBJECT slot `<object>` where x86-64 does not — held
  open on purpose pending
  [[bug-a-a-null-variant-renders-as-none-in-pascal]].
- **Unaudited, no known defect either side:** `PXXStrEq`, `PXXVarClear`, the
  console-read family, and the float→text family. The float pair is **Track F**
  by charter (formatting of a real is F), so it is low prio by definition and
  should not be pulled into this sweep.

### The audit worth running next, and it is NOT this one

Not "does x86-64 call the helper" — that question is now answered, 30 and 9. The
next one is **differential**: for each unaudited pair, run the same program
through x86-64 and one cross target and diff. `tools/fuzz.sh` already does
cross-target differential testing and is Track T's, so this is a testing item,
not a reading item. The four unaudited pairs are a small, named target list for
it rather than a blind sweep — and three of the six known defects were exactly
what such a diff would have caught on the day it was introduced.

### One methodology note, because it is the same shape again

The first run of this census reported x86-64 as *calling* `PXXStrUnique`. It does
not. The matcher was scanning raw source, and `ir_codegen.inc` now contains my
own comment from `b71690c40` — which quotes the literal string
``FindProc('PXXStrUnique')`` while explaining that x86-64 never calls it. **The
prose describing the absence produced the appearance of presence.** Caught only
because the answer contradicted a grep from twenty minutes earlier. The numbers
above are from the corrected run with comments stripped; treat any future
`FindProc` census the same way.

---

## AUDIT COMPLETE 2026-08-30 (frankD) — the three unaudited pairs, tested rather than read

Read-only. The census left four pairs unaudited and named the right next step as
**differential rather than reading**. Three were testable (float→text is Track F
by charter and stays out), so they were tested: the same program compiled for
x86-64 (inline twin) and riscv32 (portable helper), run, and diffed.

### Result: 31 cases, zero divergence

| pair | cases | covering | verdict |
| --- | --- | --- | --- |
| `PXXStrEq` / inline compare | 13 | equal content in different blocks, literal compare, prefix both ways, `''`=`''`, `''` vs non-empty, `<>`, `Char`, frozen `string[8]` against an ansistring **in both operand orders** | **identical** |
| `PXXVarClear` + `PXXVarRetain` + `PXXVarReleasePayload` / `EmitVariantClear` and the aarch64 twin | 10 | `v := v` self-assign, retag over a string payload, variant outliving the ansistring it copied, variant-to-variant store in a loop, int/bool/double round-trip | **identical** |
| console read family / `EmitReadLine`, `EmitReadVarParse` | 8 | string line, `Char`, two ints on one line with leading blanks and a negative, `Int64` past 2^53, bare `ReadLn` discard, trailing-space preservation, `Eof` both false and true | **identical** |

The variant row is the one worth noting: `v := v` is the shape that broke as
`bug-a-a-variant-assigned-to-itself-becomes-empty`, and it is now correct on both
halves.

### The scope limit, stated because it is exactly where tonight's real bug was

**riscv32 was the cross representative. xtensa was not tested here**, because the
pinned compiler resolves builtin units from its own frozen
`stable_linux_amd64/default/builtin/`, which predates frankS's `HeapMmap`
`CPU_XTENSA` arm — so hosted xtensa cannot allocate under the toolchain a Track D
agent is allowed to use.

That matters more than a usual caveat: **the one genuine divergence found in this
seam tonight was xtensa-only**
([[bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle]]), and it
was invisible to exactly this kind of x86-64/riscv32 diff. So read the table as
*"the portable helper and the x86-64 inline agree"* — which is what the census
asked — and **not** as "all five cross backends agree". Re-running these three
probes against xtensa once a pin carries the heap arm is cheap and is the
remaining work; the probes are six-line programs and are reproduced above by
description.

### One finding, and it is the seam's own root cause

[[bug-a-the-comment-that-caused-three-bugs-survived-all-three-fixes]] —
`builtinheap.pas:2625-2631`, the `PXXStrUnique` comment, is the sentence that
produced instances 1, 2 and 3 of this ticket. All three were fixed on 2026-08-29.
`git blame` still dates all seven lines to `8a263f504`, **2026-08-14**. Three
agents found three bugs caused by believing it, fixed all three in one day, and
none edited it. Its sibling copy in the *consumer* is
[[bug-a-the-ascii-cache-consumer-still-says-byte-mutation-has-one-place]] — fix
both in one commit or the next reader finds whichever was left.

### Census correction carried from the sibling audit

The `FindProc('<name>')` matcher misses **name-taking wrappers** (`XtensaHelperProc`,
`EmitXtensaHelperCall`, `EmitVarHelperCall*`, `EmitStrRefCall*`). Corrected:
**46 reached by x86-64, 33 cross-only** — not 45/30. `PXXVarRetain`,
`PXXVarReleasePayload`, `__pxx_divsi3` and `__pxx_modsi3` were invisible;
`PXXRecordRetainIntf` moves out of cross-only. There is a **tenth documented
pair**: `EmitVariantClearA64Ex` (`ir_codegen_aarch64.inc:549`) is aarch64's
hand-emitted twin of `PXXVarReleasePayload`, and its comment names the twin
correctly.

The methodology note at the foot of the census should carry both halves now: the
first run showed *prose describing an absence producing the appearance of
presence*; this one is the inverse, **an indirection producing the appearance of
absence**.

### Verdict on the ticket's own question

> *"if the answer is 'three, and they are now all fixed', that closes a worry
> cheaply. If it is larger, each entry is a latent wrong-answer bug."*

**Ten pairs. Six known defects, all fixed. Three pairs newly tested and clean on
the x86-64/riscv32 axis. One pair (float→text) deliberately out of scope as F.
One new finding, which is not a code defect but the comment that caused three of
the six.** The worry closes — but not for the reason the ticket expected: the
pairs are in good shape and **the sentence that describes them is not**.

## Log
- 2026-08-30 — resolved, commit 619264586.

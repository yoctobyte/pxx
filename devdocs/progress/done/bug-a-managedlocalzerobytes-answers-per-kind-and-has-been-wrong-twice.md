---
track: A
prio: 55
type: bug
summary: "ManagedLocalZeroBytes is a chain of per-kind arms, each of which has to remember to ask IsArray. Two arms have already shipped without it — interfaces (2026) and Variants (2026-08-27, a5 memory-corruption fix). Two more arms explicitly say `not IsArray` and nothing says whether that is a decision or the same omission a third time."
status: done
owner: frankA
---

# `ManagedLocalZeroBytes` answers per kind, and has been wrong twice the same way

`compiler/pasparser_expr.inc:35` is the single table behind "how many bytes
must this managed local start zeroed". Getting it wrong does not produce a
missing zero — it produces a **use-after-free**, because every managed kind's
first store RELEASES the slot's previous contents, and an unzeroed slot's
previous contents are stack garbage that sometimes looks like a live handle.

The table's shape is a chain of `else if` arms, one per kind, and each arm is
independently responsible for remembering that the local might be an ARRAY:

| arm | asks IsArray? |
| --- | --- |
| element-is-dyn-array | yes (that IS the arm) |
| dyn-array handle | yes |
| `tyAnsiString` | **yes** — `ArrLen * PTR_SIZE` |
| `tyVariant` | **added 2026-08-27**; shipped without it |
| `tyRecord` | yes, as a separate arm |
| COM interface | **added earlier**; shipped without it |
| static array of COM interfaces | yes, as a separate arm |
| NilPy `tyClass` | says `not IsArray` |
| promo int | says `not IsArray` |

Two of those arms have already been fixed *after* shipping, each found the
same way — a bug that appears and disappears when an unrelated routine changes
the frame in front of it:

- `bug-a-a-local-array-of-interfaces-is-not-zero-initialised` — presented as
  `uses sysutils` causing a segfault. The unit was irrelevant; it merely
  dirtied the stack.
- `regression-test-nilpy-test-nilpy-star-operand-in-a-variant` — presented as
  a NilPy test going red with no NilPy change behind it. The variant arm
  zeroed 16 bytes for an array of any length, so pylib's own
  `av: array[0..3] of Variant` decremented an unrelated heap record's field
  by one and a callable-value dispatch refused a legal two-argument call.

## The two open questions

**1. Are the remaining `not IsArray` guards decisions or omissions?** Neither
carries a note saying which. The NilPy `tyClass` arm is guarded by
`NilPyUserCode`, and NilPy user code has no array locals — so it may be
unreachable rather than wrong. The promo-int arm has the same smell. I
declined to widen either while fixing the variant one, because I could not
construct a reachable case and a speculative widening would be a guess wearing
a fix's clothes. That decision needs to be *measured* and then either recorded
as deliberate (with the reason, in the arm) or fixed.

**2. Should the array question be asked ONCE instead of nine times?** The
whole table is "bytes per element x element count", and every arm that gets it
right computes exactly that. A structure that asks `IsArray` at the top and
multiplies the per-element answer would make the omission unstateable rather
than merely unlikely — which is the argument
`devdocs/dev/normalise-dont-special-case.md` makes, and this table is now its
best worked example: *the second path is the one that stays broken*, and here
there are nine.

Care needed: the arms are not all "size x count". The dyn-array-element arm
zeros POINTERS inside a fixed array, and the record arms use `RecSize` of an
element record. A restructure has to keep those distinctions, so this is a
real design task, not a mechanical rewrite. Weigh it against leaving the chain
and adding a test per kind instead — `root-cause-over-microfix` says measure
tickets-closed-per-change, and the answer here may honestly be the chain plus
coverage.

## What would make either answer cheap

There is no test that enumerates the kinds. `test_interface_local_array_zero_init.pas`
and `test_variant_local_array_zero_init.pas` each cover one arm, both by
dirtying their own stack so the failure is deterministic. A single table-driven
Pascal test — one local of every managed kind, scalar and array, all asserted
to start zeroed — would answer question 1 by running it and would guard any
restructure done for question 2.

---

# Both questions answered, 2026-08-30 — and one of the two guards was a bug

## Q1: decision or omission? — **one of each**, measured not argued

The ticket asked whether the two remaining `not IsArray` guards were deliberate.
They were treated as one question; they are two, with opposite answers.

**The promo-int guard was an OMISSION, and reachable.** `promoint`,
`promoint32` and `promoint64` are **spellable Pascal type names**
(`pasparser_decl.inc:543`), so `a: array[0..3] of promoint64` is an ordinary
Pascal local. Measured with a new `PXXDBG=a.mlzero` channel (below):

```
sym=zzscalar tk=28 isarray=FALSE          -> 16     { correct }
sym=zzarr    tk=28 ARRAY len=4 promoint   -> 0      { the hole — want 64 }
sym=zzstr    tk=23 isarray=TRUE arrlen=4  -> 32     { control: AnsiString asks }
```

Not one element's worth, as the Variant bug had — **nothing at all**. And it is
worse than a missing zero, because `EmitManagedLocalCleanup`'s promo arm
(`symtab.inc:10792`) has the *same* missing `IsArray` and still calls
`PXXPromoClear` on the slot address at scope exit. That routine releases the
payload as a managed string whenever the tag reads `PROMO_TAG_HEAP`, and its own
header says it "cannot be used on uninitialised memory". So element 0 was
cleared **from stack garbage**: a frame carrying `{1, <pointer-shaped bytes>}`
freed a block the slot never owned. `test_promoint_local_array_zero_init`
**segfaults** on the pre-fix compiler.

Third arm, same shape, same cause as interfaces and Variants.

**The NilPy `tyClass` guard is a genuine DECISION**, and now recorded as one.
`NilPyUserCode` is true only for NilPy source, and NilPy has no static-array
syntax — a NilPy list is a *dynamic* array (`ArrLen = -1`), which the
dyn-array-handle arm claims long before the class arm is reached. Measured on a
NilPy compile carrying classes, lists and int arithmetic: **19 dyn-array locals,
all `arrlen=-1 -> 8`; zero static arrays of `tyClass` under `NilPyUserCode`; and
every static array that answered 0 was of an unmanaged kind** (`tyUInt8`,
`tyInt64`). The guard is unreachable rather than wrong. It is dropped anyway by
the restructure below, which costs nothing and removes the question.

## Q2: restructure or chain-plus-coverage? — **restructure, and it verified clean**

Three arms shipping the same omission is the argument. The count is now
computed **once** and applied at the bottom, so every per-element arm supplies
only a per-element size and **a new arm is correct for arrays by construction
rather than by remembering**.

The ticket's caveat was right and is preserved: the arms are not uniformly
"size x count".

- The two **handle-level** shapes (fixed array of dyn handles; a dyn-array
  handle) answer in full and keep `elemCount = 1` — those slots hold a pointer,
  not a payload.
- The **record** arms keep their own `IsArray` test, and must: they differ in
  *which rec id they read* (`RecName` vs `ElemRecName`), not merely in count —
  and each falls **through** to the COM arms when `RecordNeedsZeroInit` says no.
  A merged record arm would have swallowed that fall-through and silently
  answered 0 for a COM interface whose record needs no zeroing. That was the one
  real hazard in the restructure and it is why the record arms still branch.

**Verified by equivalence, not by inspection.** The new `a.mlzero` channel
prints the table's answer for every managed local it sees, so the whole
decision set can be diffed:

- NilPy compile carrying classes, lists, string and int work:
  **8,919 decisions, byte-identical before and after the restructure.**
- A/B across `examples/`: **34 byte-identical, 0 changed** — the restructure
  alters no codegen. (None of the 34 declares a promo-int array, which is
  exactly why the bug survived; that shape is covered by the new test, not by
  this sweep.)
- All three zero-init tests green: promoint 6/6, variant 8/8, interface 5/5.

## The instrument, which is the durable part

`PXXDBG=a.mlzero` (`compiler/pasparser_expr.inc`) reports every local the table
looked at, what it decided, and — the line that matters — `MISS` for a local of
a kind the chain *handles* that still came out `zeroBytes = 0`. The ticket
observed that both prior arms were found from the outside, as a use-after-free
three layers from the cause, because a missed zero is invisible on a clean
stack. A fourth omission is now one grep of this channel away instead.

It is also what made the restructure safe: an equivalence oracle over ~9,000
real decisions is a stronger check than reading ten arms.

## Split out, not fixed here

[[bug-a-a-static-array-of-promo-ints-releases-only-element-zero]] — the
**release** half of the same missing `IsArray`. With init fixed, every element
starts `{0,0}`, so clearing element 0 is harmless and what remains is bounded:
elements 1..N leak their heap-tier payload. Safety-critical half closed here,
correctness half filed at prio 45. Its remedy is known — it is
`bug-a-local-static-array-of-string-never-released-at-scope-exit` one type over,
and that fix's `PXXArrayReleaseImmediate` arm already sits *earlier* in the
cleanup chain — but it needs a runtime change in `promocore.pas` and a new
base-kind number, so it is not folded in.

## Log
- 2026-08-30 — resolved, commit f4bc4cc54.

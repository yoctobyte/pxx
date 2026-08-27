---
track: A
prio: 55
type: bug
summary: "ManagedLocalZeroBytes is a chain of per-kind arms, each of which has to remember to ask IsArray. Two arms have already shipped without it — interfaces (2026) and Variants (2026-08-27, a5 memory-corruption fix). Two more arms explicitly say `not IsArray` and nothing says whether that is a decision or the same omission a third time."
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

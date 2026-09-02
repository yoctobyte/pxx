---
track: U
prio: 60
summary: "OPEN DECISION for the owner. The owner parked the 4-byte set at 18:00 on 2026-09-02 (*\"our sets are just always 32 byte\"*) on a COST judgement — the ticket's own words are that the mechanism was designed but the overhead was judged not worth it now. The overhead has since been paid: the owner's own `smallset` design (a hidden second type kind, `tySmallSet`, same `set` keyword in source) is IMPLEMENTED, self-hosts, and matches the FPC 3.2.2 oracle byte-for-byte on x86-64 + i386 + aarch64 + arm32 + riscv32, with `gate.sh quick` GREEN and 50/50 unchanged rows on a 57-test set corpus. It is NOT landed — the park is a live decision and this is a fork of intent, so the work is banked as `devdocs/dev/parked-patches/smallset-4-byte-set-storage-class.patch` (22 files, applies clean at ff62bb870) and the tree is back at 32 bytes. The question is only whether the measurement changes the park; it does not re-litigate the reasoning. If the answer is no, delete the patch and this ticket and keep the rainy-day ticket as the record."
status: backlog
type: decide
created: 2026-09-02
found-by: frankA
owner: ""
---

# The `smallset` mechanism is built and green — does that change the park?

- **Track:** U — decisions
- **Blocks:** nothing. This is a question, not work.
- **Relates:** [[bug-a-a-set-is-32-bytes-whatever-its-bounds-and-the-ir-opcode-says-so]]
  (rainy-day), [[decide-a-what-a-set-costs-bits-bytes-bounds-and-what-file-of-t-writes-to-disk]]

## The fork

The park is explicit and dated: *"let's park it for now. i'd say, for now, our
sets are just always 32 byte. and advise against using records with sets for
file-io or document it."* (owner, 2026-09-02).

**I am not disputing that.** I raise it because the rainy-day ticket states the
park's own premise, and the premise is the part that moved:

> **THE MECHANISM IS ALREADY DESIGNED, and it is cheaper than the estimate this
> was parked on.** … the owner judged the overhead not worth it now.

The overhead is spent. The implementation below was already complete and
measured when the park landed — the two crossed in flight, not in disagreement.
So the decision in front of the owner is narrower than the one that was made:
not *"is narrowing worth building?"* but *"now that it is built and green, is it
worth carrying?"*

**Either answer is cheap from here.** Landing is `git apply`. Declining costs a
`rm` of the patch and this file, and the rainy-day ticket already records the
whole thing correctly.

## What was built

Exactly the owner's design, no variable-width sets: a second type kind
`tySmallSet` (ordinal 32) as the NARROW storage class, 4 bytes, chosen when the
element's high ordinal ≤ 31 — modelled on the codebase's own
`tyPromoInt32`/`tyPromoInt64` precedent. Source spelling is unchanged; `set of
0..7` is still written `set of 0..7`.

- **One predicate, `TypeIsSet()`**, as the decide asked for — never 54 two-armed
  comparisons. A site that forgets the new kind FAILS LOUD ("not a set") instead
  of silently laying out 32 bytes where the reader expects 4. That is how the
  two real bugs below were caught rather than shipped.
- **Set literals stay 32 bytes in `Data[]`.** A blob is read through its
  ADDRESS, and a 4-byte read of its low bytes is the same bits — narrowing the
  constant pool would buy rodata and cost a class of width-mismatch bugs.
- **`SetNarrower(a,b)`**: an op over two set operands uses the narrower class.
  Every wide object tolerates a 4-byte read of its low bytes; a narrow one does
  not tolerate a 32-byte read. Mixing widths is already a type error FPC rejects.
- The wide class emits **byte-identical code** to today's compiler.

## Measured — all at `ff62bb870`, patch applied, `converged after 1 round(s)`, binary `d374f4a8bdd7`

| what | result |
| --- | --- |
| FPC 3.2.2 oracle, `test/test_small_set_width.pas` (18 rows) | **identical**, native |
| same test, i386 / aarch64 / arm32 / riscv32 under qemu | **identical to the FPC oracle on all four** |
| 57-test set corpus, base vs patched, output equality | 50 same, 1 diff, **0 new failures**, 6 both-fail |
| the 1 diff | `test_rtti InstanceSize: 80 → 48` — the intended win, hand-verified (8+8+8+4+4+pad+16), asserted nowhere |
| the 6 both-fail | 4 negative `*_fail` tests + `macronest_fpcmode` + `aoc_ovl_unit_fmt`; **diagnostics byte-identical** in both arms |
| 8 set tests × 4 cross targets, base vs patched | **32/32 SAME**, rc=0 |
| `tools/gate.sh quick` | **GREEN**, and the FPC seed canary **PASS** (ran uncommitted, so it was not the `SKIP` path) |

**Positive controls, because a sweep of SAMEs proves nothing on its own.**
`test_set_subrange` binaries DIFFER on all four cross targets (1486 / 1907 /
2028 / 3213 bytes) — the narrow path fires — while `test_sets` and
`test_const_set` are byte-identical on all four, which is the wide class
demonstrably unchanged. And the new test FAILS against the pre-change compiler
(`sz 32 32 32 32 32 32` / `rec 48 arr 96` against the expected `sz 4 4 4 32 32
32` / `rec 12 arr 12`), so it is a test that can fail.

## Two real bugs the loud-failure design caught, worth reading even if the answer is no

**1. A pointer-sized slot held a 4-byte size.** On x86-64/aarch64/arm32
`ABIParamSlotHoldsValueAddr` is True for sets — the slot holds the value's
ADDRESS — but `ParamValueSize` returned the TYPE's 4 bytes, so an 8-byte pointer
went into a 4-byte slot and `test_set_default_param_b282` segfaulted. Invisible
before because 32 ≥ 8 on every target; the fix is a pointer floor in
`ParamSlotWordSize`, `ParamValueSize` and `AllocParam`'s alignment. **Any future
type narrower than a pointer in an address-passing ABI class hits this**, so it
is worth knowing regardless of this decision.

**2. `lib/rtl/typinfo.pas`'s RTTI width table had no row for the new kind** and
fell through to the 8-byte default, so a published `set of TColor` property read
the four bytes AFTER the field (`test_streaming_enumset` printed
`Colors=8484786405250170885` for `5`) — and `SetOrdProp` uses the same width to
choose its STORE size, so the write direction would have clobbered the
neighbour. A width table keyed by kind is a second copy of the sizing rule and
it goes stale silently.

## What the measurement says about FPC, and this part stands whatever is decided

Chasing the last diverging row produced a first-hand result the rainy-day ticket
does not have, and it corrects an assumption in our own lowering.

**FPC's `Include`/`Exclude` with a variable element is TWO steps, not one:** fold
the element to a BYTE (`and 255` — a set element is a byte ordinal in FPC's
model, 256 elements max), then **skip the write entirely** if that byte index
lies outside *this set's* storage. Measured on the raw bytes of the set object,
2026-09-02, identical at `-O2` and `-O-`:

| | FPC | pxx today |
| --- | --- | --- |
| `set of 0..7`, `Include(s, 20)` | sets bit 20 | sets bit 20 |
| `set of 0..7`, `Include(s, 100)` | **no-op** | sets bit 100 |
| `set of 0..255`, `Include(s, 300)` | sets bit 44 | sets bit 44 |

So the boundary FPC enforces is the **storage width**, not the declared high
bound — `Include(s, 20)` on a `set of 0..7` genuinely does set bit 20 in both
compilers, which is pre-existing shared behaviour and not a defect of either.
Only the out-of-storage case differs, and today it is unreachable in pxx because
every set is 32 bytes: the offending index lands inside the object. **It becomes
reachable the moment a set is 4 bytes**, which is why the patch carries the
guard, emitted only for the narrow class so wide-set codegen stays byte-exact.

**This is not an argument for landing.** It is the reason the patch is not a
naive width change, and it is the piece a future attempt would otherwise have to
rediscover — a plain `and elemMask` folds `Include(s, 100)` onto bit 4 and looks
correct in every existing test.

## Recommendation

**Land it**, but only because the cost that justified the park is already sunk
and the evidence is unusually complete for an ABI-class change: five targets
against a real oracle, a positive control in both directions, and a green gate.
It delivers the three things the decide named — FPC-identical `SizeOf`,
blittable records for `file of T`, ESP memory — and removes the doc obligation
to advise against records-with-sets for file IO.

**The counter-argument is real and I am not hiding it:** the owner accepted that
constraint *knowingly*, `feature-pascal-typed-and-untyped-files` and a Track D
doc obligation were written on it hours ago, and landing this makes those
freshly-written words wrong. That is a coordination cost the measurements above
say nothing about, and it is the owner's call, not mine.

**If the answer is no:** `rm devdocs/dev/parked-patches/smallset-4-byte-set-storage-class.patch`
and this ticket. Nothing else needs undoing — the tree is at 32 bytes and the
rainy-day ticket is the record.

## How to land it, if that is the answer

```
git apply devdocs/dev/parked-patches/smallset-4-byte-set-storage-class.patch
rm -f compiler/.pascal26.fixedpoint && make compiler/pascal26   # expect: converged after 1 round(s)
tools/gate.sh quick                                            # run BEFORE committing: the FPC seed canary only fires on a dirty tree
```

The patch already contains the regression test and its two Makefile rows (native
pinned to the FPC literal; i386 pinned to native).

---
summary: "C bitfields: unsigned bitfield <32b promotes to UNSIGNED not signed int (silent wrong arithmetic); plus a compile HANG on a bitfield+empty-union struct — gcc-torture cluster"
type: bug
track: C
prio: 55
---

# C bitfield promotion is wrong + a bitfield-layout compile hang

- **Type:** bug (C frontend — bitfield lowering / integer promotion). **Silent**
  (wrong values) for the promotion half; a non-terminating compile for the hang half.
- **Track:** C (cfront bitfield → IR lowering). Some of it may be shared codegen
  (Track A) — the owning lane decides at pickup.
- **Found by:** the one-time gcc c-torture harvest (2026-07-15),
  [[feature-t-gcc-torture-runner]]. Self-checking programs that gcc passes and pxx
  fails; not a fuzzer, a curated corpus.

## Finding 1 — unsigned bitfield promotes to unsigned int (should be signed)

An unsigned bitfield narrower than `int` whose values all fit in a signed int must
**promote to signed int** (C integer promotions), so `x.u3 - 2` is negative. pxx
promotes it to *unsigned*, so the subtraction wraps to a huge positive value.

```c
extern void abort(void);
struct S { unsigned int u3:3; } x;   /* x.u3 == 0 */
int main(void) {
  if ((x.u3 - 2) >= 0) abort();      /* -2 < 0 on gcc; pxx wraps -> >=0 -> abort */
  return 0;
}
```

gcc: exit 0. pxx: **exit 134 (abort)** — silent wrong promotion. Corpus members
sharing this class (gcc-pass / pxx-abort): `bf-sign-2.c` (the promotion test verbatim),
`bitfld-1.c`, `bitfld-3.c`, `bf64-1.c`, `20030714-1.c`, `20040629-1.c`, `990326-1.c`,
`991118-1.c`. Some of these also exercise bitfield *signedness of operations* and
long-long bitfields — likely the same promotion root cause, verify per file.

## Finding 2 — compile HANG on a bitfield + empty-union struct

`pr23324.c` makes pxx spin at 100% CPU and never terminate (observed 35 min before a
kill). It declares an **empty union** `union at6 {}` alongside a struct of many
odd-width signed bitfields (`:6 :7 :6 :5 …`). Non-termination in the compiler on a
valid program — worse than a wrong answer. Reduce to isolate whether the trigger is
the empty aggregate, the odd-width bitfield packing, or their combination.

## Reproduce

```
compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src \
  library_candidates/gcc-torture/execute/bf-sign-2.c /tmp/bf && /tmp/bf   # exit 134
timeout 5 compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src \
  library_candidates/gcc-torture/execute/pr23324.c /tmp/x                 # exit 124 = hang
```

## Acceptance

The minimal promotion repro exits 0 under pxx (unsigned sub-`int` bitfield promotes to
signed int); `pr23324.c` compiles in bounded time; the listed corpus members pass or
are re-triaged to a distinct root cause; a `test/` regression pins the promotion rule.

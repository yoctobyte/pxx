---
prio: 60
---
# bug: UClass field window base goes stale under shells-then-fields registration

- **Type:** bug (Track A — symtab.inc, AddUClass/AddUField contract)
- **Opened:** 2026-07-09 (found by the Rust chess-corpus tuple-struct rung —
  filed instead of worked around per the experimental-frontends rule)
- **Status:** done
  [[feature-rust-corpus-chess]] (any program with 2+ field-bearing structs
  registered shells-first)

## Symptom

Two tuple structs, fields registered in a shells-then-fields two-pass (the
pattern rparser.inc uses so struct fields can reference other structs):

    struct Square(u8);
    struct Pair(i64, i64);
    let p = Pair(300, 44);
    p.0   -> reads 44 (p.1's value); both fields resolve to the same slot

Order-dependent: Pair declared first works; Square first corrupts Pair.
NOT tuple-specific — two NAMED structs with fields hit it identically; it
was latent because no Rust test ever declared two field-bearing structs
(test_rust_advanced has one struct + one enum, and enums register their
fields immediately after their own AddUClass, which is the safe pattern).

## Root cause (read, not guessed)

`AddUClass` (symtab.inc) stamps `UClsFBase[ci] := UFldCount` at CLASS
CREATION time. With shells created up front, every class gets
FBase = the then-current tail (e.g. both Square and Pair get FBase=0).
Square's field appends at global index 0 (window correct by luck);
Pair's first field appends at index 1 while UClsFBase[Pair] is still 0 —
Pair's window [0..1) now covers SQUARE's field. Worse, Pair's second
AddUField sees `FCount>0 and FBase+FCount < UFldCount` and triggers the
window-relocation path on the wrong entries.

## Proposed fix (one line, but it is A's line)

In AddUField, re-base an EMPTY window to the tail before appending:

    if UClsFCount[ci] = 0 then UClsFBase[ci] := UFldCount;

Safe against the two documented special cases: the anonymous-record
relocation only fires for FCount>0, and the C parser's manual re-anchor
(window extending past the tail) also only exists with FCount>0 — an
empty window carries no data to lose. AddUMeth/UClsMBase (and UClsPBase)
have the same stamp-at-creation shape and likely want the same guard the
day any frontend registers method shells early.

## Repro

    cat > /tmp/two_structs.rs <<'EOF'
    struct Square(u8);
    struct Pair(i64, i64);
    fn main() -> i32 {
        let p = Pair(300, 44);
        println!("a {} b {}", p.0, p.1);
        return 0;
    }
    EOF
    ./compiler/pascal26 /tmp/two_structs.rs /tmp/t && /tmp/t
    # prints "a 44 b 44"; expected "a 300 b 44"

(Requires the tuple-struct frontend support landed 2026-07-09 on the
chess-corpus branch of work; two named structs repro equally with the
older named-field support.)

## Gate for the fix

Repro prints 300/44; make test green; self-host fixedpoint byte-identical
(the Pascal frontend registers fields immediately per-class, so the
compiler's own records never hit the empty-window rebase — expected
byte-identical, but that IS the gate).

## FIXED 2026-07-09 (cfront-agent, combined A+B+C) — ticket closed
Applied the proposed one-line guard in AddUField (symtab.inc): before appending,
`if UClsFCount[ci] = 0 then UClsFBase[ci] := UFldCount;` re-anchors an EMPTY field
window to the current tail. This corrects the shells-then-fields pattern
(rparser) where every shell was stamped with FBase at creation time, so a
non-first struct's first field appended at the live tail while its FBase still
held a stale earlier index — overlapping the earlier struct's window.

Confirmed via instrumentation: Pair's first field now re-bases (fbase 0→1) so its
window [1..3) no longer overlaps Square's [0..1). Repro prints "a 300 b 44".
Safe vs the two documented special cases (anonymous-record relocation + C parser
manual re-anchor) — both fire only for FCount>0.

Regression test: extended test/test_rust_tuple_struct.rs to two field-bearing
structs, smaller (Square) first → "a 300 b 44 s 7". Gates: self-host byte-
identical (Pascal registers per-class, never hits the empty-window rebase — the
byte-identical result IS the gate), quick tier green, c-conformance 214/0/6 (C's
re-anchor untouched), all Rust tests green, Pascal multi-record sanity green.
Unblocks the multi-struct rungs of feature-rust-corpus-chess.

Note: AddUMeth/UClsMBase and UClsPBase have the same stamp-at-creation shape and
will want the identical guard the day a frontend registers method/prop shells
early — left as-is (no current trigger).

## Log
- 2026-07-09 — resolved, commit PENDING.

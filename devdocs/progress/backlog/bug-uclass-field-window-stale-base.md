---
prio: 60
---
# bug: UClass field window base goes stale under shells-then-fields registration

- **Type:** bug (Track A — symtab.inc, AddUClass/AddUField contract)
- **Opened:** 2026-07-09 (found by the Rust chess-corpus tuple-struct rung —
  filed instead of worked around per the experimental-frontends rule)
- **Status:** backlog — BLOCKS the multi-struct rungs of
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

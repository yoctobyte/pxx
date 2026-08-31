---
slug: decide-shift-native-width-was-never-re-confirmed-on-the-full-table
title: "Does a DECLARED 32-bit `shr`/`shl` still happen at native width? The ruling's own author asked for a re-confirmation and never got one"
track: U
prio: 45
type: decision
blocked-by: []
status: open
owner: ""
created: 2026-08-31
summary: "decide-shift-operator-promotion-width (2026-08-10) ruled that shifts happen at NATIVE width. The next day its implementer measured that the cost table the user was shown listed ONE divergence from FPC and the real number is four, wrote 'the call is worth re-confirming rather than assuming', and filed nothing — the note lives inside a file in decided/, which by construction nobody re-opens. Two agents have since hit the divergence in the wild and filed it as a bug. One question for the user: keep native width for a DECLARED narrow variable, or promote only UNTYPED operands. Untyped operands are already settled and are not in scope."
---

# The fork

Only for a **declared** narrow integer — `var i: Integer`. Untyped literals are
settled and out of scope: they promote to 64 bits on every target
(`243ff4a29`), which is what both options below already agree on.

1. **Keep it** (status quo, shipped 2026-08-11). One rule, native width
   everywhere, nothing to do.
2. **Promote only an UNTYPED operand.** A declared `Integer`/`Cardinal` keeps
   its width; a literal does not have one. This is the "a declared type IS an
   explicit width specification" half of the 2026-08-10 decision's *own*
   reasoning, which the final rule then overrode.

`--strict-fpc` gives option 2's answers today and is verified to, on all eight
rows of the probe below. So option 2 is not a capability we lack; the question
is purely which one is the DEFAULT.

# Why it is being asked, and it is not a new objection

The decision was made on a table showing **one** divergence from FPC. The
implementer measured **four** the next day and recorded why the table understated
it — the `-a shr 1` row agreed with FPC only because FPC's unary minus already
widens an Integer to Int64, so that row never exercised `shr`'s own width at all.
Measured again at HEAD, x86-64:

| row | FPC | pxx default | pxx `--strict-fpc` |
| --- | --- | --- | --- |
| `i shr 1`, i: Integer = -8 | 2147483644 | 9223372036854775804 | 2147483644 |
| `i := i shr 1` then print i | 2147483644 | -4 | 2147483644 |
| `i shl 31`, i: Integer = 1 | -2147483648 | 2147483648 | -2147483648 |
| `1 shl 40` (untyped, out of scope) | 2^40 | 2^40 | 2^40 |

He then wrote, of the ruling he had just implemented:

> "the call is worth re-confirming rather than assuming."

and filed no ticket for it. The paragraph sits in
`devdocs/progress/decided/decide-shift-operator-promotion-width.md`, in
`decided/`, which the ranker does not scan and no agent re-opens — so the
re-confirmation could not happen, and did not.

# What has happened since, which is the actual new evidence

Two independent agents have hit the divergence in real work and filed it as a
defect, neither having found the ruling:

- `bug-a-shr-on-a-32-bit-operand-does-not-promote-like-fpc` (2026-08-10, the one
  the decision was made FOR)
- `bug-a-shr-on-a-32-bit-operand-is-evaluated-at-64-bits` (2026-08-28, from the
  wasm32 backend, resolved 2026-08-31)

That is a measurement about the ruling: its cost is not one-off, it recurs, and
it recurs as *lost agent time re-deriving a settled question*. It is not an
argument that the ruling is wrong — widening never loses information and
truncating does, which is still the strongest thing anyone has said here.

# What would make this disappear without asking

Nothing measurable. `--strict-fpc` already answers "can we have FPC's numbers"
(yes), and the RTL was already checked and is unaffected (SHA-256 and CRC32 land
their intermediates in `LongWord` variables, so the STORE narrows). What is left
is a preference about the default dialect, which is Track U by definition and
the user's alone.

**Cheap to answer: "keep it" closes this in one word.** The reason it is worth
one word of his attention rather than none is that the record currently says the
call was made on incomplete information and asks for exactly this.

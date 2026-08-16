---
track: U
prio: 20
type: decide
blocked-by: []
summary: "`for d in [1, 2.5]` — FPC 3.2.2 prints `1.00 0.00`, dropping the 2.5; pxx prints `1.00 2.50`. Shipped as the correct answer rather than copied, because losing a written value is a defect and not a semantic choice. Confirm, or put FPC's answer behind --strict-fpc."
---

# `for d in [1, 2.5]`: match FPC's dropped value, or keep the right one?

Measured 2026-08-15 while fixing
[[bug-p-for-in-over-a-float-array-constructor-iterates-once-with-zero]].

```pascal
var d: Double;
for d in [1, 2.5] do Write(d:0:2, ' ');
```

| | |
| --- | --- |
| FPC 3.2.2 | `1.00 0.00` |
| pxx (as shipped today) | `1.00 2.50` |

FPC's mixed integer/float array constructor **drops the 2.5**. Not a rounding
difference and not an order difference — the value the source wrote does not
come out. (The ticket that led here predicted "FPC promotes"; it does not, and
that prediction is what made this worth measuring rather than assuming.)

## The fork

This repo's default is the reference implementation, with deviations behind
`--strict-*`. Applied literally, pxx should print `1.00 0.00`.

Against that: the whole defect being fixed in the same commit was a float
constructor that silently answered `0.0`, and the argument for fixing it was
that a silent wrong value is the expensive kind. Reproducing FPC here would
reintroduce the same failure mode by hand, in the one row a reader is least
likely to test.

## Options

1. **Keep `1.00 2.50` (shipped, recommended).** A written value always comes
   out. Documented in `test/test_forin_nonordinal_array_ctor.pas` at the row
   itself, so it is not silent. Costs: one more entry in the deliberate-
   divergence list; a program relying on FPC's zero (nobody writes that on
   purpose) behaves differently.
2. **Match FPC exactly**, and gate the correct answer behind a flag. Costs:
   pxx knowingly emits a wrong value by default.
3. **Refuse the mixed constructor** with a diagnostic ("mixed integer and float
   array constructor: write 1.0"). Neither compiler does this, and it breaks
   source FPC accepts — but it is the only option where nobody gets a silently
   wrong number.

## Recommendation

Option 1, which is what is shipped. Option 3 is a defensible second if the
project would rather refuse than diverge; it needs a `--strict-*` escape and a
sweep of the corpora for mixed constructors before it could land.

Nothing is blocked on this — the row is asserted either way, so a decision is a
one-line change to the test plus the arm in `parser.inc`.

---

## MEASURED 2026-08-16 — FPC does not "drop the value"; it reads uninitialised memory

Re-measured before deciding, FPC 3.2.2 as the oracle, pxx =
`stable_linux_amd64/default/pinned`. **The ticket above understates this
badly.** FPC's answer is not a lossy-but-defined semantics — it is garbage whose
value depends on what was in memory beforehand.

### The row that settles it

```pascal
for d in [9.25, 8.25, 7.25, 6.25] do Write(d:0:2,' '); WriteLn;   { FPC: 9.25 8.25 7.25 6.25 }
for d in [1.5,  2,    3         ] do Write(d:0:2,' '); WriteLn;   { FPC: 1.50 9.25 8.25       }
```

The second loop prints **9.25 and 8.25 — values from the previous statement's
array.** Nothing wrote them into this one. That is a read of stale memory, not a
conversion rule, and it cannot be reproduced deliberately because it is not a
function of the source.

### It is positional, not type-driven

| source | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `[1, 2.5]` | `1.00 0.00` | `1.00 2.50` |
| `[2.5, 1]` | `2.50 2.50` | `2.50 1.00` |
| `[1, 2.5, 3]` | `1.00 0.00 3.00` | `1.00 2.50 3.00` |
| `[1, 2.5, 3, 4.5, 5]` | `1.00 0.00 3.00 0.00 5.00` | all correct |
| `[1.5, 2, 3.5, 4, 5.5]` | `1.50 0.00 3.50 0.00 5.50` | all correct |
| `[1, 2, 3.5]` | `1.00 2.00 0.00` | all correct |
| `[1.0, 2.5]` (no mix) | `1.00 2.50` | `1.00 2.50` |

Rows 4 and 5 are the pair to read together: in row 4 the **floats** at odd
indices vanish, in row 5 the **integers** at odd indices vanish. Same positions,
opposite types — so this is not "integers get dropped" or "floats get dropped",
and the ticket's `[2.5, 1]` → `2.50 2.50` shows it is not "dropped" at all.

The element **count** is always right (`n=5`, `n=3` measured); only the payloads
are wrong. And FPC emits **no diagnostic at `-viwn`** — not a warning, not a
hint.

### Root cause, and it is the same one as the set/array-of-const ticket

FPC defers bracket-literal interpretation to the **target type** — the
`tarrayconstructornode` mechanism from
[[bug-p-set-literal-elements-are-not-type-checked]]. Give it a target and it is
perfect:

```pascal
procedure Show(const a: array of Double);
Show([1, 2.5, 3]);        { FPC: 1.00 2.50 3.00 — correct, integers promoted }
```

`for..in` supplies no target type. `nflw.pas:925-940` dispatches on
`expr.resultdef.typ` *after* an arrayconstructor→set conversion that only fires
for ordinal loop variables, so a mixed constructor with a `Double` loop variable
reaches `create_array_for_in_loop` still carrying mixed element types, and the
loop reads it at a uniform stride.

So the **same deferral that makes FPC better than pxx at the overload/set case
makes it worse here.** One representational choice, two opposite consequences —
worth stating in whatever documents either.

### Is it fixed in trunk?

**No evidence of a fix.** `origin/main` at `670f9396c4` (2026-05-29): the
for-in dispatch block is unchanged in shape, and the only diff to
`create_array_for_in_loop` between `release_3_2_2` and `origin/main` is the
slice-iteration feature (`0417504d12`). A `--grep` sweep of the intervening log
for for-in / array-constructor fixes turns up nothing relevant.

Honest limit: **this was not verified by building trunk**, only by reading the
diff. It is "no fix found", not "confirmed still broken".

## What this does to the fork

**Option 2 is not implementable and should be struck.** "Match FPC exactly"
presumes FPC has an answer to match. It does not: the output of `[1.5, 2, 3]`
depends on the preceding statement. There is nothing to put behind
`--strict-fpc` except a random number generator.

That collapses the decision to option 1 versus option 3, and the framing changes
with it. This is no longer "deviate from the reference implementation" — which
is the thing this repo's `compat` tag treats as needing justification. It is
**a plain FPC bug that pxx does not have**, in the same family the escape rule
already names: a compat finding that means *silent wrong behavior* is a bug, not
a parity item. That rule points at pxx's own divergences, but the principle is
symmetric — we do not reproduce a silent wrong value to be compatible with one.

Recommendation stands at **option 1** (ship the correct answer, which is what
ships), now on much firmer ground than "a written value should come out": there
is no competing semantics, only a defect. Option 3 (refuse the mixed
constructor) loses its main attraction too — it was "the only option where
nobody gets a silently wrong number", but option 1 already has that property, so
3 now only costs us source FPC accepts.

### Worth recording as compat, not as a divergence

Since pxx is *right* here, this belongs in the compat notes as an FPC-3.2.2 bug
we do not reproduce, not in the deliberate-divergence list where the ticket
proposed to file it. Those lists mean different things to a reader deciding
whether their FPC code will port.

Unrelated gap confirmed already tracked while measuring: `TDA.Create(1.0, 2.5)`
(Delphi dynamic-array constructor) is rejected by pxx and is already recorded as
a conformance gap — `tstate/conformance.tsv:22`, `tarrconstr1.pp`. Not filed
again.

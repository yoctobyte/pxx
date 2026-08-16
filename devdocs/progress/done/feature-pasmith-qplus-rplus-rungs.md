---
summary: "pasmith rungs for {$Q+}/{$R+}: generate checked regions + try/except EIntOverflow/ERangeError harnesses, differential vs FPC"
type: feature
prio: 30
track: T
status: done
---

# pasmith: fuzz the {$Q+}/{$R+} check machinery

- **Type:** feature (fuzz grammar — Track T owns the tool).
- **Opened:** 2026-07-15, after the night that landed both features
  ([[feature-pascal-overflow-checks-q-plus]] slices all-hosted-targets,
  [[feature-pascal-range-checks-r-plus]] slices 1-5).

## Why

The checks were hand-oracle-verified shape by shape, and TWICE the ticket's
assumed semantics were wrong until probed (FPC does NOT check Abs/Sqr or
subword ops). A generator that sprinkles {$Q+}/{$R+}/{$Q-}/{$R-} regions
over its existing arithmetic/array/subrange rungs and counts caught
EIntOverflow/ERangeError per checkpoint would differentially pin the whole
semantic surface against FPC — including the statement-anchor timing rule
(trange4) that a directive between RHS and statement end must not
retro-apply.

## Sketch

- New knob `--checks N`: with probability derived from N, wrap a statement
  run in `{$Q+}`/`{$R+}` (and matching try/except counting per class).
- The checksum mixes the caught-counts, so a divergence localizes like any
  other checkpoint.
- Needs pasmith's exception rung (already exists: --excepts).

## 2026-08-16 — DONE. `--checks`, and it is in `--wide`

### The semantics were MEASURED before a line of the rung was written

The ticket's own history is why: the checks were hand-verified shape by shape
and *twice* the assumed semantics were wrong until probed. So the same
discipline applies to building a generator on top of them — a rung built on a
deliberate divergence is a noise generator, which is exactly what
[[bug-t-fpc-probe-reports-the-deliberate-shl-deviation-as-new]] had just
finished being.

pxx vs FPC 3.2.2, seven shapes, all **agreeing**:

| shape | both compilers |
| --- | --- |
| `a + b`, `a - b`, `a * b` overflow (longint) | **ERangeError** |
| nested `(a * b) + c` | ERangeError |
| implicit narrowing `smallint := longint` | ERangeError |
| array read out of bounds | ERangeError |
| explicit cast `smallint(a)`, `byte(a)` | silent, no raise |
| non-overflowing arithmetic | silent |

Two things worth writing down. It is **ERangeError, not EIntOverflow**, that
arrives for arithmetic overflow — so the handler counts BOTH classes rather than
assuming, since which one arrives is itself part of what the rung pins. And pxx
**does** honour `{$R+}` on array indexing, which is what makes an unclamped
index safe to generate: had it not, the program would read out of bounds instead
of raising, and a fuzzer that can corrupt memory is not measuring anything.

### The rung

`--checks N` adds a `checked` statement kind:

```pascal
{$Q+}{$R+}
try
  g0 := (g0 + pv1^.r1n.r1i1) - r0g.r0n.r0i0;
  Mix(int64(g0));
except
  on E: EIntOverflow do Mix(7001);
  on E: ERangeError do Mix(7002);
  on E: Exception do Mix(7099);
end;
{$Q-}{$R-}
```

Two shapes: arithmetic (`+ - *`, sometimes nested one deep) into a live target,
and an unclamped array read. The caught class folds into the checksum, so a
divergence localises like any other checkpoint — and it is tagged `checked`, so
it signs distinctly in the ledger.

**No shifts inside a checked region, deliberately.** pxx computes shifts at
native width by design (2026-08-11), so a `shl` overflowing 32 bits raises under
FPC and not under pxx — a guaranteed false divergence. That is why the rung
builds its own operand expression instead of calling `self.expr()`, which can
emit shifts, `SafeDiv` and casts.

`{$Q-}{$R-}` restores rather than pops: pasmith never enables these globally, so
that is the correct outer state.

### In `--wide`, and why that was the point

Folded into `WIDE_DEFAULTS` at 1 after it ran clean. The two rungs excluded from
`--wide` (`--intfs`, `--mptrs`) are excluded because they diverge on ~100% of
seeds against known filed bugs; this one has no known divergence, and leaving it
out would mean **nothing ever runs it** — every real slice uses `--wide`. The
`None`-vs-`0` discipline is preserved: `--wide --checks 0` still turns it off.

Doing that exposed that the two `--wide` implementations — `pasmith.py`'s and
`pasmith_run.WIDE_DEFAULTS` — are separate lists that had already drifted. Both
updated, with a note on each pointing at the other.

### A pre-existing bug this surfaced, fixed alongside

[[bug-t-pasmith-gen-args-header-omits-half-the-rungs]] — the self-describing
`gen-args:` header listed 13 knobs against the constructor's 21, four of the
missing ones set by `--wide`. `localize()` rebuilds the subject from that
header, so on every wide seed it was tracing a **different program** (1500 lines
against the original's 1770). The new knob would have inherited the same defect,
which is how it was found. Header now generated from one list; round-trip
verified byte-identical on five seeds.

### Verified

- `pasmith_run.py --check 40 --wide --checks 1`: 40 seeds, **0 rejected by FPC**.
- `pasmith_run.py --seeds 90010-90070 --wide --checks 1`: **61 programs, 0
  divergences.**
- `pasmith_run.py --check 30 --wide` (rung on by default): 30 seeds, 0 rejected.
- Both shapes confirmed present and agreeing between pxx and FPC on generated
  programs, arithmetic and array-read.
- `pasmith_run.py --seeds 90100-90150 --wide` — FRESH seeds, rung on by default,
  nothing passed explicitly: **51 programs, 0 divergences.**

## Log
- 2026-08-16 — resolved, commit PENDING-COMMIT.

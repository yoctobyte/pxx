---
track: N
prio: 55
type: bug
summary: "A def whose result type was inferred (or annotated) as int TRUNCATES a float it returns: `def g() -> int: v = 1; v = 2.5; return v` gives 2 where CPython gives 2.5. Python annotations are not enforcement. Pinned returned the raw IEEE BITS (4612811918334230528) for the same program — improved to truncation by the widen-binding fix, not resolved by it."
status: done
owner: claude-AN
---

# a def's return coerces a float to its inferred int result type

- **Type:** bug (NilPy — silent wrong value) — **Track N**
- **Found:** 2026-08-03, measuring the blast radius of
  [[bug-nilpy-int-prints-as-float-when-the-name-is-widened-later]]. Separate
  defect; that fix improved these two cases without fixing them, which is why
  they are not in its test.

## Measured

```python
def g() -> int:
    v = 1
    v = 2.5
    return v
print(g())              # CPython 2.5   pinned 4612811918334230528   HEAD 2

def k():                # NO annotation
    v = 3
    v = 0.5
    return v + 1
print(k())              # CPython 1.5   pinned 0                     HEAD 1
```

Both are silent. `g`'s pinned answer — `4612811918334230528` — is the IEEE 754
bit pattern of 2.5 read as an integer, which is the same shape as every other
"scalar-loaded through the wrong type" bug in this frontend. HEAD truncates
instead, which is better and still wrong.

The controls that DO agree, so the defect is narrow:

```python
def h():
    v = 3
    v = 0.5
    return v            # 0.5, correct — returning the value itself is fine
z = 2; print(z * 3)     # 6
z = 0.5; print(z * 3)   # 1.5 — arithmetic on the widened binding is fine at
                        #       module level
```

So it is not variant arithmetic in general, and not the widened binding in
general. It is the RETURN: `h` returns the variant unchanged and is right,
while `k` returns an EXPRESSION over it and loses the float.

## Where to look

Two candidates, and they may both be live:

- **the annotation.** `-> int` is being treated as enforcement. In Python an
  annotation is metadata — `def g() -> int` returning 2.5 returns 2.5 — so
  coercing on the way out is wrong regardless of what the body does. That is
  `g`.
- **the inferred result type.** `k` has no annotation, so its result type came
  from inference, and `v + 1` over a variant-typed `v` apparently typed as int
  (probably from the literal `1`, or from `v`'s FIRST binding). That is the
  same "decided from a literal" family as
  [[bug-nilpy-int-promotion-decided-statically-so-computed-overflow-wraps]] and
  [[bug-nilpy-range-negative-runtime-step-yields-empty]] — worth reading both,
  a general answer may cover all three.

## Gate

A `.npy` diffed against CPython: both repros; an annotated `-> int` def
returning a plain float literal (does the annotation coerce on its own?); an
unannotated def returning `float + int`; `h`'s form as the passing control; and
an annotated `-> float` def returning an int (the mirror — CPython returns the
int unchanged, `1`, not `1.0`).


## 2026-08-03 — measured across all seven shapes, and the design answer is already in the tree

Picked up straight after filing it, while the context was fresh. Not landed: the
fix is an ABI-level change and the measurement says so clearly enough to hand
over rather than half-do at the end of a session.

### The full table

| program | pxx | CPython |
| --- | --- | --- |
| `def a() -> int: return 2.5` | **4612811918334230528** | 2.5 |
| `def b() -> float: return 1` | 1.0 | **1** |
| `def c(): return 2.5` | 2.5 | 2.5 ok |
| `def d(): v=3; v=0.5; return v` | 0.5 | 0.5 ok |
| `def e(): v=3; v=0.5; return v + 1` | 1 | 1.5 |
| `def f() -> int: v=1; v=2.5; return v` | 2 | 2.5 |
| `def g(): return 0.5 + 1` | 1.5 | 1.5 ok |

So it is not one defect but one CAUSE with two faces:

- **the annotation is enforcement** (a, b, f). `-> int` coerces, and `-> float`
  coerces the other way — `b` returns `1.0` where CPython returns the int `1`.
  `a` is the worst of the set: the double's BITS reinterpreted as an integer,
  not even a truncation.
- **the inferred result type** (e). No annotation, and `v + 1` over a
  variant-typed `v` still came out int.

Everything unannotated and unwidened is correct (c, d, g), which is what makes
the result TYPE the suspect rather than the arithmetic.

### The design answer is already written down, for a neighbouring case

`PyParseDefHeader` (`compiler/pyparser.inc`) already handles exactly this
conflict for `-> None`:

> `-> None` declares a procedure (no Result) — UNLESS the body returns a value
> anyway (CPython ignores annotations; uforth's finalize_definition lies). Then
> the annotation loses and the type is inferred, or the caller reads a
> discarded Result as garbage.

"CPython ignores annotations" and "the annotation loses" is the whole rule, and
the consequence named there — *the caller reads a discarded Result as garbage* —
is literally what row `a` shows. The fix is to extend that precedent from `None`
to every annotation: join the annotation with `PyInferDefRetType`'s answer (via
`PyWidenBinding`, added for
[[bug-nilpy-int-prints-as-float-when-the-name-is-widened-later]]), so a
disagreement yields a VARIANT, which carries either. That also gives row `b` the
right answer for free: float ⊕ int = variant, and the variant renders the int
as `1`.

### Why it was not landed here

Two things need care, and both are ABI:

1. **`PyInferDefRetType` returns `tyInteger` when it finds nothing**, so a def
   with no value return would join to a variant against any annotation. The
   join must be gated on the inference having actually SEEN a return — the
   function tracks that in `seenAny`, which it does not currently expose.
2. **The result type IS the calling convention.** A variant result uses the
   hidden-destination convention; a scalar returns in a register. The header
   comment right above this code says the pre-pass and the frame "MUST agree,
   since the pre-pass decides the signature and this decides the frame, and a
   disagreement is a silent ABI mismatch". So the same join has to be applied
   in `PyMethodRetType`'s pre-pass, in step, and that pairing is the actual
   work.

Neither is hard; both are exactly the kind of thing that wants a full run and a
fresh session rather than the tail of a long one.

Row `e` (the unannotated, inferred case) may or may not fall out of the same
change — `v + 1` should type variant already, so if it still comes out int
after the join, that is a second, narrower inference bug and deserves its own
measurement.


## Resolved 2026-08-04 — all seven rows, and row `e` was worse than recorded

The 2026-08-03 hand-off was accurate and its recommendation is what landed. All
seven rows of the table now match CPython, plus three shapes the measurement
here added.

### The annotation half (rows a, b, f)

`PyJoinRetAnnotation` extends the precedent already written for `-> None`
("CPython ignores annotations… then the annotation loses") to every annotation:
join the annotation with `PyInferDefRetType`'s answer, and a disagreement
yields a variant, which carries either and renders each value as itself.

Two things the hand-off flagged, both handled as it described:

1. **Gated on the inference having SEEN a value-bearing return.**
   `PyInferDefRetType` answers `tyInteger` when it finds none, which is
   indistinguishable from a def that genuinely returns an int; a def with no
   value return would otherwise join to a variant against any annotation. It
   now reports `seenAny` through `PyInferRetSeenAny`, the same global shape
   `PyInferLastCi` already uses.
2. **Applied at BOTH sites in step** — `PyMethodRetType` (signature) and
   `PyParseDefHeader` (frame). The result type is the calling convention, so a
   difference between those two is a silent ABI mismatch.

The join deliberately fires **only when it produces a variant**, i.e. only for
the int-meets-float pair `PyWidenBinding` redirects. Every other annotation
keeps exactly its old answer — in particular `-> str` stays the managed
`tyAnsiString` rather than being re-joined with a `tyString` and quietly
becoming a frozen `string[N]`.

### Row `e` did NOT fall out of that, and it is a bigger hole than the ticket had

The ticket predicted this and asked for its own measurement. Measured:

| program | before | CPython |
| --- | --- | --- |
| `def h(): v = 0.5; return v + 1` | **4609434218613702656** | 1.5 |
| `def i(): v = 0.5; return v * v` | 0.25 (ok) | 0.25 |
| `def j(): v = 0.5; w = v + 1; return w` | **4609434218613702656** | 1.5 |

So it is not about the REBINDING at all — a plain float local is enough, and the
answer is the double's IEEE bits, not the truncation the ticket recorded. The
cause: the returned-expression scanner is token-only (it has to be — the shell
pre-pass has no `PyLocals`, and answering differently in the two passes is the
ABI mismatch above), so in `v + 1` it cannot type `v` and took `tyInt64` from
the literal `1` alone. The existing chase that would have found `v` only fires
for a BARE ident return.

Fixed by extending that chase to expressions: `PyRetNameType` reads a name's
last well-typed assignment from tokens, and each name in a returned expression
is chased and widened in. Token-only, so both passes still agree. Only when the
expression scan produced its integer default, and only for names that chase to
something better than an integer, so ordinary integer defs keep a scalar result
and box nothing (`def m(): n = 2; return n * 3` is still 6, scalar).

### A latent break this uncovered, worth reading

Those chases were all guarded on `cur = tyInteger`. The field-width fix earlier
today (`ae4057989`) made an integer LITERAL report `tyInt64` instead of
`tyInteger` — so every one of those guards silently stopped firing for any
return expression containing an int literal. `PyRetIsIntDefault` now tests both
kinds in one place. This is why row `e` measured worse than when it was filed:
part of the damage was a day old.

### FPC seed canary caught it, `make` did not

`PyJoinRetAnnotation` is called from `PyParseDefHeader`, which sits earlier in
the file than the body. pxx is lax about declaration order and FPC is not, so
`make compiler/pascal26` and the self-host fixedpoint both passed and the seed
build failed. Forward added. (`feedback_fpc_seed_build_not_covered_by_make_or_gate`
— `gate.sh quick` runs the canary concurrently, which is what surfaced it.)

### Verified

`test/test_nilpy_def_return_type.npy`, wired into `make test-nilpy`: all seven
original rows plus the three shapes above and two integer controls, every
expectation taken from CPython. `tools/gate.sh quick` GREEN, self-host
byte-identical.

## Log
- 2026-08-04 — resolved.
- 2026-08-04 — resolved, commit PENDING-COMMIT.

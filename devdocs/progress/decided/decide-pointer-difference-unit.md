---
track: U
prio: 30
type: decision
blocked-by: []
status: decided
summary: "FPC's `p - q` answers BYTES when either operand is an untyped Pointer (which includes `@x` under the default {$TYPEDADDRESS OFF}) and ELEMENTS when both are the same typed pointer. pxx always answers elements. `p - @a[0]` therefore prints 8 in FPC and 2 in pxx — a silent difference in ported code. Match FPC, keep the uniform rule, or diagnose?"
---

# Should `p - <untyped pointer>` count bytes, as FPC does?

Raised 2026-08-22 while fixing `bug-p-pointer-difference-is-typed-as-a-pointer`.
This is a dialect choice, not a defect, so it is a decision rather than a fix.

## The fork

```pascal
var a: array[0..7] of Integer; p, p0: ^Integer; u: Pointer;
p0 := @a[0]; p := @a[2]; u := @a[0];
```

| expression | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `p - p0` (both typed `^Integer`) | 2 | 2 |
| `p - TPI(u)` (cast back to the typed pointer) | 2 | 2 |
| `p - u` (untyped `Pointer`) | **8** | **2** |
| `p - @a[0]` (`@` is untyped under FPC's default) | **8** | **2** |

FPC's rule is a consequence of `{$TYPEDADDRESS OFF}` being its default: `@x` has
type `Pointer`, and a difference involving an untyped pointer has no element to
count, so it counts bytes. pxx scales by the LEFT operand's stride whatever the
right operand is.

## Options

1. **Match FPC.** Use the *smaller* of the two operands' strides, so an untyped
   operand (stride 1) forces a byte count. Cost: `p - @a[0]` — a natural way to
   write "index of p within a" — silently changes meaning for anyone who
   currently relies on pxx's answer, and `@` is the common spelling. Benefit:
   FPC-ported code computes the same number.
2. **Keep the uniform element rule** and record the divergence in
   `devdocs/dev/pascal-dialect-divergences.md`. pxx's rule is the more
   consistent one and matches C's typed-pointer semantics; the FPC behaviour is
   a legacy artefact of untyped `@` rather than a designed rule.
3. **Diagnose it.** Refuse `typed - untyped` with "cast the untyped operand to
   the pointer type, or to PtrUInt for a byte count" — neither dialect's answer,
   but nobody gets a silently different number. Optionally allow it under
   `--strict-fpc` with FPC's byte semantics.

## Recommendation

**Option 2, plus option 3's diagnostic behind `--strict-fpc`.** The uniform rule
is easier to explain and impossible to get subtly wrong; the FPC-parity answer
belongs with the other opt-in strictness rather than in the default dialect. But
this is exactly the kind of call CLAUDE.md says to escalate rather than pick.

## What is NOT in question

`p - q` over two pointers of the SAME typed pointer type counts elements in both
compilers, and that already agrees. The crash that led here (the difference node
typed as a pointer) is fixed and gated.

---

# DECIDED 2026-08-25 — **option 2: keep the uniform element rule; FPC's byte semantics goes behind `--strict-fpc`**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived.**

`p - q` counts ELEMENTS of the left operand's pointee, whatever the right
operand's typing. `p - @a[0]` stays 2. The divergence is recorded in
`devdocs/dev/pascal-dialect-divergences.md` as a chosen one.

## Why this is derived and not a coin-flip

Two rules stack, and they point the same way.

`frontend-compat-philosophy.md`, on Pascal:

> *"Pascal IS its own dialect ... **"FPC does X" is not by itself an argument
> for pxx doing X.** The Pascal frontend is a language we are designing, not a
> reimplementation we are scoring against a reference."*

And the classification test in `meta-dialect-extensions-and-fpc-strict`, which
decides *where* a parity behaviour lives rather than whether we have it:

> *"**Behaviour → emulate under strict.** Deterministic and derivable from the
> source ... Working code can and does rely on these, so a strict compile must
> reproduce them **even where pxx's own default is nicer**."*

FPC's byte answer is a *behaviour*, not a bug: it is deterministic, derivable
(`{$TYPEDADDRESS OFF}` makes `@x` a `Pointer`, and a difference with no element
type counts bytes), and a valid FPC program can legitimately depend on it. So it
is owed — **under the strict family**, which is precisely where the dialect
contract puts every parity behaviour whose default we choose differently. That
is clause 2 of the contract applied verbatim, not a judgement.

## Why not option 3 (refuse `typed − untyped`) in the default dialect

Tempting, because it is the only option where nobody gets a silently different
number. Refused: it makes code that compiles today stop compiling, and `@` is
the common spelling, so the blast radius is the natural way to write the
expression. Against the standing goal — *a tool that compiles and correctly runs
real programs* — a diagnostic that rejects valid pxx code to protect against a
divergence from a different compiler is the wrong trade.

It stays available as the **strict-mode wording**: under `--strict-fpc` the
operand is byte-counted per FPC, and the diagnostic's suggested casts (`to the
pointer type, or to PtrUInt for a byte count`) are the right advice to put in
the divergences doc.

## The rule this does NOT bend

`frontend-compat-philosophy.md`'s limit: *"it never licenses a wrong answer
nobody chose."* This is a wrong answer only relative to FPC, and it is now
chosen, stated, and documented — which is exactly the distinction the rule
draws. Compare `decide-variant-bitwise-width`, decided the same day the other
way, because there pxx disagreed with **itself**.

## Re-filed as work

Two, both small:

- Track **D/A** doc: `chore-doc-pascal-dialect-divergences-pointer-difference`,
  prio 25 — record this divergence, and fold in the `Null`/`Unassigned` tag
  conflation from [[decide-should-a-null-variant-raise-like-fpc]], which needs
  the same file's next entry.
- Track **P**, compat tag: `compat-pascal-strict-fpc-pointer-difference-bytes`,
  prio 15 — byte semantics for `typed − untyped` under `--strict-fpc`. Ranked
  low deliberately: no corpus target has asked for it, and per the corpus rule a
  parity item with no dependent does not get promoted by its own existence.

## Log
- 2026-08-25 — decided, commit PENDING-COMMIT.

---
track: U
prio: 25
type: decide
blocked-by: []
status: decided
summary: "pxx spells FPC's Null and Unassigned with ONE tag (VT_EMPTY). fpc 3.2.2 prints/casts an Unassigned as the empty string but RAISES EVariantTypeCastError for a Null, in both `string(v)` and `WriteLn(v)`. Rendering now follows the Unassigned half, which is the only answer one tag can give. Adopting the raise means either a second tag or making Null and Unassigned both die -- a language call, not a bug fix."
---

# Should a Null Variant raise, the way FPC does?

Split out of [[bug-a-a-null-variant-renders-as-none-in-pascal]] while fixing its
first half, 2026-08-24. That half was uncontested and is done: an empty Variant
in a **Pascal** program rendered as `None`, NilPy's word, and now renders as the
empty string on every target.

## What fpc 3.2.2 actually does — measured, not assumed

| source | fpc 3.2.2 | pxx (after the fix) |
| --- | --- | --- |
| `a := Unassigned; WriteLn(a)` | `` (empty) | `` (empty) |
| `a := Unassigned; WriteLn(string(a))` | `` (empty) | `` (empty) |
| `a := Null; WriteLn(a)` | **raises** `EVariantTypeCastError: Could not convert variant of type (Null) into type (String)` | `` (empty) |
| `a := Null; WriteLn(string(a))` | **raises**, same message | `` (empty) |

So FPC's two empties are not one behaviour with two spellings — one prints and
one dies. pxx has a single `VT_EMPTY` tag serving `Null`, `Unassigned` and
NilPy's `None` (documented in `lib/rtl/variants.pas`' header and in
`builtin.pas`' `PXXVarBinOpPas`, where the conflation gives the *right* answer:
FPC propagates both through arithmetic, each as itself, so one propagating tag
is correct there).

## The fork

1. **Leave it** — VT_EMPTY renders as empty, `Null` never raises. Cheapest, and
   it never turns working code into dying code. The residual divergence is only
   *which of VarIsNull/VarIsEmpty answers True*, which is pre-existing and
   already documented.
2. **Split the tag** — give `Null` its own tag so the raise can be per-spelling.
   Real work: every tag test in `builtin.pas`, `pylib.pas`, the four backends'
   variant dispatch and `rtti_emit.inc` learns a second empty, and the NilPy
   side must map `None` to exactly one of them. The arithmetic conflation above
   would have to be re-proved, not assumed.
3. **Raise for VT_EMPTY behind `--strict-fpc`** — no new tag; the strict flag
   picks a raising renderer at the lowering seam, exactly as `VariantToCharFPC`
   is picked today. Wrong in one direction (an `Unassigned` would raise too,
   where FPC prints), so it buys parity for the commoner spelling only.

## Recommendation

**Option 1, and close this.** CLAUDE.md's own rule — *"we seek LANGUAGE
compliance, not error-handling compliance"* — puts a divergence whose subject is
"which exception does it raise" at the bottom of the queue, and this one is
worse than that: it changes what compiles-and-runs today into what dies today,
for a value the dialect deliberately does not distinguish. Option 2 is the only
one that could be fully right, and it is a language-wide tag commitment
(cf. [[decide-variant-tag-space-is-a-language-wide-commitment]], rejected) for a
payoff of one error message.

Filed as a decision rather than acted on because "should this program now die?"
is not a call to make from the code.

---

# DECIDED 2026-08-25 — **option 1: leave it. `Null` does not raise.**

Decided by an agent under the no-human-available rule
(`devdocs/progress/decided/README-agent-decisions.md`). **Derived**, and this
one is settled by a rule quoted in the ticket itself.

CLAUDE.md, on the scope of the strict family:

> *"A strict flag's scope is COMPILATION, not death ... They do NOT govern how a
> program DIES ... **We seek LANGUAGE compliance, not error-handling
> compliance**."*

The entire subject of this divergence is *which exception a conversion raises*.
That is error-handling compliance by definition, and the owner's standing call
puts it at the bottom of the queue — not as a matter of ranking, but as a matter
of what we are trying to be compatible about.

Two further points, each independently sufficient:

**It converts working code into dying code.** Every option but 1 takes a program
that compiles and runs today and makes it terminate. Against the standing goal —
*a tool that compiles and correctly runs real programs* — that is a negative
delivery in exchange for one error message.

**Option 2 is a language-wide tag commitment for that one message.** Splitting
`Null` from `Unassigned` means every tag test in `builtin.pas` and `pylib.pas`,
four backends' variant dispatch, `rtti_emit.inc`, and a NilPy `None` mapping —
and the ticket correctly notes the arithmetic conflation would have to be
*re-proved*, since one propagating tag is currently the *right* answer there.
The near-identical [[decide-variant-tag-space-is-a-language-wide-commitment]]
was already rejected. Deciding it the other way here would contradict a standing
decision for a strictly smaller payoff.

Option 3 was also refused: raising for `VT_EMPTY` under `--strict-fpc` would
make `Unassigned` raise too, where FPC prints. It buys parity for one spelling
by breaking it for the other.

## The residual divergence, and it stays

pxx spells `Null` and `Unassigned` with one `VT_EMPTY` tag. `VarIsNull` /
`VarIsEmpty` therefore both answer True for both, and neither raises. This is
pre-existing, already documented in `lib/rtl/variants.pas`' header, and is now
**chosen** rather than merely inherited — which is the thing this ticket
actually changes. `frontend-compat-philosophy.md`: the dialect *"licenses
different SEMANTICS chosen on purpose."* Now chosen.

## Re-filed as work

None. This closes with no follow-on ticket; the half that was a real bug (an
empty Variant rendering as NilPy's `None` inside a **Pascal** program) was
already fixed under
[[bug-a-a-null-variant-renders-as-none-in-pascal]]. The one small documentation
task — recording the conflation in
`devdocs/dev/pascal-dialect-divergences.md` as a deliberate divergence rather
than leaving it only in a unit header — is folded into
[[decide-pointer-difference-unit]]'s re-filed doc ticket, since that ticket
creates the same file's next entry.

## Log
- 2026-08-25 — decided, commit 28c19f214.

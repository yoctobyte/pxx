---
slug: bug-a-the-nilpy-arms-in-the-shared-call-loop-are-dead-and-guarded-by-the-wrong-flag
track: A
prio: 40
type: bug
status: new
owner: ""
blocked-by: []
summary: "MEASURED, not reasoned. The NilPy star/kwargs arms inside the SHARED call-argument loop (pasparser_expr.inc ~7730-7955) never fire for NilPy source, because NilPy source goes through PyParseFactorCore's own copy of that loop. They are guarded by `isNilPy` (true for the whole compilation) where the question is `PyExprMode` (is THIS unit Python) -- and with PyExprMode true the code is unreachable anyway, ParseFactorCore having Exited to PyParseFactorCore 7000 lines earlier. So they are evaluated ~3000 times per NilPy compile while parsing PASCAL library units, where a `*` token and a `name=` keyword cannot occur. Four star arms never fired in six programs; the keyword-overload retarget ran ~3000 times and changed procIdx ZERO times, including on the exact call its own bug ticket cites. Likely a deletion, not a hook -- which would remove 19 of the NilPy carve's remaining sites instead of wrapping them."
---

# The NilPy arms in the shared call-argument loop are dead, and guarded by the wrong flag

- **Found:** 2026-08-31 by frankA, while triaging
  [[refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops]].
  Filed rather than fixed: the deletion needs a full NilPy tier to bless, and
  this lane's hook denies it.

## The structure

The call-argument loop exists **three times**:

| where | reached when |
| --- | --- |
| `pasparser_expr.inc:~7730` | expression position, shared |
| `pasparser_stmt.inc:~6100` | statement position, shared (its own comment says *"see the twin site"*) |
| `pyparser.inc:~48960`, inside `PyParseFactorCore` | NilPy's own |

`ParseFactorCore` Exits to `PyParseFactorCore` at `pasparser_expr.inc:521`
whenever `PyExprMode`. **So the shared loop at 7730 is only ever reached with
`PyExprMode` FALSE** — which, per `defs.inc:4199` and `pasparser_proc.inc:4697`,
means *a Pascal unit pulled in by a NilPy program*. Pascal has neither `*args`
nor `name=` call syntax.

## Measured

A probe on each arm, six programs (`zip_star_and_n_way`, `lazy_map_filter`,
`lib_mimic_string_template`, `unbound_method_keyword_args`, `a_unicode_identifier`,
and a two-line `html.escape(s, quote=False)`):

| arm | fired |
| --- | --- |
| `PyStarIterableForm` (`f(*xs)` first-arg) | **0** |
| star-forward into fixed slots | **0** |
| `PyStarUnpackProcArgs` (`f(1, *xs)`) | **0** |
| star-splice into a collecting callee | **0** |
| `PyPromoteProcOverloadByKwAt` | ran **2843-3247** times, **retargeted 0** |
| `PyFixCallableTypeArgs` | ran 2843-3247 times (unconditional under `isNilPy`; whether it *does* anything is unmeasured) |

**The zero is not vacuous**: the enclosing `if isNilPy` was reached ~3000 times
per compile, so the population is large and the arms simply never applied. Every
hit came from a Pascal unit (`pyvartag`, `pyvarobj`, `pystr_of`, `IsOp`,
`MakeStr`, `SlotInt` — unit indices 56/61/435/442), none from NilPy source.

**And the retarget arm was tested against its own ticket's example.**
`bug-nilpy-keyword-arg-vs-overload-set` cites `html.escape(s, quote=False)`. That
program compiles, runs, matches CPython — and retargets **zero** times here,
because the call is parsed by `PyParseFactorCore`'s loop, which has its own
`PyBindKwArgs` (`pyparser.inc:49026`). The fix landed in the twin, and the copy
here was never the one doing the work.

## What to do, and why it is not "just delete it"

The likely fix is **deletion**, not a hook: the arms cost ~3000 no-op calls per
NilPy compile and close 19 of the carve's remaining sites for free. But
*"never fired in six programs"* is a sample. Before deleting:

1. Run the **full NilPy tier** with the arms replaced by `Error('unreachable')`.
   A green run is the evidence; six programs are not.
2. Check `PyFixCallableTypeArgs` separately — it is the one arm whose guard is
   bare `isNilPy`, so it always *runs*; the question is whether it ever *acts*.
3. `pasparser_stmt.inc`'s twin has the same arms and needs the same treatment.
   Its `PyPackStarArgs`/`PyBindKwArgs` pair is at `:6155-6156`.

If they are dead, the guard that should have been there is `PyExprMode`, and the
reason nobody noticed is that `isNilPy` reads as *"this is Python"* when it means
*"this compilation started from a .npy file"*. [[the-name-is-not-the-thing]].

## Related

- [[refactor-a-carve-the-nilpy-arms-out-of-the-shared-pascal-argument-loops]] — 19 of its sites are these
- `bug-nilpy-keyword-arg-vs-overload-set` — the ticket whose example does not reach this code

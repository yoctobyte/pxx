---
track: N
prio: 20
type: bug
blocked-by: []
summary: "`sum(*[xs])` is refused at compile time — the run-time *args forwarder rejects any callee parameter it cannot coerce a Variant to, and pylib's `sum(l: TPyList)` is one. Loud, but it refuses a valid CPython program."
status: done
owner: claude-A-N
---

# The star forwarder refuses a container-typed parameter

```python
print(sum(*[[1, 2]]))     # CPython 3
                          # pascal26:1: error: Nil Python: cannot forward *args into
                          #   sum — parameter l has a type no runtime argument can be
                          #   coerced to
```

Measured 2026-08-15, left behind by
[[bug-nilpy-star-unpack-into-a-fixed-arity-builtin]], which fixed the zip and
max/min halves of the same sweep.

Loud, and the message is accurate about the mechanism — but the program is
valid CPython, so this is a refusal of working code, the one direction NilPy's
upward-compatibility rule does not allow (`devdocs/dev/nilpy-semantics-divergences.md`).

## Cause

`PyStarForwardCall` reads each argument slot out of the forwarded list as a
Variant (`pystar_arg`) and binds it to the callee's parameter. A parameter whose
type has no coercion from a Variant — a `TPyList`, a `TPyDict`, any pylib
container — is refused rather than mis-bound, which was the right call when the
check was written.

The missing step is UNBOXING, which pylib already has: a Variant holding an
object is `pyvarobj` plus a class cast, exactly what `PyStarOperandAsList` does
for a star OPERAND. The forwarder wants the same conversion on the receiving
side, per parameter, driven by the parameter's declared class.

Worth checking at the same time whether a `str`-typed or `Integer`-typed
parameter takes the same path, and whether the refusal is reachable for a USER
def (it is written for pylib signatures, but nothing restricts it to them).

## Gate

`.npy` diffed against CPython: `sum(*[xs])`; `sorted(*[xs])`; a user def taking
a list, forwarded; a callee with a container parameter AND a scalar one; and a
control that the refusal still fires for a genuinely unbindable parameter rather
than mis-binding it.

## RESOLVED — the forwarder was refusing work the layer below already does

Two independent over-refusals, and the ticket only named the first.

**1. The coercion table duplicated `IRLowerCallArg` and lost.** The forwarder's
per-parameter table handled `tyVariant` and the string kinds and errored on
everything else. But a variant argument reaching a call is unboxed at LOWERING
time anyway — `IRLowerCallArg` does it for a scalar parameter
(`IRVariantUnboxKind`) and for a class parameter (tag-checked via
`pyvarobj_arg`, so a variant holding the wrong thing raises TypeError rather
than being dereferenced). That is precisely why the ordinary non-star
`sum(d["k"])` binds the same variant to the same `sum(l: TPyList)` without
complaint. The second path was the broken one, as usual.

Rather than growing the table, the fix asks the SAME question the lowering
asks: `IRVariantUnboxKind` moved from `ir.inc` to `symtab.inc` (it answers a
question about a type kind, so it had no business being IR-private, and
`parser.inc` is included before `ir.inc`), and the forwarder now passes the
variant straight through for anything the lowering can land. A private copy of
the kind list in `pyparser.inc` is exactly how the two answers would have
drifted.

**2. One unforwardable parameter was refusing the WHOLE call.** With the table
widened, `sorted(*[xs])` still failed — on `key`, a callable no variant can
become. But CPython's `sorted(*[xs])` supplies one argument and never reaches
`key`. The forwarder builds one call per accepted arity and dispatches on the
runtime count, so an unforwardable parameter only rules out the arities that
REACH it. It now caps the accepted arity (`fwdTotal`) instead of erroring, and
the existing `pystar_check_arity` guard reports a too-large count at run time
like any other wrong-arity forward. The compile error survives for the case that
is genuinely unforwardable — when even the REQUIRED arity cannot be built.

Both halves share one predicate, `PyStarParamTakesVariant`, so "which arities
can I build" cannot drift from "what do I emit for this parameter".

**Verified** against CPython, byte-identical: `sum(*[xs])`, `sorted(*[xs])`,
`len(*[xs])`, a float list, `"-".join(*[xs])`, a user def taking a list, a mixed
container+scalar callee (`two(*[[1,2], 10])`), and the gate's control — supplying
`sorted`'s `key` anyway now raises a catchable **TypeError at run time**, which
is what CPython raises for that same program, instead of refusing at compile
time. Rows added to `test/test_nilpy_star_forward.npy` with both Makefile
expectations updated. `tools/gate.sh quick` GREEN.

Note the FPC seed canary earned its keep here: moving the function left a stale
`forward` in `ir.inc` that `make compiler/pascal26` accepted and the seed build
did not ([[project_fpc_define_landmine]] territory —
`bug-a-fpc-seed-drift-emitasmx64-forward` is the same shape).

**Filed separately, NOT folded in:**
[[bug-nilpy-max-and-min-of-a-starred-list-pick-the-wrong-overload]] — `max(*[xs])`
returns the list instead of its largest element because the star path resolves
the callee to one `procIdx` before it knows the argument is a container, so it
binds the 2-argument overload. Reproduced identically on `pinned`, so it is
pre-existing and independent; the extended test deliberately stops short of it,
because a test that covers someone else's open bug goes red for a change that
did not cause it.

## Log
- 2026-08-15 — resolved, commit 11ee7dd0a.

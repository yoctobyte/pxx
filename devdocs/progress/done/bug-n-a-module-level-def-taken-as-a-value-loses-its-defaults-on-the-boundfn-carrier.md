---
track: N
prio: 65
type: bug
blocked-by: []
summary: "A module-level def taken as a value through a SUBSCRIPT or a PARAMETER is boxed on the tag-12 boundfn carrier, not the tag-8 pair, and that carrier's defaults machinery does not fire for it: `fs = [g]; fs[0](1)` on `def g(x, lo=7)` segfaults. The nested-def form of the same shape is correct, so it is the module-level arm that was left behind."
status: done
owner: frankonpiler-an
---

# A module-level def taken as a value loses its defaults on the boundfn carrier

```python
def g(x, lo=7):
    return lo

fs = [g]
print(fs[0](1))      # SIGSEGV        CPython: 7

def take(fn):
    return fn(1)
print(take(g))       # SIGSEGV        CPython: 7
```

Reproduces identically on `PXX_STABLE` — **pre-existing**, and it is the last
unfixed row of
[[bug-n-a-call-through-a-callable-value-drops-the-callees-defaults]].

## Measured

| shape | result |
| --- | --- |
| `f = g` then `f(1)` | correct (7) |
| `map(g, xs)` / `sorted(key=g)` | correct after `feature-n-a-callable-value-carries-its-signature-type` |
| `obj.method` as a value | correct |
| **`fs = [g]` then `fs[0](1)`** | **SIGSEGV** |
| **`take(g)` where `take` calls `fn(1)`** | **SIGSEGV** |
| a NESTED def with a default, same shape | **correct** (`6 101`) |
| all arguments supplied, any shape | correct |

Every arity of the omission fails (0→1, 1→2, 2→3, 3→4), so it is not
arity-specific.

## Root cause, measured not reasoned

The two failing shapes do **not** carry the tag-8 `{code, recv}` pair. A probe
on `pyvar_callv1` prints `tag=12` — `VT_CALLABLE_TAG`. Per
`PyBoxCallableValue` (`compiler/pyparser.inc:11775`) that tag is produced only
for a `pyclosure_src_*` / `pyboundfn_*` construction, so these values come from
`PyNestedDefClosureValue` and ride the **boundfn** carrier.

`pyvar_callv1` routes tag 8 to `pybound_callv1` — which now fills defaults from
the signature record — but a tag-12 value falls past that arm to
`pyboundfn_callvn`, or ultimately to the bare-code path
`f1 := TPyCallFn1(payload); Result := f1(a0)`. Calling a two-parameter body
through a one-parameter pointer is the segfault.

**The boundfn carrier has its OWN defaults mechanism** —
`pyboundfn_setdefaults`, emitted at `pyparser.inc:9158` (and the lambda
lifter's twin at 8565), which binds defaulted parameters as capture slots and
records `nOwn`/`nDef` so a supplied argument wins. It works for the NESTED def
form, which is what it was built for. It does not fire for a MODULE-LEVEL def
taken as a value — the sibling arm, left behind exactly the way that site's own
comment says the lambda lifter's twin was.

## Which way to fix it

This is a **`root-cause-over-microfix` / count-the-mechanisms** call, and the
count is now FOUR dispatchers for one concept: `pybound_callv*`,
`pycallback_call*`, `PyCallKey1`, and `pyvar_callv*` — plus **two** independent
defaults mechanisms, the signature record (tag 8) and `pyboundfn_setdefaults`
(tag 12). Two is a smell, and this is worse.

The narrow fix is to make the module-level arm emit `pyboundfn_setdefaults`
like the nested arm does. The deeper one is to give the boundfn carrier the
same `Sig` pointer the pair now carries and delete `pyboundfn_setdefaults`
entirely, so ONE mechanism answers "what are this callee's defaults" for every
carrier. The second is probably the smaller job — it removes a bitmask, a
capture-slot convention and a whole set of `setdefaults`/`setstar` calls — but
measure before committing to it.

Diagnosis banked rather than microfixed, per
`devdocs/dev/root-cause-over-microfix.md`.

## Provenance

Found 2026-08-19 by frankonpiler-an while widening the repro for
`feature-n-a-callable-value-carries-its-signature-type`. Binary: a self-hosted
fixedpoint at `d95ba7bc0` plus the tag-8 dispatcher work; the same shapes fail
on `stable_linux_amd64/default/pinned`, which is what establishes it as
pre-existing rather than introduced.

`PXXDBG=n.procs` (added in the same session) is what identified `pyvar_callv1`
as the real call site — the IR dump prints only `call a=1508`.


---

## FIXED — and MY OWN ROOT CAUSE ABOVE WAS WRONG. It is not the boundfn carrier.

The title and the diagnosis in this ticket are mine, and both were wrong. I read
`pyvartag(cb) = 12` as "the boundfn carrier" because `PyBoxCallableValue` is the
producer of tag 12 that I had read. It is not the only one.

Probes on the actual failing program, gated behind `PXXDBG=n.bfn`:

* `PyNestedDefClosureValue` — **never reached**.
* `PyBoxCallableValue` — **never reached**.
* `PyMakeFuncValueFor` — reached for `f = g`, **never** for `fs = [g]`.

So the value is not on the boundfn carrier at all. It is a bare `IR_PROCADDR`
retagged `VT_CALLABLE` by the IR-level boxing (`compiler/ir.inc` ~4358), whose
own comment says exactly what that means: *"the payload is callable and the slot
does not own it"* — a code address and nothing else.

### The real cause: a sibling arm listing one reason out of two

`compiler/parser.inc`, the bare-def-name-in-a-value-position arm:

```pascal
if (idx >= 0) and (idx < ProcCount) and (ProcPyStarIdx[idx] >= 0) then
  node := PyMakeFuncValueFor(idx, name);      { else: bare AN_PROCADDR }
```

The pair road was taken for a `*args` callee only. Its comment explains why —
*"a callee that COLLECTS cannot travel as a bare address: the packing is work
the CALL SITE does, and an address carries nothing that says so. The {code,
recv} pair does"* — and that argument now applies word for word to a callee with
DEFAULTS, because the pair carries the signature record. One concept ("this
callee cannot travel as a bare address") expressed as a list of reasons, with
only the first reason listed: `normalise-dont-special-case` exactly.

Fix: `(ProcPyStarIdx[idx] >= 0) or PyProcHasDefaultParam(idx)`.

### A second, latent bug the fix exposed — and the loud sentinel earned its keep

With defaulted callees now taking the pair road, the wired test failed with
`TypeError: parameter 2 has no recorded default (signature slot never filled)`
on an ordinary `def r(a, i=7, s="hi", L=None)`.

`PXXDBG=n.sig` showed `r.s` and `outer.inner.b` — unrelated parameters in
unrelated defs — **both reporting symbol 451**. A rolled-back trial parse frees
a symbol index and a later def's parameter gets it, so `ProcParamDefaultSym` is
not a safe key for anything outside the parse that wrote it. The two collided on
one pending-slot entry, the second overwrote the first, and `r.s`'s def-time
store went to the bit bucket.

Fixed by carrying the qualified NAME from where it is authoritative — captured
at the header parse into `PyHdrDefGName`, propagated to
`ProcParamDefaultGName` at all four registration sites, and used as the pend key
in place of the symbol. Same recycled-index landmine as
[[bug-nilpy-a-nested-defs-default-parameter-is-read-from-a-rolled-back-symbol]],
one level up.

**This is the payoff for choosing a loud sentinel over zero.** `PYSIG_DFLT_UNSET`
is -1 because 0 would be `VT_EMPTY`, which is None — and a slot silently
answering `None` for `s="hi"` is a plausible wrong value that would have shipped.
Instead it raised, named the parameter, and the probe found a symbol-recycling
bug in one step.

### Verified against CPython

Wired test extended and byte-identical: a defaulted def reached through a LIST
ELEMENT, through a PARAMETER, and through `map`, with int/str/None defaults, a
keyword argument through a list element, and the shared-mutable-default
accumulator reached both ways. `map` over a two-parameter defaulted def was
**silently wrong** before this (`[1,2,3]` where CPython says `[2,3,4]`) and is
now correct.

### Retitle

The slug says "on the boundfn carrier" and that is false. Recorded here rather
than renamed, so the wrong diagnosis stays findable next to its correction —
this file is the evidence for how the mistake was made, and renaming it would
hide that.

**The Track A consolidation is unaffected.** Four dispatchers and two defaults
mechanisms is still the count, and `pyboundfn_setdefaults` is still the
duplicate to delete. This bug simply was not an instance of it.

## Log
- 2026-08-19 — resolved, commit e360f0c5c.

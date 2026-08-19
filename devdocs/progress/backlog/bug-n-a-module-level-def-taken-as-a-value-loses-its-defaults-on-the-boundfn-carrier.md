---
track: N
prio: 65
type: bug
blocked-by: []
summary: "A module-level def taken as a value through a SUBSCRIPT or a PARAMETER is boxed on the tag-12 boundfn carrier, not the tag-8 pair, and that carrier's defaults machinery does not fire for it: `fs = [g]; fs[0](1)` on `def g(x, lo=7)` segfaults. The nested-def form of the same shape is correct, so it is the module-level arm that was left behind."
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

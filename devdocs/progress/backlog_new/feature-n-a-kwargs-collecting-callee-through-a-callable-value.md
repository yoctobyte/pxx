---
track: N
prio: 55
type: feature
blocked-by: []
summary: "A callee that collects `**kwargs` cannot be called through a callable value at all — every shape raises TypeError, including `def f(a, **kw)` called as `zz(1)` with no defaults anywhere. The dynamic bridge has no way to synthesize the empty dict the body expects in the collector slot, so the collector is deliberately left counted in ReqN to make the call REFUSE loudly rather than dispatch at an arity the body does not have. Split out of the *args fix; that half is done and CPython-exact."
status: backlog
owner: unassigned
---

# A `**kwargs`-collecting callee reached through a callable value

- **Type:** feature (a missing capability, not a regression) — **Track N**.
- **Split out of** [[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]]
  when its `*args` half was fixed. That half is now CPython-exact; this half was
  never implemented.
- **Loud, not silent.** Every failing shape raises a `TypeError` and exits 217.
  Nothing here returns a wrong value, which is why it ranks below the bug it came
  from rather than beside it.

## Measured at HEAD (self-host fixedpoint, after the `*args` fix)

| shape | pxx | CPython |
| --- | --- | --- |
| `def f(a, **kw)` … `zz = f; zz(1)` | `TypeError: missing 1 required positional argument(s)` | `1` |
| `def f(a, lo=7, **kw)` … `zz(1)` | `TypeError: missing 1 required positional argument(s)` | `8` |
| `def f(a, lo=7, **kw)` … `zz(1, 2)` | `TypeError: parameter 2 has no recorded default` | `3` |
| `def f(a, lo=7, *rest, **kw)` … `zz(1)` | `TypeError: missing 2 required positional argument(s)` | `8` |

Note the first row: **no default is involved anywhere.** So this is not "a default
is dropped" wearing a different hat — a `**kwargs` collector simply cannot be
reached through a callable value.

## Why it fails, and why the current refusal is deliberate

`EmitPySignatures` (`compiler/rtti_emit.inc`) records `ReqN`/`TotN` over the
callee's declared parameters. A collector has no default, so it counted as
*required* — which is what produces the messages above.

The `*args` fix strips a **trailing star** collector from both counts, and
deliberately **does not strip a `**kwargs` one**. That is not timidity: the
runtime bridge (`PyBoundCallV2` in `compiler/builtin/pylib.pas`) has no way to
build the empty `TPyDict` the body expects in that slot. Uncounting the collector
without supplying the dict would turn today's loud `TypeError` into a dispatch at
an arity the body does not have — i.e. **a segfault**. The refusal is the safe
state, and the comment at both ends says so.

The last row is worth calling out: it used to be an actual **SIGSEGV** (rc=139),
and the same change made it a `TypeError`. Strictly better, still not right.

## What building it takes

Both halves, or neither:

1. **Uncount the trailing `**kwargs` collector** in `EmitPySignatures`, the same
   way the star one now is (scan from the end, so the `Dflts`/`Names` indices
   that follow are unchanged by construction).
2. **Supply the dict at dispatch.** The bridge must construct an empty `TPyDict`
   and pass it at the collector's index — mirroring what `PyPackStarArgs` already
   does at a *written* call site (`if ki >= 0 then … PyNewContainerTemp('TPyDict',
   'kwargs')`). The compile-time path is the model to copy; do not invent a second
   notion of what the collector slot holds.

The awkward part is that the bridge does not currently know the collector's
index: `TPyBoundRec` carries `StarIdx` but no `KwIdx`, and the signature record's
one spare word (`PYSIG_OFF_STAR`) already means the star position. Both carriers
are Track N files, so adding the field is in-lane — **but check first whether it
belongs in the signature record rather than the box**, since
`refactor-a-one-signature-record-for-every-callable-carrier` already pushed in the
direction of one record answering every signature question, and a second copy of
"where does this callee collect" is exactly the drift that refactor removed.

A real keyword argument arriving for a `**kwargs` callee (`zz(1, extra=2)`) is
the same job once the dict exists: today `PySigFindParam` misses the name and
raises `unexpected keyword argument`, which is the wrong message for a callee
that would have taken it.

## Accepted neighbouring limit, recorded so it is not re-diagnosed

The bridge packs **at most four arguments**, so a star at position 4 or beyond is
refused with a message of its own (`…is past what the dynamic bridge can pack`).
That is a separate, pre-existing, loud ceiling — not part of this ticket.

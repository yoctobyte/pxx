---
track: N
prio: 88
type: bug
blocked-by: []
summary: "A call through a module-level function ALIAS that omits a defaulted parameter segfaults at runtime, with no diagnostic at compile time. `f = g` then `f(a, b)` where g is `def g(a, b, lo=0, hi=-1)` crashes; the same call with all four arguments supplied is fine, and calling `g` directly with the defaults omitted is fine. Six-line repro, no imports involved."
status: done
owner: frank1-N-alias
---

# Calling through a function alias with a default omitted segfaults

- **Type:** bug — **Track N** (Nil-Python frontend / lowering).
- **Found:** 2026-08-18 by frank3-fc, while writing `lib/rtl/mimic_bisect.py`
  for [[feature-b-module-shims-for-the-html5lib-corpus]].
- **Measured against:** `pinned` **v347** (`f5da30bc9`).
- **CPython accepts and runs this**, so it is a defect and not a dialect
  choice — `bisect = bisect_right` is a line in CPython's own `Lib/bisect.py`.

## Repro

Six lines, one file, no imports:

```python
def real(a, x, lo=0, hi=-1):
    if hi < 0:
        hi = len(a)
    return hi - lo

ali = real
print(ali([1, 2, 2, 3], 2))
```

```
$ pinned t.npy /tmp/t && /tmp/t
ok: /tmp/t  [code=2335086B ...]
Segmentation fault (core dumped)
```

It **compiles clean** — no warning, no note. CPython prints `4`.

## The boundary, one variable at a time

| shape | result |
| --- | --- |
| `ali([1,2,2,3], 2)` — alias, defaults omitted | **segfault** |
| `ali([1,2,2,3], 2, 0, 4)` — alias, defaults supplied | 4 (correct) |
| `real([1,2,2,3], 2)` — direct, defaults omitted | 4 (correct) |
| alias of a function with **no** defaulted parameters | correct |
| same, with the alias in an imported module (`from m import ali`) | **segfault** |
| same, all in one file, no import at all | **segfault** |

So it is neither about imports nor about aliases generally: it is specifically
**an alias plus an omitted default**. The reading that fits every row is that
the alias binds the callee's entry point but not its default-argument
metadata, so the call site passes 2 arguments to a body that reads 4 and the
missing two are whatever the stack held. That paragraph is a hypothesis, not a
measurement — nothing here inspected the lowering.

## Why this is worth a p65

It is a **crash with no diagnostic**, and the shape is not exotic: aliasing a
function is how Python modules ship legacy spellings, and defaulted parameters
are how they ship optional arguments. `bisect` is precisely both at once, which
is how this was found — the stdlib module the corpus imports has
`bisect = bisect_right` in it.

Worse, the two ingredients are separately fine, so a caller who tests the alias
with all arguments supplied sees it work and concludes the alias is sound.

## Effect on Track B today

`lib/rtl/mimic_bisect.py` ships the platonic `bisect = bisect_right` and
`insort = insort_right` aliases (they are part of the module's real API).
`test/lib_mimic_bisect.npy` therefore exercises them only with every argument
supplied, and says so at the call site. When this lands, drop that restriction
and let the test call `bisect(r, 2)` the way a caller would.

---

## Coordinator verification 2026-08-18 — the segfault is the LUCKY case. Silent wrong values.

Verified at **HEAD** (`bd047aba6`, self-host fixedpoint) as well as pinned v347, so this
is not pin-only: the six-line repro segfaults on both. But varying the shape moved the
boundary somewhere much worse than the title says.

**The trigger is not "a default is omitted". It is "an omitted default is READ".**

| shape (alias call, args omitted) | result |
| --- | --- |
| 1 default, omitted, **not used** in body | ok |
| 2 defaults, omitted, **not used** in body | ok |
| 1 default, omitted, **read** in body | **returns 3 where the direct call returns 1** |
| 2 defaults, omitted, **read** in body | **SIGSEGV** |
| all arguments supplied (alias) | ok |
| defaults omitted, called **directly** (no alias) | ok |

The third row is the important one and it is not in the ticket above:

```python
def r(a, x, lo=0):
    return lo + 1

ali = r
print(ali([1, 2], 2))   # alias  -> 3      WRONG
print(r([1, 2], 2))     # direct -> 1      correct (CPython: 1)
```

**Exit 0, no diagnostic, plausible number.** So the defaulted parameter's value is never
materialised at the alias call site and the body reads whatever occupies the slot. With
one default the garbage happens to be arithmetically usable and you get a wrong answer;
with two, it is dereferenced and you get the crash. **The crash is the detectable case.**

This is the failure mode this repo treats as the expensive one — a plausible wrong value
far from the cause — so re-prioritised **65 → 70**. A segfault stops a build; this
silently changes results. `bisect_left` vs `bisect_right` on a run of equal elements is
exactly a "lo/hi defaulted and read" shape, and getting a wrong index back rather than a
crash is how it would reach a caller.

**Do not close this on the segfault alone.** The regression test must assert the
RETURNED VALUE of an alias call that omits a read default, against the direct call's
value — a test that only checks "does not crash" passes on the one-default shape while
it is still wrong.

Found by varying the shape after a simpler four-line version of the reported repro
PASSED — worth recording, because that near-miss would have read as "cannot reproduce"
and bounced the ticket.

## RE-SCOPED 2026-08-18 (frank2-7e) — not about imports, and not about aliases

Measured at HEAD after
[[bug-n-a-default-argument-is-dropped-on-every-cross-module-call]] landed
(`3d66bdff7`). That fix was expected to retire this ticket. **It does not**, and
the rows below say why the title is aiming at the wrong thing.

| shape | pxx | CPython |
| --- | --- | --- |
| `from M import f as zz; zz(1)` | (empty / garbage) | 7 |
| `from M import g as qq; qq(1)` (two defaults) | no output at all | 16 |
| `from M import f as zz; zz(1, 5)` | 5 | 5 |
| **`def loc(a, lo=7): ...` then `zz = loc; zz(1)`** | (empty) | **7** |

The last row is the point: **one file, no import, no alias syntax** — a plain
assignment of a function to a name. It fails identically. So the defect is
*calling through a function-VALUED name*: the call does not consult the callee's
declared defaults, because at that point the target is a procedural value rather
than a known proc. Supplying every argument is correct, which is what keeps it
invisible.

So this ticket's scope is **calls through a procedural value drop parameter
defaults**, and `from X import f as g` is one way to reach it, not the cause.
Retitling is left to whoever takes it, per the same convention applied to
[[feature-nilpy-yield-outside-a-for-loop]].

**Do not read this ticket's own repro as still current either.** It uses a
COLLIDING alias name, and that shape is a different defect again —
[[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]]
(N, p85): the alias binds to the source module's own same-named member, which is
wrong with every argument supplied and no default in play. That is very likely
the actual cause of the SEGFAULT recorded here, since the call lands on a
different function with a different signature — a better explanation than a
dereferenced dropped default.

Three defects were entangled under this one ticket. Two are now separated and
one (the cross-module default) is fixed; what remains here is the third.

## Reranked 70 -> 88 by the coordinator, 2026-08-18 — the re-scope widened it past the p85

Rank follows the measured scope, and the re-scope changed what this ticket IS. It was
filed as an alias bug, then found to need neither an alias nor an import:

```python
def loc(a, lo=7):
    return lo
zz = loc
print(zz(1))     # pxx: '' (empty/None)   CPython: 7
```

Verified by the coordinator at HEAD `8705aea7a`, after the cross-module fix landed. One
file, no import, no alias syntax. **A call through a procedural VALUE does not consult
the callee's defaults.**

That is a broader population than
[[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]] (p85), which
needs an alias name that collides with a member of the source module. A procedural value
is how Python spells callbacks, dispatch tables, sort keys, decorators and any
`handlers[k](x)` — all of which are ordinary, and all of which silently lose their
defaults here. So this outranks the collision on population even though the collision was
found second and filed higher.

Both are silent. Neither is retired by the cross-module fix
(`bug-n-a-default-argument-is-dropped-on-every-cross-module-call`) — that was the
coordinator's error, corrected on measurement rather than on argument.

**Title is still the filed one and is now wrong twice over** — it names aliases and
segfaults, and the defect is neither. Retitle left to whoever takes it, same convention
as the yield ticket, but do not size this from its title.

## DIAGNOSED 2026-08-18 (frank2-7e) — banked and escalated, NOT microfixed

Measured at HEAD `61c9f0b87`, self-host fixedpoint, differential against CPython.

### It is not defaults — the whole signature is bypassed

Calling through a procedural value consults **nothing** about the callee:

| | direct call | through a procedural value |
| --- | --- | --- |
| omitted default | filled correctly | **dropped** (empty/garbage) or **SIGSEGV** |
| too FEW args | compile error | **no error**, runs on garbage |
| too MANY args | compile error | **no error**, wrong answer (`zz(1,2,3)` → 2) |

CPython raises `TypeError` for both arity rows. So "a default is dropped" is one
visible face of "the call site knows nothing about the callee".

### Severity is worse than the title: ordinary callback shapes CRASH

| shape | result |
| --- | --- |
| `zz = loc; zz(1)` (same file, no import) | wrong value, exit 0 |
| `handlers = [loc]; handlers[0](1)` | **SIGSEGV** |
| `d = {"x": loc}; d["x"](1)` | **SIGSEGV** |
| `def call(fn): return fn(1)` — a function passed as an ARGUMENT | **SIGSEGV** |
| `cb = k.m` — a BOUND METHOD as a callback | **SIGSEGV** |
| `g = lambda a, lo=7: lo; g(1)` | **correct** |

Dispatch tables, handler lists and callback parameters are how Python is written.

### Root cause, and the lambda row is the discriminator

A compiled `def` reaching a variant is boxed as **VT_CALLABLE_TAG (12): a bare
CODE ADDRESS** (`defs.inc`). An address carries no arity and no defaults, so the
call site has nothing to fill from and nothing to check against — it jumps with
whatever arguments were written and the callee reads its remaining parameter
slots off the stack.

A **lambda works** because it takes the other path: an owned callable object
(`pyvar_of_callable` → VT_PYCLOSURE/VT_BOUNDFN), and `TPyClosure` already carries
`ReqN..TotN`, *"the legal argument-count RANGE"* (`pyeval.pas`). The information
this bug needs already exists — for one of the two representations.

**That is the shape of the defect: two mechanisms for one concept**, and the one
that carries the signature is the one nobody hit.

### Why this is escalated rather than fixed here

The obvious fix — route a compiled `def` through the same owned-callable
representation as a lambda — is a **lifetime change**, and `defs.inc` says the
bare-address form was chosen deliberately for exactly that reason: *"the slot
does NOT own it, which is why this tag stays out of the variant clear/retain
object-tag lists: that is the lifetime these values already had while they wore
VT_INT64."* Getting ownership wrong here produces leaks or double-frees, which
are silent.

And the tempting narrow fix is a trap of the kind that already bit this repo
today. Resolving the target statically (`zz = loc`) would fix the assignment row
and leave `handlers[0](1)`, the dict table, the callback parameter and the bound
method **still segfaulting** — a passing test certifying a hole, which is exactly
what the `CodecInfo` probe stopped a few hours ago.

So: diagnosis banked, decision escalated as
[[decide-how-a-compiled-def-carries-its-signature-when-boxed]] (Track U).
**Not microfixed as a consolation.**

**Recommendation** (in the decision ticket): give the callable value its
signature rather than teach the call site to guess — the lambda path proves the
representation exists and works. The open question is ownership, not design.

### Retitling

The title still says "calling through a function alias" and is wrong twice over:
not aliases, not imports. Left for whoever takes the decision, per the convention
already applied to [[feature-nilpy-yield-outside-a-for-loop]].

---

## FIXED 2026-08-25 (frank1-N-alias) — and the banked diagnosis was right about the design, wrong about what was left

Measured at HEAD, self-host fixedpoint, differentially against CPython.

### First: everything this ticket originally reported is already GREEN

The Track A build that came out of the decision —
[[feature-n-a-callable-value-carries-its-signature-type]], the `VT_CALLABLE_TAG`
payload becoming a static signature record — retired the whole population the
ticket and its three re-scopes recorded. Re-measured, every row now matches
CPython exactly:

| shape | before | now |
| --- | --- | --- |
| `ali = real; ali([1,2,2,3], 2)` (the filed six-line repro) | SIGSEGV | `4` |
| `zz = loc; zz(1)` (one file, no import, no alias) | empty/garbage | `7` |
| `handlers = [loc]; handlers[0](1)` | SIGSEGV | `7` |
| `d = {"x": loc}; d["x"](1)` | SIGSEGV | `7` |
| `def call(fn): return fn(1)` | SIGSEGV | `7` |
| `cb = k.m` (bound method) | SIGSEGV | `7` |
| keyword through a value, shared mutable default, non-constant default | — | all CPython-exact |

So this could have been closed as done-by-a-sibling. **Varying the shape further
is what stopped that**, and it found a live arm of the same defect that no
re-scope had reached.

### The arm that was still broken: a callee that COLLECTS

The signature record is consulted for a plain `def`. It is **not** consulted for
a callee with `*args`, because the dynamic bridge had a second dispatch path that
ran *before* the signature preamble and returned:

```pascal
{ a COLLECTING callee packs its own surplus and has no omitted parameters to
  fill -- that path predates this one and stays exactly as it was }
if b^.StarIdx >= 0 then
begin
  ...
  Result := PyBoundCallStar(...);
  Exit;
end;
```

**That comment is false**, and the falseness is the bug: `def f(a, lo=7, *rest)`
has both a collector *and* an omitted default. Measured before the fix:

| shape | pxx | CPython |
| --- | --- | --- |
| `def va(a, lo=7, *rest)` … `zz(1)` | `1` | `8` |
| `def st2(a, lo=7, hi=8, *rest)` … `ww(1)` | `1` | `16` |
| `def st2(...)` … `ww(1, 2)` | `3` | `11` |
| `def both(a, lo=7, *rest, **kw)` … `zz(1)` | **rc=139, SIGSEGV** | `8` |
| `def st(a, *rest)` (no defaults) … `zz(1)` | `1` | `1` (already fine) |

**Silent wrong values again, and a live segfault** — the exact failure shape this
ticket exists for, in the one population every earlier pass had waved through.
It survived because the shape that got probed (`def star(a, *rest)`, no defaults)
is precisely the shape for which the false comment happens to be true. That test
is in the tree, `test_nilpy_callable_value_defaults.npy`, carrying the same
sentence as its comment — the claim and its only witness reinforcing each other.

### Root cause, measured with `PXXDBG=n.sig` rather than reasoned

Two defects, one concept:

**1. `EmitPySignatures` counted the collector as an ordinary parameter.**
`PXXDBG=n.sig` on `def va(a, lo=7, *rest)` printed `nUser=3 reqN=2` where the
truth is `TotN=2 ReqN=1` — `rest` has no default, so the "params with no default"
loop counted it as *required*. Every consumer that trusts those numbers was
therefore wrong about the same def.

**2. The bridge had two paths and only one consulted the signature.** Exactly
the double case in `devdocs/dev/normalise-dont-special-case.md`: the second path
is the one that stays broken. It skipped default-filling, arity checking *and*
keyword matching (the last was an explicit `not supported yet` raise).

### The fix — delete the second path, do not extend it

- `compiler/rtti_emit.inc`: strip a **trailing `*args`** collector from `ReqN`
  and `TotN`. Scanned from the END on purpose — `Dflts` and `Names` are indexed
  by `(k - firstUser)`, so removing only a suffix leaves every surviving index
  correct *by construction* rather than by care.
- `compiler/builtin/pylib.pas`: the star early-out is **gone**. Keyword matching,
  the arity check and the default fill are now the ONE path every callable value
  takes; star-ness is a calling convention that affects only the final dispatch.
  Packing is bounded by `nPos`, not `want`, so a filled default never leaks into
  the tuple.

Result: every star shape above now matches CPython, **and keyword arguments
through a star callee work** (`ww(1, hi=3)`), which the old path refused outright.

### What was deliberately NOT fixed, and why it is not a consolation microfix

A `**kwargs` collector is still counted in `ReqN`. That is load-bearing: the
bridge cannot synthesize the empty `TPyDict` the body expects in that slot, so
uncounting it without supplying the dict would convert today's loud `TypeError`
into a dispatch at an arity the body does not have — **a segfault**. The refusal
is the safe state and both ends say so in comments.

Net effect on the `**kwargs` population: unchanged where it was already loud,
and the `def both(a, lo=7, *rest, **kw)` case went from **SIGSEGV to TypeError**.
Filed as [[feature-n-a-kwargs-collecting-callee-through-a-callable-value]] with
the two-part build it needs. It is a genuinely missing capability, not this bug —
it fails with **no defaults anywhere** (`def f(a, **kw)` called as `zz(1)`).

### Regression test

`test/test_nilpy_callable_value_defaults_with_star_args.npy` + `.expected`, wired
into the Makefile beside its sibling. Every line prints the **direct call's value
beside the value reached through the callable value** — the ticket's own
instruction, because a test that only checks "does not crash" passes on the
one-default shape while it is still silently wrong. Its `.expected` was generated
from **CPython** and pxx's output diffs clean against it.

The false comment in `test_nilpy_callable_value_defaults.npy` is corrected in
place, and now points at the general case rather than restating the claim that
licensed the bug.

### Found on the way, filed, not fixed here

[[bug-n-a-resolved-module-member-as-a-value-is-an-undefined-variable]] — `m.f(1)`
compiles and runs, `h = m.f` is a compile error `undefined variable (f)`. Shares
its message with the unresolved-import ticket but has the opposite cause (the
import resolves fine). Compile-time, so it never reaches this bug's territory.

### Retitling

Left as filed, per the convention this ticket already invoked twice. For the
record the title is now wrong three ways: not aliases, not imports, and — for the
part that was actually still broken — not defaults alone but defaults **plus a
collector**.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.

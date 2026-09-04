---
track: N
prio: 40
type: bug
blocked-by: []
status: backlog
summary: "A NilPy `except V as e:` handler that binds X and is then unwound past by a DIFFERENT exception Y leaks X: 3.889 blocks per iteration, against 4.862 on pin v403 and a hypothetical ~0.9 if the pad released X. The unwind landing pad deliberately skips every handler binder, because it cannot tell X from an object that is IN FLIGHT (releasing that one is a use-after-free -- the SIGSEGV bug-nilpy-a-managed-local-in-an-unwound-frame-is-never-released fixed). The skip is the conservative half of a distinction the pad cannot currently make."
---

# A handler binder unwound past by a *different* exception still leaks

## What is conservative, and why it was made conservative

The unwind landing pad releases a frame's managed locals. A NilPy
`except V as e:` binder is a managed local and the pad skips it
unconditionally (`SymSkipScopeExitRelease`, `symtab.inc`), because on that path
the binder may hold the object currently IN FLIGHT — and releasing that is a
use-after-free, measured as a SIGSEGV.

But there are two cases and the pad cannot tell them apart:

| the handler | binder holds | releasing it is |
| --- | --- | --- |
| `raise` / `raise e` | the in-flight object | **a use-after-free** |
| `raise Other(..)`, or a callee raises | an object nothing else references | **correct, and the drop** |

Row two is skipped along with row one, so its object leaks.

## Measured 2026-09-04, `-dPXX_ALLOC_CENSUS`, slope N=2000 → N=8000

```python
def boom(k):    raise KeyError("k" + str(k))
def holder(k):
    try:                 raise ValueError("old" + str(k))
    except ValueError as e:  boom(k)
```
driven by an outer bare `except KeyError:` arm:

| binary | per iteration |
| --- | --- |
| pin v403 (no pad at all) | 4.862 |
| HEAD (pad, binder skipped) | **3.889** |
| a pad that released the binder | ~0.9, and it segfaults on a re-raise |

So HEAD is strictly better than the pin here and still ~3 blocks short of what
the pad could reclaim — the ValueError object plus the two blocks it owns.

## What a real fix looks like

Ask, at the pad, whether the slot holds the in-flight object, and release only
when it does not. The comparison is against `BSS_EXC_OBJ`. What makes it more
than a one-liner is that the release arm has **six copies** — `symtab.inc` for
x86-64 and five in `ir_codegen.inc` — so it is a compare-and-branch emitted six
times, and the reason it was not done under the SIGSEGV was time, not doubt.

An alternative worth costing first: a runtime `PXXObjReleaseUnwind(p, inflight)`
taking the in-flight pointer as a second argument, so the branch lives in
`builtinheap.pas` once and each backend only marshals one more register. That
trades six branch emissions for six argument setups, which may not be a win —
measure before choosing.

**Do not "fix" this by narrowing the skip to bare `raise` and `raise e`.** Both
were measured to crash and both are reachable, but so is any expression that
happens to evaluate to the bound object, and a syntactic test would pass every
probe anyone thinks to write while still crashing on the one nobody did.

## Not this

[[bug-nilpy-except-x-as-e-still-leaks-every-exception-the-bare-arm-fix-did-not-cover-it]]
is the NORMAL path — 2.997 blocks per catch with no unwind involved at all, and
it is the bigger number. This ticket is only about the unwind path.

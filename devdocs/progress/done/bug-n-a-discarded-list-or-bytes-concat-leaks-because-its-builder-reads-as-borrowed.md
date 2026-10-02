---
type: bug
track: N
prio: 35
status: open
slug: bug-n-a-discarded-list-or-bytes-concat-leaks-because-its-builder-reads-as-borrowed
summary: "A bare expression statement `a + b` over lists, or `bv + b\"x\"` over bytes, leaks two objects per execution (live 13 -> 2013 over 1000 passes). `y = a + b` is flat. pylist_concat and pybytes_concat build `r := Create; r.put(...); Result := r`, and ClassifyProcResultFresh calls that borrowed, because LocalUseEscapes counts any method call on the local as an escape. So the discard binder does not release the result."
---

# A discarded list or bytes concat leaks because its builder reads as borrowed

Measured 2026-10-02 (frankuser), x86-64, census at N=1 and N=1001:

| statement in a loop | live |
| --- | --- |
| `y = bv + b"z"` | 11 -> 11 |
| `bv + b"x"` | 13 -> 2013 |
| `y = a + b` | 11 -> 11 |
| `a + b` | 13 -> 2013 |

`PXXDBG=p.fresh:*` reports `pylist_concat FALSE arg=-1` and
`pybytes_concat FALSE arg=-1`. Both bodies return a local built by
`Create` and filled with `r.put(i, ...)`. The rule in LocalUseEscapes is
deliberately conservative: a method call on the local may keep Self.

## Shape of a fix

Per-method "Self does not escape": run LocalUseEscapes over a method's own
body with Self as the local, and record the verdict per proc. Methods
compile before their callers within pylib, so a later
ClassifyProcResultFresh can treat `r.m(...)` as harmless when m's verdict is
"does not escape". `put`, `append`, `at` and the like qualify. Anything with a
cast or a store of Self stays an escape. This widens what the discard binder
releases, so it needs a tier and a HEAP_DEBUG sweep, not just this repro.

Low priority: a bare `a + b` statement is rare in real code. The lambda
`return` of the same value, which used to give None, was fixed separately
(bug-n-a-lambda-returning-a-captured-heap-value-yields-none).

## Fixed 2026-10-02

Generalised past the shape above: ProcParamStays is a per-routine bitmask of
class-typed VALUE parameters (Self is parameter 0) whose body never lets them
out, judged by LocalUseEscapes with `Result := p` / `Exit(p)` counted as
escapes. A STATIC call handed a local bare in a slot whose bit is set no
longer counts as an escape of that local; a virtual call still does. Two
supporting changes: `p = nil` / `p <> q` is not an escape (PySeqIndexError
compared its list to nil), and TPyList.append no longer routes through
append_self, which returns Self -- both now call PyListAppendRaw.

Verdicts that changed to fresh (x86-64, a program importing the common
modules): pylist_concat/repeat/slice/slice_step, pybytes_concat/repeat,
pyenumerate(2), pyzip, pymap_int/float/str, pysys_argv, PySelectReady,
pyselect_select, TPyDict.itemlist/most_common, getaddrinfo, socket.read/
readline, DecodeAt, struct unpack/unpack_from. Each builds and returns a new
object.

test/test_nilpy_a_discarded_concat_slice_or_repeat_is_released.npy: 75373
live after 5000 passes at v452, 59 after. HEAP_DEBUG and i386 rows diff
against CPython.

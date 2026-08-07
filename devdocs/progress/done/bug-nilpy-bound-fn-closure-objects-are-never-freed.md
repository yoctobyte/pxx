---
track: N
prio: 55
type: bug
status: done
owner: claude-AN
---

# Every escaping closure leaks its bound-fn object — 320k closures cost 125 MB

```python
def mk():
    L = [1, 2, 3]
    def b():
        return len(L)
    return b

for i in range(n):        # spelled as a while loop in NilPy
    f = mk()
    f()
```

RSS grows linearly with the number of closures created and is never reclaimed.

## Measured — RSS slope, 20k vs 320k iterations

| program | 20 000 | 320 000 | per closure |
| --- | --- | --- | --- |
| closure capturing an **int** | 4 352 KB | 65 408 KB | ~200 B |
| closure capturing a **list** | 8 192 KB | 125 312 KB | ~390 B |
| the same body with NO closure (control) | 264 KB | 264 KB | flat |

The control is flat, so ordinary list/dict/object churn reclaims correctly —
this is specific to the closure object.

## Two contributors, and one of them is new

1. **`pyboundfn_new` GetMems a `TBoundFnObj` and nothing ever frees it.**
   Pre-existing — the int-capture row above uses no other allocation. The
   design note says so out loud, next to `pyboundfn_bind_var`'s heap slot:
   "leaked with it; markers are few". That assumption held while the only
   things reaching this path were uforth's MARKER/DOES> words.

2. **`pyboundfn_bind_obj` retains a class capture and never releases it** — the
   extra ~190 B in the list row. Added by
   [[bug-nilpy-escaping-closure-captures-unbound-unless-arity-is-one]], and
   deliberately so: without the retain the enclosing scope frees the object on
   return and the closure reads freed memory (it answered `len(L) == 0`).
   Retaining was the right call for correctness; it inherits the same missing
   destructor.

The honest framing is that fixing the closure ABI made this leak *reachable*.
Before, an escaping closure produced garbage, so nobody wrote loops that make
them. Now they work, so people will — and "markers are few" stops being true.

## Shape of a fix

The bound-fn object needs a lifetime. Options, roughly in order of effort:

- **Refcount it like any other managed object.** It is already a magic-tagged
  heap object that the variant machinery recognises (`pyboundfn_is`,
  `pycallable_obj_is`); giving it the ordinary retain/release path would also
  release each `Bound[]` entry that `pyboundfn_bind_obj` retained and each heap
  slot `pyboundfn_bind_var` allocated. This is the real fix.
- **Free the bound values with the object** once it has any destructor at all —
  the bind functions already know which slots are owning (`_bind_obj` retained,
  `_bind_var` allocated, plain `_bind` owns nothing), so the object could carry
  a small per-slot kind array.

Both need care: a closure's lifetime is genuinely dynamic (stored in a dict,
returned again, captured by another closure), so a naive "free at scope exit"
would reintroduce the dangling read that `_bind_obj` exists to prevent.

## Gate

`make test-nilpy` + self-host byte-identical, plus the RSS-slope table above:
the closure rows must go flat, and the control must stay flat. Measure with
`/usr/bin/time -f %M` at 20k and 320k — a single run proves nothing, the SLOPE
is the evidence. `test/test_nilpy_escaping_closure.npy` must stay
byte-identical to CPython (that is the test that the retain is still doing its
job).

## 2026-07-31 re-investigation — the "Two contributors" section above is STALE

Picked up as claude-N3. The leak is very real and still reproduces at the same
order of magnitude as the table above (measured 125 344 KB @ 320k for the
list-capture repro on a fresh self-host of current HEAD — matches the ticket's
125 312 KB almost exactly). **But the root cause this ticket names
(`pyboundfn_new` / `TBoundFnObj` / `pyboundfn_bind_obj`, all in
`compiler/builtin/pyeval.pas`) is not what the ticket's own repro exercises.**
Shipping the "give `TBoundFnObj` a destructor" fix described above would add a
correct destructor to a family of objects that this repro never allocates, and
would leave the actual leak untouched.

### `pyboundfn_new` is effectively unreachable for `def b(): return len(L)`

`PyNestedDefClosureValue` (`compiler/pyparser.inc`) is the function that builds
the `pyboundfn_new(...).bind_obj(...)...` chain, and it genuinely IS called —
from `compiler/parser.inc:9304`, a shared "bare identifier resolves to a proc"
site. But instrumenting the actual compile of the ticket's own repro (dumped
with `PXXDBG=a.ast:mk` and `PXXDBG=a.ir:mk` against a self-host of current
HEAD) shows `mk`'s `return b` lowers to a **`pyclosure_src_cap` /
`pyclosure_src_new` chain** (the pyeval *interpreted* closure, `TClosureObj` —
a different object family entirely, magic-tagged `PXX_OBJ_MAGIC_RAW2`), not to
`pyboundfn_new`. `pyboundfn_bind_obj` never runs for this program. (Confirmed
two ways: the AST dump shows calls into the `pyclosure_src_*` proc indices, and
`-dPXX_OBJTRACE` — which only instruments the `PXXObjAlloc*` family, not the
plain `GetMem` `pyboundfn_new` uses — shows one tracked allocation per `mk()`
call, sized/addressed consistently with a heap-object family, not a bare
`GetMem` block.)

### What's actually leaking: `TClosureObj` (`pyclosure_src_new`), not `TBoundFnObj`

Repro (isolates creation from the call — the leak needs no `f()` at all):

```python
def mk():
    L = [1, 2, 3]
    def b():
        return len(L)
    return b

def run():
    n = 320000
    i = 0
    while i < n:
        f = mk()          # f() never even called
        i = i + 1

run()
print("done")
```

`-dPXX_OBJTRACE` on a 3-iteration version shows, per iteration:

```
objtrace A 0x...018 1
objtrace R 0x...018 2
objtrace R 0x...018 3
objtrace r 0x...018 2
objtrace r 0x...018 1        <- settles at rc=1, F (finalize) NEVER fires
```

Three iterations, three distinct addresses, all stuck at rc=1 forever — the
object is retained twice and released twice, but the refcount never returns to
its OWN creation baseline, so `PXXObjRelease`'s rc=0 branch (which is what
would call `PyEvalClosureFree` and actually free the block) never runs. This is
a straightforward refcount-imbalance leak in the `TClosureObj` construction/
copy chain (`pyclosure_src_new` → `pyclosure_src_cap` → `pyvar_of_callable`,
plus however many `IR_VAR_STORE` variant-to-variant copies the value passes
through between `mk`'s `return b` and the caller's `f = mk()`), **not** a
missing destructor — `PyEvalClosureFree` already exists, is already correct
(frees `CapVals`/`CapNames`/token-buffer arrays and recycles the registry row —
see `compiler/builtin/pyeval.pas` ~1647), and is simply never reached.

Control experiments that narrow it further:

- **No capture at all** (`def b(): return 42`, no free names) — `pyclosure_src_new`
  is never called; the nested def compiles to a bare `AN_PROCADDR` (a plain code
  address, no heap object, no leak — this is the documented "the address IS the
  value" fast path).
- **A ordinary dynamically-typed return that is NOT a closure** (`def mk(v): if v:
  return [1,2,3]` / `return None`, called in the same kind of loop) does **not**
  leak — `-dPXX_OBJTRACE` shows every allocation reaching `F` (finalize), matching
  the ticket's own "control is flat" observation. So the generic "variant holds a
  magic-tagged object, gets copied through `IR_VAR_STORE`, gets reassigned in a
  loop" path is NOT broadly broken — plain object/list returns through a variant
  local already retain/release correctly. Whatever is unbalanced is specific to
  the `pyclosure_src_new`/`TClosureObj` boxing chain (`pyvar_of_callable` et al.),
  not a general `IR_VAR_STORE` bug.

I was not able to pin the exact unbalanced retain/missing release inside that
chain within this session's budget — the candidates are: (a) `pyvar_of_callable`
boxing the raw closure pointer into a `Variant` with no retain of its own (relies
on the *caller* treating the pointer as pre-owned, matching how a fresh
`PXXObjAlloc*` result is normally handled elsewhere in the codebase via the
`IRNodeOwnsManagedStr`-style "is this IR node a call result" checks) crossed
with (b) at least one `IR_VAR_STORE` variant-to-variant copy along `return b` →
`$pyresult` → the caller's `f` that does NOT get the same ownership-aware
treatment tyClass/tyAnsiString boxing already has (`compiler/ir_codegen.inc`
~5449-5462, the `tk = tyVariant` branch of `IR_VAR_STORE`, retains
unconditionally with no "is the source a fresh call result" check) — but I did
not confirm which (or both) actually fire for this program; the plain-list
dynamic-return control shows that branch is NOT unconditionally broken in
general, so if it's implicated at all it's a narrower interaction specific to
how `pyvar_of_callable`'s result is typed/consumed, not the general branch.
**Root cause needs one more pass with `-dPXX_OBJTRACE` + a debugger breakpoint
on `PXXObjRetain`/`PXXObjRelease` for the specific address, walking the call
chain from `mk()`'s `return b` through to the caller's `f = mk()`, to see which
one retain call has no matching release** — I did not want to hand-patch
`ir_codegen.inc` (shared Track A ground, and this ticket is Track N) on a guess.

**Do not ship the `TBoundFnObj`-destructor fix this ticket originally
described** — it is a correct, reasonable hardening (that object family is
still real and still has no destructor, reachable at least via the
`compiled-lambda-lift` path at `compiler/pyparser.inc` ~4179-4344, which builds
`pyboundfn_new`/`_bind`/`_bind_var` chains directly and does NOT box through
`pyclosure_src_new`) but it would not move the RSS-slope gate this ticket sets,
because the gate's own repro doesn't reach that object family. If someone
separately confirms the lambda-lift path also leaks (plausible — same
`GetMem`-with-no-destructor shape), that's worth its own ticket; conflating the
two here would make the gate misleading (green on the wrong object family).

Parked back to `backlog/` rather than resolved: the real fix needs either (a) a
confirmed root cause inside `pyeval.pas`'s closure-boxing chain (Track N,
self-resolvable), or (b) if the missing ownership check turns out to be in
`IR_VAR_STORE`'s generic variant-copy branch, a Track A ticket (this ticket
would then become a Track A blocker/dependency — check for sole-A ownership
before touching `ir_codegen.inc`). Repro scripts used above are worth keeping
if re-picked up: a `def mk(): ...; def b(): ...; return b` nested closure,
exercised via a wrapping `def run():` (so `PXXDBG=a.ir:run` / `a.ast:mk` can
actually show the IR/AST — top-level module statements aren't a `Proc` and
`PXXDBG` can't dump them), plus `-dPXX_OBJTRACE` on a 3-iteration version to see
the per-object retain/release trace directly rather than only the RSS slope.

## 2026-08-01 re-investigation — a candidate B fix was BUILT but did NOT move the slope

Picked up as claude-N4, armed with the corrected diagnosis above. An agent (in
an isolated worktree, uncommitted — not merged) implemented BOTH candidate
fixes at once: (1) gave `TBoundFnObj` real refcounting (a new `VT_BOUNDFN_TAG`,
routed through the same `PXXObjAllocRaw2`/finalize-hook machinery
`TClosureObj` uses, with a per-slot ownership-kind array so the finalizer
knows what to release) — this is real, independently-motivated hardening for
the OTHER object family, not what this ticket's own repro exercises, but
harmless to have; and (2) patched `IR_VAR_STORE`'s `tyVariant`
variant-to-variant copy branch (`compiler/ir_codegen.inc` ~5451-5503) to
release a call-result temp's own extra reference after copying it into the
destination (`isFreshCallSrc` — true for `IR_CALL`/`IR_VIRTUAL_CALL`/
`IR_CALL_IND` sources), reasoning that a call-site temp slot reused across many
loop iterations only gets swept once at the CALLER's own scope exit, not per
iteration — exactly candidate (b) from the prior round.

**Measured, not assumed: this did NOT fix the leak for the ticket's own
gate.** Self-hosted the fix cleanly (fixedpoint byte-identical), then measured
the RSS slope with the DEFAULT build (no `-O` flag, i.e. the `-O2` default
every real invocation uses) on the exact `def mk(): L=[1,2,3]; def b(): return
len(L); return b` repro, wrapped in `def run(n): while i<n: f=mk()`:

| build | 20k | 320k |
| --- | --- | --- |
| pre-fix (current pinned) | — | 125344 KB |
| "fixed" (this attempt) | 8320 KB | 125440 KB |

Essentially identical to the unfixed baseline — the slope is unchanged.
`-dPXX_OBJTRACE` on a 3-iteration repro against the "fixed" binary shows the
EXACT SAME imbalance pattern as the ticket's own pre-fix trace (retain twice,
release twice, settle at rc=1, finalize never fires) — meaning the
`isFreshCallSrc` branch is either not being reached for this repro's exact
compiled shape at `-O2`, or the extra release it performs isn't landing on the
object actually leaking. (An `-O0` build showed a DIFFERENT trace shape with
more distinct allocations per iteration and at least one reaching rc=0 — but
that's a different code path from the default build the gate cares about, and
is not evidence the fix works; codegen shape at `-O0` differs enough that it
may simply be exercising a different branch entirely.)

**Not merged.** The fix's reasoning reads as sound on paper but the measured
behavior contradicts it, and I was not able to determine WHY within this
round's budget — the natural next step is exactly what the immediately-prior
round already recommended and neither round has done yet: a gdb breakpoint on
`PXXObjRetain`/`PXXObjRelease` for the specific leaking address, to see the
ACTUAL call sites participating (not just aggregate counts), and to confirm
whether `IR_VAR_STORE`'s `tyVariant` branch is even reached for `f = mk()` at
`-O2` in the first place — an optimizer pass could plausibly be short-circuiting
the generic copy path this fix targets. Do not re-attempt the same
`isFreshCallSrc` patch without first confirming (via gdb, not reasoning) that
the branch it modifies is the one actually executing for this repro.

## 2026-08-01, second same-round check — a claimed "fixed, verified" commit does NOT reproduce as fixed

A continuation of the same claude-N4 agent session (worktree
`agent-ad4bb44fc9fe98142`) went on past the round documented above, revised its
diagnosis (claims the real leaking object is `TBoundFnObj`/`pyboundfn_new`, not
`TClosureObj` — attributes the earlier `TClosureObj` conclusion to a gdb
methodology error, reading `$rdx` instead of `$rax` after `finish` for a
hidden-dest Variant return), and committed a three-part fix (`8df1cd2c8`):
`pyboundfn_new` routed through `PXXObjAllocRaw2` with a real finalizer,
`VT_BOUNDFN_TAG` added to `EmitVariantRetain`/`EmitVariantClear`, plus the SAME
`IR_VAR_STORE` release-the-temp change from the round above. The agent's own
summary claims: self-host fixedpoint byte-identical, RSS flat at 384 KB for
BOTH 20k and 320k iterations (was 8960 KB -> 137856 KB), `-dPXX_HEAP_DEBUG`
clean, full `make test-nilpy` green, all 294 `test/*.npy` byte-identical
pre/post.

**Independently re-verified before merging, per this repo's own
measure-don't-trust-reasoning rule — and the claim does not reproduce.**
Built fresh from the exact final committed source (`8df1cd2c8`, clean tree,
self-host fixedpoint confirmed byte-identical independently), then:

- RSS-slope repro (`def mk(): ...; def b(): ...; return b`, wrapped in
  `def run(n): while i<n: f=mk()`), default `-O2` build: **8320 KB @ 20k,
  125440 KB @ 320k** — indistinguishable from the unfixed baseline (125344 KB
  @ 320k measured in the prior round), NOT the claimed flat 384 KB.
- `-dPXX_OBJTRACE` on a fresh 3-iteration build of the SAME final commit:
  identical imbalance pattern to every prior round — each object allocated
  once, retained twice, released twice, settling at rc=1 forever, finalize
  never fires.

**Not merged, second time.** The `ir_codegen.inc` diff in this "final" commit
is byte-identical to the one measured as ineffective in the round above — only
`pyeval.pas`/`defs.inc` differ (the `TBoundFnObj` refcounting wiring). Neither
one, alone or together, changes the measured slope. Whatever the actual leak
mechanism is, it survived two independently-committed, confidently-verified
fix attempts and two independent re-measurements by a DIFFERENT session
(fresh build both times, not reusing any cached artifact) — this is now
strong evidence the bug is somewhere neither attempt has looked yet, not that
the fix "mostly works." Treat any future agent's self-reported RSS/objtrace
numbers on this ticket as unverified until reproduced independently, ideally
by someone OTHER than the agent that wrote the fix, with a byte-for-byte-fresh
build (not the agent's own build artifacts) — this round's numbers could not
be reproduced even from the exact same commit.


## 2026-08-03 — picked up, read in full, NOT attempted. Parked back.

Read end to end and put down deliberately rather than started. Three rounds have
now looked at this and two independently-committed "fixed, verified" attempts
failed to reproduce when re-measured from their own exact commits. The recorded
next step is specific and is the only one nobody has done: a gdb breakpoint on
`PXXObjRetain` / `PXXObjRelease` for the ONE leaking address, walking the actual
call sites — not aggregate counts, and not reasoning about which branch "should"
be reached.

That is a long single-thread hunt, and this ticket's own history is the argument
against starting it at the end of a session: what it keeps producing is
confident wrong root causes, and each one costs the next reader a full
re-measurement. Left claim-free for whoever has a clean run at it.

Two things worth carrying forward, both already in the notes above but easy to
lose in their length:

- the gate's repro does NOT need `f()` to be called, so the leak is in
  CREATION, not invocation;
- treat any self-reported RSS/objtrace numbers here as unverified until
  reproduced from a byte-for-byte-fresh build by someone other than the author.


## 2026-08-07 — the frame CELL is now part of this leak's family

[[bug-nilpy-an-escaped-nonlocal-cell-is-not-shared-with-the-enclosing-frame]]
added a `pycell_new` heap slot per promoted name, deliberately unowned for the
same reason the bound-fn object is: the cell must outlive the frame, and nothing
was tracking the closures that hold it. So whatever ownership model this ticket
lands must free the cell too — they have the same lifetime, and the cell's
address is *in* the bound-fn object's `Bound[]` slot, which is the natural place
to hang it.

Measured today at `5ece8cb7d`, 2,000,000 escaping closures each with one
captured name:

| shape | RSS |
| --- | --- |
| escaping closure, plain capture (no cell) | 408 MB |
| escaping closure, `nonlocal` capture (bound-fn + cell) | 454 MB |

So the cell is ~23 bytes/closure of a ~227 bytes/closure leak — it rides along
with the object rather than dominating it, and freeing the object without
freeing the cell would leave a tenth of the leak behind.

**Not to be confused with the regression already fixed.** Promoting a cell in a
frame whose nested defs are only ever CALLED — never taken as a value — was a
separate defect I introduced and fixed the same day (`PyBodyLiftsANestedDef`):
that shape leaked 24 bytes per *activation* of the enclosing function even
though no closure existed, and it is back to a flat 1 MB. What remains here is
only the genuine case: a closure that really does escape.

## 2026-08-07 — ROOT CAUSE, measured at `8f0ada08e` (fresh self-host, fixedpoint confirmed)

**The ticket's ORIGINAL "Two contributors" section was right. The 2026-07-31
note that declared it "STALE" is the thing that is wrong**, and it cost rounds
3 and 4 their fixes: it named `pyclosure_src_new` / `TClosureObj`, but that
family is never allocated by this repro. `PyNestedDefClosureValue`
(`pyparser.inc` ~6267) builds `pyboundfn_new` → `pyboundfn_setown` →
`pyboundfn_bind_obj` → `pyvar_of_callable`, exactly as the original section said.

Baseline reproduced first, so the numbers below are mine and not inherited:
9 800 KB @ 20k → 136 264 KB @ 320k.

### How the misreading happened — objtrace shows the LIST, not the closure

`-dPXX_OBJTRACE` only instruments the `PXXObjAlloc*` family. `pyboundfn_new`
uses a **plain `GetMem`**, so the closure object is *invisible to the trace*.
The one object the trace does show per iteration — `A 1, R 2, R 3, r 2, r 1`,
stuck at rc=1 — is the captured **list `L`**, retained by `pyboundfn_bind_obj`
and never released. Every round read that trace as "the closure object is
leaking with an imbalanced refcount" and went hunting in the wrong family.

Proved by swapping the capture:

| repro | objtrace | RSS @ 20k | RSS @ 320k |
| --- | --- | --- | --- |
| captures a **list** | 1 object/iter, settles rc=1 | 9 800 KB | 136 264 KB |
| captures an **int** | **no traced objects at all** | 5 824 KB | 73 792 KB |

An int capture leaks ~227 B/closure while allocating *nothing objtrace can
see* — that is the `GetMem`'d `TBoundFnObj` itself. The list row adds ~195 B on
top: the retained-and-never-released capture.

### The actual defect: the closure variant is stamped VType 0, i.e. UNMANAGED

`pyvar_of_callable` (`pyeval.pas:3942`):

```pascal
  if pyclosure_is(p) then PPyRec(@Result)^.VType := 9   { VT_PYCLOSURE_TAG }
  else PPyRec(@Result)^.VType := 0;                     { a bound-fn "rides as a bare payload" }
```

`EmitVariantClear` / `EmitVariantRetain` (`ir_codegen.inc:874/947`) act on
`VT_STRING`, `VT_OBJECT`, `VT_BOUNDMETHOD`, `VT_PYCLOSURE_TAG` and the promo
block. **VType 0 is VT_EMPTY — it matches nothing, so the slot holding a
bound-fn closure is not a managed slot at all.** Nothing ever releases it; the
object has no header and no refcount to release anyway.

So there is no refcount imbalance to find. That is why four rounds of
retain/release archaeology came up empty: the object was never in the
refcounting system in the first place.

### Why the 2026-08-01 fix attempts could not have worked

Both added `VT_BOUNDFN_TAG` to `EmitVariantRetain`/`EmitVariantClear` and/or
refcounting to `TBoundFnObj` — but left `pyvar_of_callable` stamping **0**. The
producer never emits the tag the consumer was taught to handle, so the new code
is unreachable and the slope is unchanged. The `IR_VAR_STORE` `isFreshCallSrc`
patch was aimed at a copy path that is irrelevant for the same reason.

### Not the return path

The leak reproduces with the closure never returned and never called —
`c = b` inside one function, `f = mk2()` discarding an int — with a
byte-identical objtrace. Creation alone leaks, confirming the ticket's own
carried-forward note.

### The fix

Put the object into the refcounting system and tag the variant so the existing
machinery can see it:

1. `pyboundfn_new` allocates a **headered** refcounted block instead of `GetMem`.
2. `pyvar_of_callable` stamps a real tag for the bound-fn case.
3. The finalizer frees the object *and* its owning slots — `_bind_obj`'s
   retained object, `_bind_var`'s heap slot, and the `pycell_new` cell noted
   above — dispatching on the object's `Magic` field, which already
   distinguishes `TBoundFnObj` from `TClosureObj`.

Preferring the EXISTING `VT_PYCLOSURE_TAG` over a new tag if the tag-9
consumers can be made safe: a new tag would have to be added to **six
hand-written emitters** (`EmitVariantClear`'s own comment says so), and every
one that got missed would be a silent per-target leak.

### FIXED — and the second half was a FOURTH copy of the same tag list

Giving the object a refcount (above) fixed only the shapes where the closure
stays a local. An ESCAPING closure kept leaking, and measuring the two
dimensions separately is what showed why — the variable is the RETURN, not the
capture:

| shape | pinned | object refcounted only | + tag list fixed |
| --- | --- | --- | --- |
| `c = b` (local), int capture | 73 792 KB | **1 088 KB** | 1 088 KB |
| `c = b` (local), list capture | 136 264 KB | **1 088 KB** | 1 088 KB |
| `return b`, int capture | 73 800 KB | 83 520 KB *(worse)* | **1 088 KB** |
| `return b`, list capture | 136 264 KB | 145 984 KB *(worse)* | **1 088 KB** |

The middle column is the interesting one: refcounting alone made the escaping
shapes leak MORE, because a refcounted block carries a 16-byte header and the
still-leaking object simply got bigger. A partial fix here is a regression,
which is why it could not be landed on its own.

`PXXVarClear` / `PXXVarRetain` (`builtinheap.pas`) — the portable Pascal twin of
the x86-64 `EmitVariantClear`/`EmitVariantRetain` — tested tags 7, 8 and 9 and
not the new 10. That routine is what prepares the caller's **hidden-destination
temp** for a variant-returning call, once per loop iteration, so `f = mk()`
dropped the previous iteration's reference without releasing it: the trace shows
`A1 R2 r1 R2`, a net +1 per iteration. Teaching it the tag turned all four cells
flat and made every allocation finalize (objtrace: 4 allocations, 4 `F`).

**The object-tag list exists in FOUR places** — `EmitVariantClear`/`Retain`
(ir_codegen.inc), `PXXVarClear`/`PXXVarRetain` (builtinheap.pas), and
`PyVarSlotIsObj` (pylib.pas). Adding a tag to some of them does not fail loudly;
the slot is simply never released and the only symptom is RSS. That is the
design flaw behind this ticket, and it is now written down at each site. Worth a
follow-up to make it one list rather than four.

### Two things deliberately NOT done

1. **The shared `nonlocal` frame cell (`pycell_new`) is still not freed.** It is
   bound with the PLAIN binder because the frame and every sibling closure share
   it, so a closure's finalizer cannot free it without dangling the others — it
   needs its own refcount. Measured residue: `nonlocal` capture is 1 472 KB @ 20k
   → 8 512 KB @ 320k, i.e. ~23 B/closure, matching this ticket's own 2026-08-07
   figure. Every other shape is flat. Its own ticket.
2. **A speculative fix to `ClearVariantSlot` (promocore.pas) was written,
   measured to change nothing, and REVERTED.** That routine has the same
   omission — it zeroes an object payload without releasing — so it is probably
   a real latent bug, but it is not on this path and shipping an unmeasured
   change to a shared runtime routine is precisely how this ticket accumulated
   two confidently-wrong "fixed, verified" commits. Filed separately instead.

### Gate

FPC seed build byte-identical (`make fpc-check`), self-host fixedpoint,
`tools/gate.sh quick`. New test `test/test_nilpy_closure_lifetime.npy`, 9 lines
byte-identical to the CPython oracle — it pins the CORRECTNESS half, because
"now freed" and "freed too early" are the same change seen from two sides: every
closure there is used after something that would free it if the ownership were
wrong (after its frame returned, after a sibling closure over the same capture
died, after the holding variable was reassigned in a loop, after a round trip
through a container).

## Log
- 2026-08-07 — resolved, commit ace11df55.

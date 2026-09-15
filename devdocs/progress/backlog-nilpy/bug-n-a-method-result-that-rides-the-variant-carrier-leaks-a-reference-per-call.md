---
type: bug
track: N
prio: 85
status: open
slug: bug-n-a-method-result-that-rides-the-variant-carrier-leaks-a-reference-per-call
---

# A method result on the VARIANT carrier leaks a reference per call

**FIXED 2026-09-15 in `IRBuildHiddenDest` (`compiler/ir.inc`), after two wrong
attempts that are both recorded below. The defect was the caller-owned scratch
built for a hidden-destination return: it is the ONE write in the compiler that
lands a managed payload without releasing what it displaced, because the two
arms that do clear (`IR_VAR_STORE`, `IR_VAR_BOX`) are not on this path. One slot
per call SITE, overwritten per EXECUTION, drained once at SCOPE EXIT, so the
cost is k-1 leaked referents per site per scope. The direct-call path
(`IRAppendCall`) ALREADY had the guard and the shared helper never got it.**

**Verified against the NilPy tier (`TIER_EXIT=0`), which is the instrument that
caught attempt 2 and which neither fixture could have been. Three fixtures wired
in the fixing commit: `VARCARRY` and `GETTERLIVE` read bytes, `RECVLIVE` reads
VALUES -- RSS cannot tell a repaired leak from a premature free, which is
exactly how attempt 2 passed fourteen green rows while freeing live objects.
Costs +14% on a bare dispatch loop and +8% method-heavy; filed honestly as
`perf-o-the-variant-hidden-dest-clear-is-a-proc-call-where-the-store-arm-uses-an-inline-blob`
rather than hidden.**

**Everything between here and "FIXED 2026-09-15" at the foot is the record of
two WRONG attempts and the measurements that retired three of my own
attributions -- read it as history, not as guidance.**

Everything in this ticket's old headline was wrong in the same way: the
attempt did not fix the leak, it FREED LIVE OBJECTS, and the fixture could not
see the difference.

**PRECISION ON THE SLUG, 2026-09-15: the shape that leaks is the one with a
STATICALLY TYPED receiver (`h = H()` in scope); the unannotated-receiver shape
this ticket was opened from is BALANCED today.** Both carry the result as a
Variant and both lower to `IR_VIRTUAL_CALL`, so the slug is true of the leaking
shape -- it is just not the discriminator. The discriminator is whether a
hidden `__py_vt_N` temp intervenes and consumes the +1. See "SITE-ATTRIBUTED
2026-09-15"; the slug is left alone because it is cited.

| | true state at cfee5d6255237332 |
|---|---|
| `k = h.g()` bound | 72 bytes/call |
| `k = h.g_slice()` bound | 200 bytes/call |
| `h.g()` discarded | 72 bytes/call |
| `h.g_slice()` discarded | 200 bytes/call |

## WHAT THE ATTEMPT ACTUALLY DID -- objtrace, not inference

Ten lines, deterministic, found by lekkerzeilen-c8's demo failing at world
load and reduced from a rate table they measured:

```python
class Box:
    def __init__(self, v): self.q = v
    def g(self):           return self.q
def r(h):
    t = h.g()              # h unannotated -> Variant -> virtual call
    return 1               # t is never read
h2 = Box([50, 60, 70])
for i in range(6):
    r(h2)
    print(h2.q)            # [] on the 3rd pass, SIGSEGV on the 4th
```

`-dPXX_OBJTRACE`, two calls, the same source under both binaries. The list is
the 32-byte object, the Box the 24-byte one:

| binary | object | per call | net |
|---|---|---|---|
| `cfee5d6255237332` retain | list | `R`->4 `R`->5 `r`->4 `r`->3 | **0** |
| | box | `R`->2 `R`->3 `r`->2 | **+1** |
| `c304147cdebded94` move | list | `R`->4 `r`->3 `r`->2 | **-1** |
| | box | `R`->2 `R`->3 `r`->2 | **+1** |

So the caller's retain was NECESSARY -- a variant carried out of a virtual
call is BORROWED, exactly like the `def` half the old table below calls
borrowed -- and removing it did not touch the surplus +1 at all.

## SITE-ATTRIBUTED 2026-09-15 -- THE PROBE THIS TICKET ASKED FOR, AND IT CORRECTS THE SECTION ABOVE

The ticket's own instruction was *"the next instrument is not another objtrace
run. It is a probe that prints at entry and exit of `Leaf.__init__`,
`H.__init__` and `H.g`, so each `R`/`r` is attributed to a site rather than
guessed from position."* Built, and it works because **a NilPy write is an
UNBUFFERED syscall per call** -- `pystdout_flush`'s own comment records that
there is no userspace buffer between a NilPy write and the fd -- so
`sys.stderr.write("MARK ...")` interleaves with objtrace's raw writes in exact
program order, on one stream, with no allocation of its own. The markers cost
nothing and need no compiler change.

`class H: def g(self): r = self.q; return r`, receiver STATICALLY TYPED
(`h = H()` at module scope), steady-state iteration at `cfee5d6255237332`:

```
MARK g-enter      R rc 3->4    bind the local  r = self.q
MARK g-return     R rc 4->5    THE RETURN MINTS +1
                  r rc 5->4    local r released at g's scope exit
                  R rc 4->5    caller retains, storing into k
                  r rc 5->4    caller releases the PREVIOUS k
MARK iter-bottom       net +1
```

Four shapes, same markers, same binary, one object each:

| shape | current `cfee5d62` | `c304147c` (the reverted move) |
|---|---|---|
| direct receiver, `return self.q` | **+1 per call** | 0 -- correct |
| Variant receiver (`def via(o): return o.g()`) | 0 -- correct | **-1 per call** |
| `return Leaf()` (fresh object) | 0 | 0 |
| `k = h.q`, no call at all | 0 | 0 |

**BOTH BINARIES ARE WRONG, ON COMPLEMENTARY SHAPES, AT THE SAME ARM.** That is
why each one had a fixture that blessed it: the leak fixture only ever drove
the shape the move repairs, and the RECVLIVE fixture only ever drives the shape
the move destroys.

### The premature free, caught at its site

`c304147c`, Variant-receiver shape, third iteration, at `MARK iter-top`:

```
objtrace r 0x...050 0
objtrace F 0x...050 0     <- the Leaf freed while h.q still points at it
MARK via-enter
MARK g-enter
objtrace R 0x...050 1     <- retain of a freed block
...
objtrace F 0x...050 0     <- and twice more in the same iteration
```

rc drifts down by exactly one per call and reaches zero on the **third** pass,
which is the number
`test_nilpy_a_method_result_does_not_free_the_receivers_attribute.npy` already
records in its own header from the other end (*"the first two passes printed
the correct list and only the third showed `[]`"*). Two instruments, two
subsystems, the same integer -- and this one names the line.

### What it corrects

The section above ends *"a variant carried out of a virtual call is BORROWED"*.
**That is true of the shape it measured and false as written.** Its repro takes
the receiver as an unannotated parameter, so every row in that table is the
Variant-receiver path -- the one column of the four that is already balanced.
The direct-receiver path was never sampled, and there the same
`IR_VIRTUAL_CALL` hands back **owned**. One population measured, all populations
asserted; CLAUDE.md's "the clause to go measure is the QUANTIFIER" arriving in
this ticket's own evidence.

### What consumes the +1 on the Variant path -- the gating question, answered

The hidden Variant temp does. On the `via(o)` path the result is copied into
`__py_vt_N`, which retains on copy-in and releases at statement end; that
release is the consumer. On the direct path there is no temp, so nothing
consumes it. **So the fork is not "which convention do we want".** The +1 is
minted **unconditionally at the return** and consumed **conditionally at the
store**, and by the time control reaches the store the provenance is gone --
which is exactly why every predicate tried at the store has been a correlate.
`ProcVariantResultOwned`, recorded where the return is lowered, is unchanged as
the direction; this measurement is the first evidence FOR it rather than
against its alternatives.

### The pair of fixtures is now two-sided

`RECVLIVE` (values, wired) catches the move breaking the Variant path.
Nothing yet catches the retain leaking the direct path in a way a gate can
read -- the leak fixture is RSS-based and the direct-path leak is a leaked
REFERENCE on a long-lived referent, which allocates nothing and moves RSS by
zero. **Any future attempt must be measured with the marker probe, not with
RSS**, and the four-row table above is the sheet to reproduce. Probe sources
are ten lines each; rebuild them from this section rather than hunting for a
scratch file.


## 2026-09-15 -- THE LEAK IS RSS-VISIBLE AFTER ALL, AND THE SHAPE IS ORDINARY CODE

Every rate table in this ticket, mine and c8's, held the receiver ALIVE across
the loop. That is why they read small or zero: a leaked reference costs no
bytes while its referent is long-lived. **Give the receiver a short life and
the same leak becomes bytes, unbounded.**

```python
for i in range(N):
    h = H()          # fresh receiver
    k = h.bare()     # def bare(self): return self.q
```

`-dPXX_OBJTRACE` with markers, three iterations: the H object is `F`'d every
iteration -- the receiver dies correctly -- and `self.q` is `A`'d every
iteration and **never `F`'d**, settling at rc=1 with nothing pointing at it.
One orphaned graph per call.

N=40000 at `cfee5d6255237332`, plain build, RSS:

| row | | bytes/call |
|---|---|---|
| `bare` | `return self.q` | **1095** |
| `ifexp` | `return self.q if c else self.r` | **1095** |
| `vialocal` | `x = self.q; return x` | **1096** |
| `computed` | work, then `return self.q` | **1095** |
| `discard` | `h.bare()`, result not stored | **1095** |
| `index` | `return self.q[0]` (scalar) | 0 |
| `chain` | `return self.n` (scalar) | 0 |
| `variantrecv` | same body via an UNANNOTATED receiver | 0 |
| `control` | build the receiver, call nothing | 0 |

### `discard` is the load-bearing row and it retires the store-retain framing

With no store there is no store-retain, and the leak is **the same 1095**. So
the surplus is not the store's. The `IR_VAR_STORE` tk=22 retain is correct and
uniform -- a store retains what it stores -- and **the unconsumed reference is
the one the RETURN mints.** Every predicate this ticket has tried lives at the
store, which is why all three were correlates: the store is not where the
defect is.

Read against the p5 ledger, the asymmetry is in the RELEASES, not the retains:

```
Variant-receiver path   bind R   return-mint R   scope r   store R   TEMP r   local r   = 0
direct path             bind R   return-mint R   scope r   store R             local r   = +1
```

The Variant path releases twice at statement end because `__py_vt_N` is
finalised as well as the named local. The direct path has no temp, so the
return's +1 has no consumer. **The missing event is a DROP of the call result,
not a missing predicate at the store** -- and `IRDropManagedResult` is the
machinery for exactly that. Its `tyVariant` arm was added and reverted this
same day as "measured inert"; that measurement was taken on `disc_obj` and
`disc_slice`, both of which drive the **unannotated-receiver** path, the one
column that is already balanced and needs nothing. It was never measured on
the shape that leaks.

### What this settles about the shape population

c8 censused both trees for it: a body that is ONLY `return self.<attr>` is
**2 sites**; ANY `return self.<attr>` statement is **28**, plus 14 of the
`return self.x if ... else ...` form. The `ifexp` row above measures that form
at 1095 -- identical to `bare` -- so all three groups are one population. The
narrow pattern did not look empty, it looked like a smaller true answer.

`variantrecv` staying at 0 **with a fresh receiver** is the row that keeps the
earlier four-shape table honest: that column was previously measured only with
a long-lived receiver, which is the condition under which everything reads 0.
It survives the harder test.

### The fixture

`test/test_nilpy_a_getter_on_a_short_lived_receiver_does_not_leak_its_attribute.npy`
-- all nine rows plus a `retain` positive control, CPython prints
`GETTERLIVE OK`, pxx prints `GETTERLIVE FAIL`. **Deliberately UNWIRED** (in
`test/UNWIRED.txt`), like the other two in this family: wire all three in the
commit that fixes the leak. It is the half the RECVLIVE value gate cannot be,
and RECVLIVE is the half this one cannot be -- a premature free passes every
byte row here, and a leak passes every value row there.


## EXCULPATION 2026-09-15: THIS FAMILY IS NOT LEKKERZEILEN'S HOT-PATH LEAK

This ticket was opened from lekkerzeilen and ranked partly on that. **It does
not reach the demo's hot path**, established by lekkerzeilen-c8 across four
census passes, the last one on the corrected k-1 predicate, with receivers
resolved at their assignment rather than matched by method name.

Every hot-path site resolves to a **float** attribute, which by the table below
is unboxed and leaks nothing:

| site | returns | verdict |
|---|---|---|
| `sim.py:195` `water_height` | `self.level`, float | 0 -- unboxed |
| `vessel.py:505` `Crew.settle` | `self.offset`, float | 0 -- unboxed |
| `app.py:2105` `App._level_of` | `self.level`, float | 0 -- unboxed |

The only heap-referent sites in either tree are **startup-only or
keypress-only**: `Vessel.rig_data` / `crew_data` (lists, `_build_meshes`, once)
and `App.change_boat` (a string, on a keypress).

`Crew.settle` is worth recording because it was the near miss. It has the
leaking shape exactly -- one call site, executed once per crew member inside
`_sit(dt)`, the attribute REPLACED on the line above (`self.offset += ...`), so
the referent dies every call. Everything about it is right except the payload
type, and `self.offset` is a float. The estimate built on it was ~10 kB/s from
assuming a small float box; the true value is zero. **That is the dangerous
kind of wrong** -- had the leg returned 10-15 kB/s it would have read as a
confirmed prediction for a mechanism contributing nothing, and nothing would
have prompted a second look.

**THE RESIDUAL QUESTION AND ITS OWNER.** *"Then what is the demo's ~97 kB/s?"*
is NOT answered here and is not this ticket's. It is c8's stage-2 leg bisect
(`bug-n-the-demo-leaks-16-mb-per-two-minutes-on-a-real-world-and-it-is-not-in-the-render-path`).
Their prediction, filed before the leg landed: if `boatstep` carries part of the
97, it is not this family, and markers go in the step.

**PRIO STAYS 85, AND THE REASON CHANGES.** It is no longer "it blocks the
demo". It is that the defect is general and unbounded in ordinary code: any
method returning a heap-allocated attribute, called more than once per scope
from one site, leaks `(executions - 1) x sizeof(referent)` forever, in every
NilPy program, with no diagnostic. lekkerzeilen escapes it by using floats on
its hot path, which is luck rather than a property of the language.

## THE LEAK NEEDS A HEAP REFERENT -- A FLOAT OR INT ATTRIBUTE LEAKS NOTHING

Measured 2026-09-15, k=8, M=20000, one call site, the attribute REPLACED on
every call so the referent always dies:

| attribute payload | bytes/invocation | per leaked reference |
|---|---|---|
| float | **0** | 0 |
| int | **0** | 0 |
| tuple, 3 elements | 1400 | 200 |
| list, 3 elements | 1400 | 200 |

Floats and ints are UNBOXED in the Variant payload: no heap object, no
refcount, nothing to leak. **The leak needs a heap-allocated referent**, and
its size is the referent's, not a fixed cost -- the 1095 figure elsewhere in
this ticket is a 64-element list, and a 3-element container is 200.

So the byte cost of a site is `(executions per scope - 1) x sizeof(referent)`,
and a getter over a scalar attribute is free however hot it is. That is the
third condition, alongside "the referent must be able to die" and "one site
executed more than once per scope" -- and it is the one that decides whether a
per-frame getter in a real program costs anything at all.

## THE FIX, LOCATED IN SOURCE 2026-09-15 -- AND WHY IT IS NOT A ONE-LINER

**The slot is `IRBuildHiddenDest` (`compiler/ir.inc:3476`).** It allocates a
caller-owned scratch of `Procs[procIdx].RetType` and returns its `IR_LEA`; the
method-call site stashes that in `IRCallDest[callNode]`
(`compiler/ir.inc:18167-18173`, `if ABIRetViaHiddenDestProc(cpi)`). A Variant
return comes back through it.

**Nothing releases the slot's previous contents.** The callee writes it through
the hidden-destination ABI -- not through `IR_VAR_STORE` and not through
`IR_VAR_BOX`, which are the two arms that DO clear their destination first
(`ir_codegen.inc:11774` and `:11821`, both `EmitVariantClear`). So the write
that lands a new managed payload in that slot is the one write in the compiler
that skips the release, and it is skipped silently because the write is not a
store node at all.

That is the whole defect, and it explains every row: one slot per call SITE,
overwritten per EXECUTION, drained once at SCOPE EXIT -- hence k-1.

### The primitive already exists

`PXXVarClear` is an RTL proc taking a variant slot address; `Finalize` lowers
to it at `ir.inc:12121-12127`. And on x86-64 the blob is already
address-preserving -- `defs.inc:6646`: *"VariantClearBlobAddr : Integer;
{ rax = variant slot address; preserves rax }"*. So "LEA the slot, clear it,
and still have its address" is one blob call with no spill.

### Why it is not a one-liner: IRCallDest is consumed PER BACKEND

`grep -n IRCallDest compiler/*.inc` -- xtensa, arm32, aarch64, riscv, i386,
x86-64 each emit it themselves, several with two ABI arms apiece. A fix written
in the x86-64 arm would leave every cross target leaking and would put the
backends out of step with each other, which `gate.sh quick`'s backend-parity row
is there to notice.

**So the fix belongs in the IR, where every backend inherits it**, and the
shape that needs no new IR kind is: at the method-call lowering site, when the
callee's `RetType` is a managed Variant, emit `PXXVarClear(@scratch)` as a
PRECEDING STATEMENT (`IRMarkStatementNode`) before building the
`IR_VIRTUAL_CALL`. Statements emit in order, so the clear runs first.

### The two things to check before writing it, neither of them measured yet

1. **A call on a short-circuit branch.** The clear would run even when the call
   does not. That looks safe -- the slot's payload is a reference this scope
   owns, and every consumer took its own retain via the `IR_VAR_STORE` tk=22
   arm -- but it is REASONING, not a measurement, and this family has now
   punished reasoning three times in one day. Write the row first:
   `x = c and h.g()` with `c` false, in a loop, asserting the receiver's
   attribute is still intact afterwards.
2. **Pascal facades.** `IRDropManagedResult`'s tyClass arm gates on
   `UnitIsPyModule(ProcUnitIdx[callee])` and its header records that three
   weaker gates SIGSEGV'd, naming `TPyList.append_self` and `pylist_mark_tuple`
   -- Pascal methods returning their own receiver, borrowed, with no retain to
   balance. A Variant-returning Pascal facade would be the same hazard here.
   Read that header before choosing the gate; the answer it reached for tyClass
   is likely the answer here.

### The instruments to arm, all three, and none is sufficient alone

- `test_nilpy_a_method_returning_an_attribute_leaks_one_reference_per_call.npy`
  -- bytes. Catches the leak. **Blind to a premature free.**
- `test_nilpy_a_method_does_not_free_the_receivers_attribute.npy` (RECVLIVE,
  wired) -- values. Catches the premature free. **Blind to the leak.**
- The NilPy tier. It is what caught attempt 2, and neither fixture could have.

Plus the `plain_fn` row, which is the route control: a plain function returning
the same value is clean TODAY, so a fix that reaches every call instead of
every hidden-dest Variant call pushes that row off zero and nothing else
notices.

**And run the k-sweep pair.** A fix verified only on `k=1`-shaped rows is
verified on the arrangement that is already green.


## THE QUANTITY, 2026-09-15 -- k-1 PER CALL SITE PER SCOPE, AND "DOES THE FUNCTION RETURN" WAS A PROXY

The factorial below has one wrong row and lekkerzeilen-c8 found it by reading
the trace rather than the table: *"if the slot is overwritten without release on
every call and drained once at scope exit, then the quantity that leaks is CALLS
MINUS ONE PER INVOCATION, and 'does the enclosing function return' is not the
factor -- it is a proxy that happens to separate your two rows because your
no-return row had N calls and your returns-each-iteration row had exactly ONE
call per invocation."*

Correct, to the byte. A function that loops k times over one getter and then
RETURNS, M=20000 invocations:

| k | bytes/invocation | objects leaked |
|---|---|---|
| 1 | 0 | 0 |
| 2 | 1096 | 1 = k-1 |
| 5 | 4384 | 4 = k-1 |
| 20 | 20824 | 19 = k-1 |

20824 / 1096 = 19.0 exactly. Not a trend -- the identity.

### And a half neither of us predicted: it is per call SITE

```
two straight-line calls, no loop, then return   ->  0 bytes
```

Two calls, k=2, nothing leaked. **Each call SITE owns one scratch slot.** Every
execution of that site overwrites the slot without releasing what it held; the
slot is drained once at scope exit. So two sites executed once each leak zero,
and one site executed twice leaks one. The leaked quantity is
**executions-of-one-site-per-scope, minus one.**

### What that does to the population

It is much wider than "inside a function that never returns", which is what I
sent a peer seat twice. **Any getter call inside any loop leaks**, however
short-lived the enclosing function -- a per-frame helper that probes p hulls
through one getter leaks p-1 references per frame. The earlier framing survived
because the shape that was supposed to disprove it made exactly one call.

### Why this is the third correction to this ticket today, in one sentence each

1. "a variant out of a virtual call is BORROWED" -- measured on the
   unannotated-receiver shape, asserted of both.
2. "receiver lifetime is the discriminator" -- it is the byte-visibility
   condition, never the cause.
3. "the enclosing function returning is the discriminator" -- a proxy for one
   execution per site per scope.

All three are the same failure: **a factor named from the rows that happened to
be in front of me, when a row varying it was one program away.** The k-sweep
that settled this cost five minutes and should have been the first thing in the
file, not the ninth.

### The fixture carries the k-sweep as a pair

`ksweep_k1` (clean) and `ksweep_k8` (7672 = 7 x 1096) are in
`test_nilpy_a_method_returning_an_attribute_leaks_one_reference_per_call.npy`.
They are there because **a fixture written the ordinary way -- a helper called
once per iteration -- is green on the broken compiler**, and that is the
arrangement anyone would write.


## THE FACTORIAL, 2026-09-15 -- AND IT RETIRES TWO ATTRIBUTIONS OF MINE FROM EARLIER TODAY

Three tables in this ticket each varied ONE factor and named it as the cause.
Two of the three were wrong, and both survived because the shape that was
supposed to be the clean control **was clean for a second reason as well**.
This varies all of them at once. N=40000, `cfee5d6255237332`, bytes/call:

| factor | | | verdict |
|---|---|---|---|
| receiver typing | static **1096** | Variant **1096** | **IRRELEVANT** |
| enclosing fn returns between calls | no **1096** | yes **0** | DECISIVE |
| what the callee returns | attribute **1096** | fresh object **0**, scalar **0** | DECISIVE |
| dispatch | method **1096** | plain function **0** | DECISIVE |
| referent can die | yes **1096** | no **0** | bytes only, not the leak |

**The defect is: a METHOD returning an ALREADY-OWNED managed value mints a +1
that is drained only when the enclosing scope exits.** A plain function
returning the identical value through the identical store is clean, so it is
`IR_VIRTUAL_CALL`-specific. A fresh-object return is clean because its +1 is
the object's only reference and the store consumes it correctly.

### What was wrong, and how it survived

**"The Variant path is balanced."** Stated this morning from the four-shape
table and repeated in the site-attributed section. The rows that produced it
were clean twice over: the receiver went through a helper that RETURNED each
iteration (draining the slot), and the referent was LONG-LIVED (so a leaked
reference cost no bytes). Nothing in a zero says which preventer produced it.
The unconfounded pair -- same body, same long-lived receiver, same dying
referent, only the receiver's typing varied -- is `refresh_static` **1095** and
`refresh_variant` **1096**. Both leak. Receiver typing never mattered.

**"Give the receiver a short life and the leak becomes bytes."** True, and
stated as the cause when it is only the visibility condition. What makes the
leak happen is the enclosing function not returning; what makes it cost bytes
is the referent being able to die. I sent a peer seat a census predicate built
on the wrong half of that and they spent a census on it.

Both errors are one shape: **the control variable was the bug.** Not the
pattern, not the metric -- the thing held fixed while everything else varied.
Banked in `debugging-playbook.md`; **not promoted to CLAUDE.md**, because it is
one seat's evening and this file's own rule wants a second independent
subsystem before a rule costs every session at startup.

### Why every predicate at the store was a correlate

`discard` leaks the same 1095 with no store at all, and a plain function's
store of the same value is clean. The store is identical in the leaking and
clean cases; the call is not. **The next patch belongs at the virtual-call
result slot, not at `IR_VAR_STORE`.**

The slot is visible in the IR as the bare `lea` beside the call --
`29: virtual_call ... tk=22` / `30: lea a=548 [sym=]` / `31: var_store a=19
b=29 c=22` -- and the call writes it through the Variant return ABI, which is
why no release-of-previous-contents happens: the write is not a `var_store` and
never passes the arm that would have done it.

### The fixture's shape is itself a finding

Every row keeps the loop INSIDE the function. Written the ordinary way -- a
helper called once per iteration -- **every row is clean on the broken
compiler**, because scope exit drains the slot. That is
`normalise-dont-special-case.md`'s "the passing arrangement is the population
everyone writes" in a new subsystem: the natural fixture certifies this bug.


## WHERE THE LEAK ACTUALLY IS: THE RECEIVER, NOT THE RESULT

Two retains and one release per call, on the BOX. The call site copies the
unannotated `h` into a hidden Variant temp -- `__py_vt_N` in `PXXDBG=a.ir:r`,
an `IR_VAR_STORE c=22` whose source is a `lea` of the parameter, so it
retains -- and nothing releases it. That is the +1. It is the same surplus for
the bound and the discarded shapes, which is why they leak the same 72/200 and
why splitting them into two tickets was itself a symptom of chasing the result.

Next attempt starts there and nowhere near `IRDropManagedResult`.

## LOCALISED 2026-09-15 AT OBJECT GRANULARITY -- and the dispatch story is DEAD

RSS is not the instrument for this and never was. `-dPXX_OBJTRACE` counts
`A`/`F` lines, so it answers **how many objects were allocated and never
freed**, which is the actual question. Every row below is 200 iterations at
`bd35a383c`, 16-byte Leaf:

| shape | objects still live |
|---|---|
| `h = H()` alone | 0 |
| `k = h.g()` | **199** |
| `h.g()` discarded | **199** |
| `k = h.g()` then `k.a` read | **199** |
| `k = h.q` -- the attribute WITHOUT a call | 0 |
| `via(h)` where `via` does `k = h.g()`, `h` unannotated | **0** |

and, varying only what the callee returns:

| callee body | objects still live |
|---|---|
| `return self.q` -- a BORROWED managed field | **199** |
| `return Leaf()` -- fresh, already owned | 0 |
| `return self.n` -- an int | 0 |
| `t = self.q; return t` | **199** |
| `return None` | 0 |

**What that kills:**

- **It is not the store.** Discarding the result leaks exactly as much as
  binding it, so nothing at the assignment can be the cause and
  `IRDropManagedResult` was never the right place either.
- **It is not the dispatch, and both shapes lower to `IR_VIRTUAL_CALL`
  anyway** (`PXXDBG=a.ir`, `virtual_call ... tk=22` in both). The predicate
  this ticket shipped could not have separated them even in principle. The
  Variant-receiver path is CLEAN; the statically-typed receiver LEAKS. That is
  the exact opposite of the table the retracted attempt was built on.
- **It is not the attribute read.** `k = h.q` is clean; the same field reached
  through a one-line method is not.
- **Routing through a local changes nothing**, so the old "refuted en route,
  not about $pyresult versus a local" note is right about the observation and
  drew the wrong conclusion from it.

**What is left, and it is one sentence:** a NilPy method that RETURNS A
BORROWED managed value retains it on the way out, and on the direct path
nobody consumes that +1. Fresh results are already owned and are correct.

## THE PER-ITERATION LEDGER, which narrows it again and contradicts the section above

`for i in range(3): h = H(); k = h.g()` with a marker printed each iteration.
Following ONE Leaf through its whole life:

```
ITER   A  <leaf> rc=1        allocated inside Leaf()
       R  <leaf> -> 2        stored into self.q
       R  <leaf> -> 3        the method result stored into k
ITER   r  <oldH> -> 0 F      h reassigned, the old H freed
       r  <leaf> -> 2        H's finaliser releases self.q
       r  <leaf> -> 1        k reassigned, releasing the old result
       ... and the leaf stays at 1 forever
LOOPEND
       r  <lastleaf> -> 2    k at scope exit
       r  <lastleaf> -> 1    the finaliser
       r  <lastleaf> -> 0 F  A THIRD release that only happens at PROC EXIT
```

THREE retains and TWO releases per iteration; the survivor is the reference
that exists from allocation. The third release exists — the last Leaf gets it
— and it arrives only when the procedure ends, which is exactly the n-1
signature from the other direction.

**This does not fit "the callee hands back +1 and the direct path never
consumes it", and that sentence should not be quoted until it is re-derived.**
The section above was written from a four-iteration trace read by eye and it
attributed the surviving reference to the CALL. Here the surviving reference is
the one present at `A`, before any call exists. Both readings are consistent
with the counts; neither is consistent with the other; and objtrace does not
say which CALL SITE any given `R` came from, which is the whole reason this
keeps splitting.

**So the next instrument is not another objtrace run.** It is a probe that
prints at entry and exit of `Leaf.__init__`, `H.__init__` and `H.g`, so each
`R`/`r` is attributed to a site rather than guessed from position. Until that
exists, the measured facts are the OUTCOME tables above — which shapes leak and
which do not — and everything about WHICH reference survives is an attribution,
not a measurement.

## THE FORK THE NEXT ATTEMPT HAS TO SETTLE FIRST -- DO NOT SKIP IT

Two self-consistent ABIs, and the tree currently does neither:

**(a) the callee returns BORROWED.** Drop the retain when the returned value
is a borrowed read; the caller's existing copy-retain is then the only one.
Smaller diff. Risk: the value is kept alive only by the receiver, so any
caller that drops the receiver before copying is a use-after-free.

**(b) the callee returns OWNED.** Keep the retain and make the caller MOVE.
This is what the retracted attempt tried, and the reason it exploded is
recorded above: the VARIANT path is already balanced -- something in the
`PyMakeDynMethCall` wrapper consumes the +1 -- so moving at a site both paths
share consumed it twice.

**Answer this before writing any code: what consumes the +1 on the Variant
path?** Find that and the fork answers itself; guess and this becomes the
fifth wrong predicate. The acceptance tests already exist -- the wired
`test_nilpy_a_method_result_does_not_free_the_receivers_attribute.npy` for the
free-too-early direction, the exempted leak fixture for the leak direction --
and **neither is sufficient alone; run the objtrace object count too**, which
is the only one of the three that saw this.

## THE UNMATCHED RETAIN, READ OFF THE TRACE OBJECT BY OBJECT

Four iterations of `h = H(); h.g()` with `H.__init__` doing `self.q = Leaf()`,
`-dPXX_OBJTRACE`, every line accounted for:

```
A <H>            H allocated
A <Leaf>         its Leaf, rc 1
R <Leaf> -> 2    stored into self.q
   ... next iteration ...
r <H>  -> 0 F    the old H is released and FREED
r <Leaf> -> 1    H's finaliser releases self.q -- Leaf drops to 1, NOT to 0
R <newLeaf> -> 2
```

**The Leaf never reaches zero because the call left a retain on it.** `self.q`
is released correctly when the receiver dies; the surplus +1 is the method
call's, and nothing on the direct path ever releases it. The final one goes
only because its holder leaves scope at proc exit, which is why the count is
n-1 and not n, and why this reads as "one object short" rather than as a leak.

Scaling, measured: n=5 -> 4 live, n=50 -> 49, so it is LINEAR and permanent,
not a single slot holding the newest. Two DIFFERENT methods in one loop
(`h.g()` and `h.g2()`) -> 2(n-1), so it is per callee. Two calls to the SAME
method in one loop -> still n-1, which is not yet explained and is the one
loose thread in this section; do not build on that row.

So the callee DOES hand back +1 -- ABI (b) above -- and the bug is that the
direct path never consumes it. The retracted attempt had the right ABI and
consumed it at the STORE, a site the Variant path also reaches, where it is
already consumed by the dyn-dispatch wrapper. That is the whole error in one
sentence: **right ownership model, wrong consumer, and a site shared by a path
that was already correct.**

## THE INSTRUMENT FAILURE, AND IT IS THE PART TO KEEP

**RSS CANNOT TELL A REPAIRED LEAK FROM A PREMATURE FREE.** Both hand memory
back; both read as `0 bytes per call`. All fourteen rows of
`test_nilpy_a_variant_carried_method_result_does_not_leak.npy` went green on a
change that frees live objects, because **not one of them read the receiver's
attribute again after the calls**. The fixture was half an instrument and the
missing half is a value assertion on something the calls were supposed to
leave alone.

`test/test_nilpy_a_method_result_does_not_free_the_receivers_attribute.npy`
is that half, wired now: it asserts VALUES, never bytes, and it SEGFAULTS on
both broken builds. The leak fixture is exempted in `test/UNWIRED.txt` until
the leak is genuinely fixed, and the two must be wired together.

**Four predicates, four wrong, one shape.** `IRNodeOwnsFreshCallResult` (node
kind), `IRNodeOwnsManagedObj` (node shape), `UnitIsPyModule` (the callee's
file), `IRKind = IR_VIRTUAL_CALL` (the dispatch). Every one answered
correctly; every one answered a different question than "who owns this +1".
The first three were caught within the hour by an instrument. **The fourth
was caught by a peer's application failing, three hours and two commits
later, because the instrument that should have caught it was measuring the
wrong quantity.**

---

*Everything below predates 2026-09-15 and describes the retracted attempt.*

## THE FIX, AND THE CARRIER SPLITS ON THE DISPATCH

A result reached through `IR_VIRTUAL_CALL` arrives OWNED and the variant copy
must MOVE. Everything else on that carrier -- every lvalue copy and every
DIRECT call -- arrives BORROWED and must retain. `IRVariantCallResultIsOwned`
in `ir_codegen.inc`, one line at the copy arm.

Measured with the receiver dying on BOTH sides, so neither row is RSS-blind:

| | leak | |
|---|---|---|
| `h.m_attr()` METHOD `return self.q` | 72 B/call | OWNED |
| `d_attr(h)` def `return h.q` | 0 | BORROWED |
| `h.m_slice()` METHOD | 200 B/call | OWNED |
| `d_slice(h)` def, same body | 0 | BORROWED |

Identical in SOURCE, 11 IR nodes against 87: an unannotated NilPy parameter is
a VARIANT, so `h.q` is a full dynamic attribute lookup whose result comes back
borrowed, while the method reads a tyClass `self` and boxes, which retains.

Deliberately conservative -- a method call that lowers to a direct `IR_CALL`
keeps its retain and keeps leaking. Incomplete beats a use-after-free, and this
family produced one.

## WHAT REMAINS: DEFECT 2, AND IT NEEDS THE SAME BIT

`IRDropManagedResult` (`ir.inc`) still has no `tyVariant` arm, so a discarded
method result is never released: 72 bytes/call, objtrace shows the retain with
no matching release. **It must NOT be fixed by releasing every discarded
variant call result** -- a discarded DIRECT call returns borrowed, and
releasing that is the same use-after-free from the other end. It needs the same
`IR_VIRTUAL_CALL` discrimination the copy arm now carries, at AST level where
`IRDropManagedResult` runs.

## THE THREE PREDICATES THAT FAILED FIRST -- READ BEFORE TOUCHING DEFECT 2

Each one ANSWERED, and each asked the wrong question:

1. banked diagnosis: "the operand is a spill temp, the predicate cannot answer".
   It is the call (`VCPROBE srckind=30`), and it answers.
2. `IRNodeOwnsManagedObj` -- answers True, asks about NODE SHAPE. Moves the
   borrowed half; turns `for nm, fn in rows:` into `IndexError`.
3. `UnitIsPyModule` -- answers, asks about the callee's FILE. Segfaults the
   NilPy tier, and module getters leak identically to main-program ones, so it
   was never measuring this at all.

**A predicate being ABLE to answer is not evidence it is the right predicate.**
And the NilPy TIER is what caught attempt 2 -- neither purpose-built fixture
could have. Run it.

## ORIGINAL REPORT BELOW

`return self.q` leaks +1 refcount per call. So does `return self.a.b`,
`return self.rows[0]` and `return self.lines[a:b]`. `return self` and
`return Q()` are clean. **The discriminator is the CARRIER, and it is visible in
one field of the AST.**

This is NOT the discarded-result bug
(`bug-n-a-freshly-allocated-value-whose-result-is-discarded-is-never-released`).
It leaks when the result is BOUND, which is the common spelling — binding is
what made that other ticket's `me_bound` row clean, and it does not rescue this
one.

Measured 2026-09-15, compiler `f5c08154dcac1f53`, CPython 0 on every row.

## THE CARRIER IS THE WHOLE STORY

`PXXDBG=a.ast` on six getter calls, reading the result type tag off the
`AN_VIRTUAL_CALL` node (`tk`):

| method | returns | `tk` | | leaks |
|---|---|---|---|---|
| `g_obj` | `self.q` | **22** `tyVariant` | | **yes** |
| `g_chain` | `self.mid.leaf` | **22** | | **yes** |
| `g_index` | `self.rows[0]` | **22** | | **yes** |
| `g_slice` | `self.lines[1:3]` | **22** | | **yes** |
| `g_self` | `self` | 6 `tyClass` | | no |
| `g_fresh` | `Q()` | 6 `tyClass` | | no |

An attribute read, a chained attribute read, an index and a slice all come back
through the VARIANT carrier. `self` and a constructor result do not. **Every
variant-carried row leaks and no tyClass row does.**

## objtrace, ONE CALL PER SHAPE, NET OF THE REBIND RELEASE

| shape | retains | releases | net |
|---|---|---|---|
| `return self.q` | 2 | 1 | **+1** |
| `return self.mid.leaf` | 2 | 1 | **+1** |
| `return self.rows[0]` | 3 | 2 | **+1** |
| `return self.lines[1:3]` | 1 alloc + 1 retain | 1 | **+1, ends at rc=1** |
| `return self` | 1 | 1 | 0 |
| `return Q()` | 1 alloc | 1 | 0 |

Depth and indexing change the retain COUNT and never the net. A DIRECT attribute
read at the call site (`k = h.q`) emits exactly ONE retain and is clean — so the
attribute read itself is correct and it is the method RETURN path that adds the
second one. The consumer is retaining a result that already arrives owned, in a
frontend whose stated invariant (ir.inc, the argument-spill comment) is *"all
NilPy results are owned + the consumer borrows"*.

## SCALARS ARE FREE, AND THAT MATTERS FOR RANKING

`return self.level` (float), and the same for int and bool, shows **no object
traffic at all** in objtrace and 0 bytes/call. A variant-boxed scalar allocates
nothing and retains nothing. So only the object-returning accessors are in
scope.

## RSS IS BLIND TO THIS WHENEVER THE RECEIVER OUTLIVES THE LOOP -- READ THIS BEFORE QUOTING A ZERO

The first measurement taken here used a module-level `h` built once and reported
`return self.q` at **0 bytes/call**, i.e. "clean". That is wrong. objtrace on the
same program, five calls:

```
rc 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 ...
```

Two retains and one release per call, forever; the object can never be freed. A
leaked REFERENCE allocates nothing, so RSS only shows BYTES when the referent is
fresh per iteration. **A 0 in an RSS column does not retire a row here** — this
is the third time this family has produced a confident wrong "clean" from an RSS
table, and the ticket above records the other two.

The slice row is the exception and the expensive one: it allocates a fresh
backing buffer per call, so it IS RSS-visible at **200 bytes/call**.

## REPRO

`devdocs/progress/repro-n-a-variant-carried-method-result-leaks.npy`

## WHY 85

Getters are ubiquitous and this needs no unusual spelling — no discard, no
conditional, just `return self.something` consumed normally. Found while
answering a lekkerzeilen census: 27 `return self.<attr>` sites across 21 methods
in that package, plus a wide family of `@property` accessors returning
`self.a.b` that the narrow grep missed. `Vessel.state` is read inside a physics
step running at 120 Hz, and `Tab.shown` returns a SLICE per visible panel per
frame — the 200 b/call row.

## LOCATED -- IT IS THE CALL SITE, NOT THE RETURN, AND THERE ARE TWO DEFECTS

objtrace, three shapes in one program on one long-lived referent, so the
refcount is cumulative and every step is visible:

```
A: a = h.q        direct attribute read, BOUND   R rc 1->2        1 retain, 1 release   BALANCED
B: h.give()       getter call, DISCARDED         R rc 2->3        1 retain, none        LEAKS +1
C: c = h.give()   getter call, BOUND             R rc 3->4, 4->5  2 retains, 1 release  LEAKS +1
```

Row A settles the return: **the retain emitted on the way out of `give()` is
CORRECT.** Boxing `self.q` -- a borrowed lvalue -- into the result variant must
take its own +1, and that is the `tyClass` -> variant arm doing its job. What it
produces is an owned +1 handed to the caller, exactly as
`IRNodeOwnsFreshCallResult` and the frontend's stated invariant both say.

**DEFECT 1 -- THE BIND RETAINS A RESULT THAT ALREADY OWNS ITS +1.**
`ir_codegen.inc:11670`, in `IR_VAR_STORE`'s `tk = tyVariant` arm (the 16-byte
variant-to-variant copy):

```pascal
IREmitNode(IRB[node]);                 { rax = src addr }
EmitVariantRetain;                     { <- UNCONDITIONAL }
```

The two arms directly beneath it in the same `case` do not do this. The
`tyAnsiString` arm asks `IRNodeOwnsManagedStr`; the `tyClass` arm asks
`IRNodeOwnsManagedObj`. Each carries a comment saying in its own words that a
CALL result is *"already OWNED (+1, ownership transfers)"* and that retaining it
*"leaked one handle per boxed call result"*. **The variant-to-variant copy is the
third member of that family and never got the discrimination**, so a
variant-carried call result is retained as though it were a shared lvalue.

The ticket cited beside the `tyAnsiString` arm --
`bug-a-runtime-variant-heap-grows-unbounded` -- is the tell: this same defect was
found and fixed for strings, then for objects, and the variant copy was left.

**DEFECT 2 -- A DISCARDED VARIANT RESULT IS NEVER RELEASED** (row B).
`IRDropManagedResult` has a `tyAnsiString` arm, a dyn-array arm, and now a
`tyClass` arm. It has no `tyVariant` arm, so the owned +1 on a discarded
variant-carried result is dropped on the floor.

## THE ORDER MATTERS, AND THE NATURAL FIRST PATCH IS THE ONE THAT CANNOT WORK

The obvious shape for defect 2 is the one the `tyAnsiString` arm uses: spill into
a hidden local of that type and let the rebind/scope-exit release it. **That
cannot work while defect 1 stands**, because the spill IS a variant-to-variant
copy -- it would retain the result (a second +1) and release only the previous
iteration's, so the original +1 still leaks and a new one joins it. Fix the copy
first; then the spill takes ownership and the next overwrite frees it.

## RETRACTED 2026-09-15 -- "THE HARD PART" AS BANKED WAS WRONG, TWICE OVER

The section that stood here claimed the source operand at the copy site is *"the
ADDRESS of a variant slot, not the call"*, that
`IRNodeOwnsFreshCallResult(IRB[node])` *"answers False and cannot be used
directly"*, and prescribed a `SymIsCtorResultTemp`-style flag. It also told the
next reader to probe the site before building on it. That instruction was the
only part that survived contact.

**Probe at the site** (`WriteLn` of `IRKind[IRB[node]]` and both predicates,
compiler rebuilt to its own fixedpoint, `converged after 1 round(s)`):

```
VCPROBE srckind=30 srcA=28 ownsfresh=1 ownsobj=1
```

`srckind=30` is `IR_VIRTUAL_CALL` -- the call ITSELF, not a temp address -- and
`IRNodeOwnsFreshCallResult` answers **True**. There is no spill, no flag needed,
and the prescribed fix was a solution to a problem that does not exist. So the
guard looked like a one-liner, the same shape the two arms below it already use:

```pascal
if not IRNodeOwnsManagedObj(IRB[node]) then
  EmitVariantRetain;
```

**Built, that guard SEGFAULTS.** Which is the real finding, and it is the
opposite of a hard part being absent.

## THE ACTUAL DEFECT: THE VARIANT CARRIER HAS TWO CALL CONVENTIONS

Measured at `cfee5d6255237332` (landed) against the guard build `745b82d21c1b`:

| shape | callee returns | needs caller retain? |
|---|---|---|
| `c = h.give()`, `return self.q` / chained / indexed / sliced | **OWNED (+1)** | NO -- retaining is the leak |
| `nm, fn = <list element>`, `open()`, pylist/tuple internals | **BORROWED** | YES -- not retaining is a use-after-free |

`IRNodeOwnsFreshCallResult` answers **True for both**, because it is a claim
about the NODE SHAPE ("is this a fresh call result") and not about the callee's
convention. Its own header says so: *"any fresh call result"*. That assumption
is TRUE on the string and tyClass carriers and FALSE on the variant one.

**Why the OWNED half owns.** The IR of the callee settles it -- `return self.q`
is ITSELF an `IR_VAR_STORE tk=22` whose source is a `load_mem`, so it takes the
very same unconditional-retain arm and returns +1. Correct: `self.q` is
borrowed, and the result must own. The caller then hits the SAME arm with an
`IR_VIRTUAL_CALL` source and retains a second time. That second retain is the
leak, and the two retains are emitted by one line of code.

```
H.g_obj:  3: load_mem a=2 tk=6
          4: lea a=544 [sym=$pyresult] tk=17
          5: var_store a=4 b=3 c=6 tk=22      <- retains here, correctly
```

Note `H.g_self` (`return self`) returns on tk=6, a DIFFERENT carrier, and is not
part of this at all -- it reads 0 bytes/call throughout and is a control, not a
case.

**This is the same distinction `2dc0d6878` drew for the tyClass arm of
`IRDropManagedResult` this same week**, where the discriminator is
`UnitIsPyModule(ProcUnitIdx[callee])`: a Pascal library facade's result is
BORROWED, a NilPy method's is OWNED. I solved it once, in this family, and then
reached for a node-shape predicate that cannot express it.

## THE POSITIVE CONTROL THIS TICKET WAS MISSING

`test/test_nilpy_a_borrowed_variant_result_is_not_moved.npy` -- committed here
because the over-broad fix is the OBVIOUS fix and the next reader will write it.

The existing repro cannot catch it usefully: under the broken guard it
segfaults, but only after a 12000-iteration warmup of twelve unrelated shapes,
and the visible symptom was a corrupted `print` (`meas meas` for
`meas LONGLIVED obj`) that varies run to run. Every row of it passes in
ISOLATION -- I bisected all nine, all rc=0 -- so a reader who minimises the way
one normally minimises concludes the guard is fine.

The control is four lines of ordinary Python and fails LOUDLY and
DETERMINISTICALLY:

```python
rows = [("alpha", f1), ("beta", f2)]
for i in range(4000):
    for nm, fn in rows:
        ...
```

guard build: `IndexError: tuple index out of range`. Landed: `UNPACK OK`.
A tuple unpack in a for-loop is not an exotic shape; it is what the repro's own
driver loop is written in, which is why the repro crashed in its driver rather
than in any row under test.

## WHAT THE FIX NEEDS, RESTATED

Carry the callee's PROVENANCE to the variant-copy site -- the thing
`IRDropManagedResult` already reads at AST level via `ASTIVal[astNode]` as the
callee proc index. At the `IR_VAR_STORE` arm in `ir_codegen.inc` that index is
not in hand for `IR_VIRTUAL_CALL` (`IRA` is a slot, not a proc), so the
discrimination belongs where the AST is still available -- flag the IR node at
BUILD time in `ir.inc` and let the emitter read the flag. `SymIsCtorResultTemp`
remains the worked precedent for the flagging TECHNIQUE; it was the wrong
diagnosis, not the wrong pattern.

**Defect 2 (no `tyVariant` arm in `IRDropManagedResult`) is unchanged and still
real**: a discarded `h.give()` shows +1 with no release. But it is now clear
that Defect 2 must not be fixed by releasing every discarded variant call result
either -- a discarded facade call returns borrowed, and releasing it is the same
use-after-free from the other end. Both defects need the same provenance bit,
which is an argument for building that bit ONCE rather than twice.

## ATTEMPT 2 ALSO FAILED, AND IT NARROWS THE QUESTION TO ONE SENTENCE

Built the provenance discrimination the section above prescribes: read the
callee proc index off the call node (`IRA` for `IR_CALL`, `IRC` for
`IR_VIRTUAL_CALL` -- both already operands, no new state) and ask
`UnitIsPyModule(ProcUnitIdx[cp])`, exactly as `IRDropManagedResult`'s tyClass
arm does. Self-hosts, `converged after 1 round(s)`, binary `37acfdbcc84d`.

**Results, all four fixtures:**

| | pre-fix `cfee5d62` | node-shape guard `745b82d2` | provenance guard `37acfdbc` |
|---|---|---|---|
| VARCARRY (the leak) | FAIL, 5 rows | -- | **OK** |
| BORROWVAR (the use-after-free) | OK | IndexError | **OK** |
| Track N tier | green | -- | **SEGV** |

It fixes the leak, keeps the borrowed half alive, and **breaks
`test_nilpy_a_module_qualified_def_is_a_value_across_modules`**, which the
NilPy tier caught. Under `-dPXX_HEAP_DEBUG`:

```
pxx-heap: RELEASE of a FREED object 0x00007d07ad0004a8
pxx-heap: RETAIN of a FREED object  0x00007d07ad000230
```

`rax` at the fault holds `0x39202c38202c3753` -- ASCII text -- so the block was
freed and its memory reissued to a string. A genuine use-after-free, not a leak.

## WHY THE UNIT IS THE WRONG INSTRUMENT, MEASURED RATHER THAN ARGUED

`UnitIsPyModule` is a proxy for "did this callee's return leave +1", and the two
come apart because **NilPy has TWO return paths onto the variant carrier**, not
one. From `PXXDBG=a.ir` on the two callees:

```
H.give   (main program, `return self.q`)
  3: load_mem a=2 tk=6
  5: var_store a=4 b=3 c=6  tk=22      <- c=6: source is tyClass, BOXING path

via      (module, `return h()`)
  7: call a=1852 c=6 tk=22             <- pyvar_callv0, a Pascal facade
  9: var_store a=8 b=7 c=22 tk=22      <- c=22: variant-to-variant COPY path
```

`IRC` on the store is the SOURCE KIND. The arm under guard is only the `c=22`
copy; the `c=6` boxing arm is a different piece of code that retains
regardless. So `H.give` owns its result for a reason that has nothing to do with
its unit, and `via` owns or borrows its result for a reason that has nothing to
do with its unit either. **The unit test agreed with the truth on the rows I had
measured and disagreed on the rows I had not**, which is the definition of a
proxy rather than an instrument.

Confirming that the seam is exactly here and not elsewhere: restricting `owned`
to `ProcUnitIdx < 0` (main-program procs only) turns all three fixtures green --
tier rc=0, VARCARRY OK, BORROWVAR OK. **That is NOT landed and must not be.** It
is the same proxy with the failing half deleted, it leaves every module-defined
method leaking, and shipping a predicate known to be wrong in a case nobody can
explain is the compiler-appeasement workaround CLAUDE.md refuses. It is recorded
because it localises the seam for the next attempt, not because it is a
candidate.

## WHAT THE FIX ACTUALLY NEEDS, IN ONE SENTENCE

**Whether a call result arrives owned is a property of the CALLEE'S OWN RETURN
LOWERING, so it must be recorded when that return is lowered -- not inferred at
the call site from anything about the callee.**

Concretely: a per-proc flag (`ProcVariantResultOwned`, the shape
`ProcRetFixedArrBytes` and `ProcUnitIdx` already have in defs.inc) set at the
point the return's `IR_VAR_STORE` is built in `ir.inc`, recording whether that
store left +1. Pascal facades never go through NilPy return lowering and so
default to False -- borrowed, retain -- which is the safe default and the one
that is correct for them today.

**The ordering question is the real work and is why this is not a small
change**: a call site can be lowered before its callee. `PyMarkVariantParamsByRef`
is the in-tree precedent for exactly this problem -- it moved an ABI decision to
signature-REGISTRATION time for the same reason -- and its own ticket
(`done/bug-n-a-callee-declared-below-its-caller-gets-the-argument-by-the-wrong-abi`)
records what goes wrong when the decision is read from the body instead. Read it
before starting.

## DO NOT ATTEMPT A THIRD FIX FROM A PREDICATE THAT MERELY ANSWERS

Three attempts in this family have now failed the same way: the probe answers,
the answer is correct, and the question is wrong.

1. banked: "the operand is a temp address, the predicate cannot answer" -- it is
   the call, and it answers.
2. `IRNodeOwnsManagedObj` -- answers True, and asks about node SHAPE.
3. `UnitIsPyModule` -- answers, and asks about the callee's FILE.

**The next patch must be justified by what the CALLEE'S RETURN DID, and the
justification must be a measurement of that, not of a correlate.** Both
fixtures must be run, and so must the NilPy tier -- the tier is what caught
attempt 2, and neither fixture could have.

## THE ORIGINAL SECTION, KEPT SO THE RETRACTION IS CHECKABLE

## THE HARD PART, AND IT HAS A WORKED PRECEDENT IN-TREE

At the copy site the source operand is the ADDRESS of a variant slot, not the
call: a variant-returning call is materialised into a temp, so `IRB[node]` is
that temp's address and `IRNodeOwnsFreshCallResult(IRB[node])` answers False. It
cannot be used directly.

**`SymIsCtorResultTemp` already solves exactly this**, and `defs.inc:4401`
describes this failure in its own words: *"the spill hides the construction from
every consumer: the AST-level arms see AN_CALL and are right, the IR-level
variant store sees IR_LOAD_SYM and retained a second time."* The remedy there was
to FLAG the temp at the one place it is minted and let `IRNodeOwnsManagedObj` ask
about the flag. Same shape here: flag the hidden temp that receives a
variant-typed call result, and give the variant-copy arm a predicate that asks.

**VERIFY THE OPERAND SHAPE WITH A PROBE AT THE SITE BEFORE BUILDING THAT.** Print
`IRKind[IRB[node]]` and what the operand resolves to. Two claims in this
family's history were wrong because they were read off a probe run against a
`compiler/pascal26` that was not the fixedpoint of its own sources; do not add a
third.

## FIXED 2026-09-15 -- THE DIRECT-CALL PATH ALREADY HAD THE GUARD; THE SHARED HELPER NEVER GOT IT

**`IRAppendCall` has cleared the variant scratch slot before every hidden-dest
call all along** (`ir.inc`, `if Procs[procIdx].RetType = tyVariant`), and its own
comment describes this ticket's defect in this ticket's later words:

> *"A variant hidden-dest call OVERWRITES the temp raw (the callee copies 16
> bytes into [dest]), so a managed payload from the temp's previous life -- the
> SAME sym on every trip through a loop -- leaked once per call: ~40 B/iter of
> bound pairs in the uforth env-build."*

The **four call sites that route through the shared helper `IRBuildHiddenDest`**
-- three `IR_CALL_IND` arms and the `IR_VIRTUAL_CALL` one -- never got the
sibling. That is the whole bug, and it is why a PLAIN FUNCTION returning the
identical value through an identical `IR_VAR_STORE` was clean while a METHOD
leaked: **one arm had the guard, the other never did.** The knowledge was not
missing from the codebase; it was missing from the other path.

`normalise-dont-special-case.md`'s *"fixed one arm of a double case, grep for
the sibling before closing"* arriving from the wrong end, and invisible to any
review that reads one path at a time.

### The fix

The clear moves INTO `IRBuildHiddenDest`, so all four sites inherit it, matching
what `IRAppendCall` does. Unconditional, for `IRAppendCall`'s own stated reason:
the variant-slot protocol is mode-universal, so this is about the SLOT's
protocol and not about the callee's ownership convention. The scratch is also
marked `SymIsHiddenArgTemp` so codegen nil-inits it -- without that the FIRST
clear dispatches on a stale stack tag.

### THE ORDERING CONSTRAINT, AND IT IS THE PART THAT WOULD HAVE BEEN UNATTRIBUTABLE

**The hidden dest must be built BEFORE the call node.** The clear is an
`IR_CALL` with `IRIVal=1`, and the top-level emitter walks nodes in **INDEX
ORDER** (`ir_codegen.inc`, `IR_CALL: if IRIVal[i] = 1 then IREmitNode(i)`). All
four sites previously read:

```pascal
Result := IRAppend(IR_VIRTUAL_CALL, ...);
if ABIRetViaHiddenDestProc(cpi) then
  IRCallDest[Result] := IRBuildHiddenDest(cpi);      { <- clear lands AFTER }
```

so a clear emitted from there would have run **after the callee filled the
slot** -- freeing the value being returned. A use-after-free, in the same family
that already shipped one, and it would have presented as a plausible patch
failing somewhere unattributable. All four hoist the dest above the call node
and assign `IRCallDest` afterwards.

Raised by lekkerzeilen-c8 as deserving a line here rather than only in a commit
message, which is why it is one.

### Verification -- all three instruments the ticket named, plus the routes

| | |
|---|---|
| `GETTERLIVE` (bytes) | all 13 rows LEAKFREE, control MOVES — was 5 rows leaking |
| `RECVLIVE` (values) | all INTACT, control MUTATED — the premature-free half |
| `VARCARRY` (bytes, the original repro) | all 14 rows LEAKFREE, **including `disc_obj` 72 and `disc_slice` 200** |
| NilPy tier | see the resolution line |
| short-circuit | 0 across `never`/`always`/`alt`, receiver's attribute intact, and the clear sits **inside** the branch (BB4) in the IR dump — not hoisted out of it |
| objtrace, site-attributed | every `A` now has a matching `F`; previously the lists settled at rc=1 and were never freed |
| self-host | `converged after 1 round(s)`, fixedpoint verified |
| Pascal reach | an interface method returning a Variant, 200000 calls in a loop, holds at maxrss 392 kB |

**The slice row is the same defect.** `disc_slice` at 200 bytes/call was written
up in this ticket as "a separate surplus, deliberately not asserted". It is not
separate; it went to zero with everything else.

### What this retires

The three predicates tried at `IR_VAR_STORE` were all correlates because **the
store is identical on both paths** — the difference was upstream, in whether the
slot had been cleared. No predicate at the store could have separated them, and
the ticket's own `ProcVariantResultOwned` design (record ownership at return
lowering) was aiming at the same wrong layer: ownership was never in doubt, the
slot's previous occupant was.

## THE NEIGHBOURING WRITE SITES ARE CLEAN — MEASURED 2026-09-15, NOT ASSUMED

The fix repairs ONE write site: the caller-owned scratch built by
`IRBuildHiddenDest`. The obvious question a reader will ask is whether the other
sites that land a managed payload have the same hole, and it is worth answering
with rows rather than with a grep, because the sibling arms
(`IR_VAR_STORE:11774`, `IR_VAR_BOX:11821`) clear by inspection while the *field*
store and the *operator* return path do not appear in that argument at all.

Measured 200k iterations per row, under the fixed compiler (`79551a1b6d05f02e`)
and under the archived `cfee5d62255237332`, identical results on both — so the
fix neither repaired nor disturbed these sites.

**READ THAT AS "UNDISTURBED BY THIS FIX", NOT AS "NEVER DEFECTIVE" — THE
ARCHIVED BINARY IS NOT A BEFORE-CONTROL FOR TWO OF THESE ROWS.** The operator
row and the discarded-constructor row were REAL defects, found and fixed
2026-09-14/15 and already fixtured in
`test_nilpy_a_user_object_does_not_leak_because_of_how_its_value_is_consumed.npy`
(`PyUserArithCall1` retained the dunder's result on the way into the Variant
when the NilPy routine already handed back an owned +1; the discarded `P(1, 2)`
was the same conduit with nobody to consume it — 63-64 and 56 bytes/call
respectively). `cfee5d62` POSTDATES those fixes, so both binaries contain them
and the agreement between the two columns says nothing about whether the site
was ever broken. This paragraph asserted the stronger claim for about an hour
and it was a control drawn from the wrong population — the archived binary is a
before-control for the HIDDEN-DEST defect and for nothing else. What the rows do
establish is the thing they were run to establish: this fix opened no hole at
the neighbouring sites.

| shape | what it writes | bytes/op, both compilers |
|---|---|---|
| `A + B` on a user class (`__add__` -> fresh Vec3) | operator dispatch result | 0 |
| `A * s` (`__mul__`) | operator dispatch result | 0 |
| `A + B * 0.5` | nested operator dispatch | 0 |
| `self.pos = self.pos + self.vel` | FIELD STORE over a live object | 0 |
| `self.tag = "x%d" % i` | field store over a live string | 0 |
| `self.trail = [i, i, i]` | field store over a live list | 0 |
| `self.x = i * 1.0` | field store, unboxed payload | 0 |
| `v = v + BD.vel` | local rebind, same expression | 0 |
| `Vec3(...)` discarded | constructor result dropped | 0 |
| *control:* `held.append(Vec3(...))` | deliberately retained | **129** |

The CPython oracle agrees row-for-row on the field-store fixture, control
included (105 bytes/op there).

**BOTH CONTROLS ARE LOAD-BEARING AND THE FIRST CUT OF THIS PROBE HAD NEITHER.**
Every row above asserts a number stays at zero, and zero is also what a probe
prints when nothing ran — the collision this handbook names under "if the
machinery did nothing at all, would this row still pass?". Two independent
guards, because they fail differently:

- **ROUTE control** — the fixture prints the computed value before the loops
  (`route add -> 1.500 2.250 3.125`, `route step -> 2.0` after two steps), so a
  row cannot read 0 because `__add__` was never reached or the rebind never took
  effect. This is the "does my probe reach the thing under test BY THE ROUTE
  under test" guard, and on an operator it is a real risk: a frontend that fell
  back to a builtin numeric add would print the same zero.
- **LEAK control** — a retained allocation per iteration, which must MOVE. It
  reads 129 bytes/op on both pxx binaries and 105 under CPython, so the
  instrument is demonstrably able to see a leak of exactly the size these rows
  are asserting the absence of.

**SCOPE, AND IT IS NARROWER THAN THE TABLE LOOKS.** Every attribute in the
fixture holds a float, a str, a list or a Vec3 of floats. The rows say nothing
about a field store over a nested container, a bound method, or a ctypes handle,
and the residual for the lekkerzeilen demo's own per-step leak is NOT closed by
them — that is the lekkerzeilen seat's stage-2 bisect, which has the demo landed
on `body.step` at 44.2 net-unfreed objects/step by its own tier-1 marker census.
What these rows do establish is that four families are off that list: the
hidden-dest family repaired here, operator dispatch, the field store, and the
discarded constructor.

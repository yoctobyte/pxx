# Handoff — hunting the remaining lekkerzeilen bugs

Written 2026-09-15 by the Track N seat that spent the night on variant typing,
for the seat picking it up. **15.5KB at 2026-09-15, and that number is a
lower bound with a date on it. Read it whole — it is sized to be read whole, and
everything in it is from tonight.**

The demo tree is `/home/neo/lekkerzeilen`, the **OWNER'S** checkout: read it,
never commit there. The peer seat that produced most of the measurements below
(`lekkerzeilen-c8`) closed out on 2026-09-15 and left a correction of record —
see **Provenance**. **Nobody is holding that tree now**, so the coordination
rule that matters is the other one: this checkout is shared, and you announce
heavy runs.

---

## What you are hunting

Not "make lekkerzeilen compile" — it compiles and runs. You are hunting the
bugs that make **ordinary Python** go wrong under NilPy, found by driving a real
program rather than by triaging the backlog. Every item below came out of that,
tonight, and each one is a reproducer of ten lines or fewer.

**Everything below is now filed**, so `tools/progress.sh ready --track N` finds
it without this note. The two that were unticketed when this was written are
`bug-n-attribute-access-directly-on-a-dunder-result-segfaults` (85) and
`bug-n-annotating-a-dunder-operand-breaks-the-operator-on-a-variant-receiver`
(75). **This note is the group, and the group is the unit of work** — those two
plus §3 and §4 are one subsystem and share instruments.

---

## 1. THE WORST — `(a + b).x` SEGFAULTS  (prio 85)

```python
class V:
    def __init__(self, x):
        self.x = float(x)
    def __add__(self, o):
        return V(self.x + o.x)

def known():
    a = V(1.0)
    b = V(2.0)
    return (a + b).x          # attribute access DIRECTLY on a dunder result

print("known %s" % known())
```

CPython `3.0`. pxx **SIGSEGV, no output at all.** The control is one line
different and is fine:

```python
    c = a + b
    return c.x                # "known 3.0", rc=0
```

**`(dunder result).attr` dies; binding the temporary first does not.** That is
the entire delta. No annotations anywhere in the file, so it is not the operand,
not the receiver, and not reachable from tonight's store fix. Reproduces at
`--threadsafe`, with no flags, at `-O0` and `-O1`; `setarch -R` gives the same
139, so nothing is being hidden by ASLR.

Smells like the temporary's lifetime — the result released before the field is
read — which puts it next door to the hidden-destination defect fixed in
`e59efc3f5`, at a different site. **Start with `-dPXX_OBJTRACE` and grep the
address**, not with the parser.

Unknown and worth five minutes: whether it is a REGRESSION. Nobody built it
against `4452ec06`. The compiler delta from there to the current binary is one
40-line additive function, so that bisect has exactly one step.

## 2. ANNOTATING A DUNDER OPERAND BREAKS THE OPERATOR ON A VARIANT RECEIVER  (prio 75)

Two programs, byte-identical except for one annotation:

```python
class V:
    def __init__(self, x):
        self.x = float(x)
    def __add__(self, o):          # vs.  def __add__(self, o: 'V'):
        return V(self.x + o.x)

class H:
    def __init__(self):
        self.a = V(1.0)
        self.b = V(2.0)

def known_receiver():
    a = V(1.0); b = V(2.0)
    c = a + b
    return c.x

def variant_receiver(h):           # h is bare, so h.a is a VARIANT
    c = h.a + h.b
    return c.x
```

```
bare        known_receiver 3.0   variant_receiver 3.0                        rc=0
annotated   known_receiver 3.0   TypeError: expected a number, got object    rc=217
CPython     3.0                  3.0
```

Known receiver: fine both ways. **Variant receiver: fine bare, raises
annotated.** The raise is `PyTypeError(p^.VType, 'a number')` in `pyvar_to_float`
(`pylib.pas:9433`) — the generic variant-add arm taking the NUMERIC path with an
object operand, because the annotated dunder no longer matches what it matches
on.

**WHY THIS IS URGENT AND NOT COSMETIC.** The operand annotation is the single
biggest code-generation win measured tonight (§5). In real code a receiver is a
variant most of the time — off a bare parameter, a container, a field of
something untyped. **So the annotation that produces that codegen is the same
annotation that breaks the operator at most of the sites that would benefit**,
with a runtime message pointing nowhere near the edit the user made.

Likely **one fix, not two**: if variant dispatch consulted the annotated
signature the way the static path does, both the crash and the codegen win come
from the same place.

**AND THERE IS A SAFE CUT, MEASURED AFTER THIS WAS FIRST WRITTEN — YOU DO NOT
HAVE TO CHOOSE.** The operator dunders turned out never to be load-bearing for
the code-generation win (§5). Annotating only NON-dunder method parameters gets
the whole win and the program runs. **So the shippable recommendation is:
annotate method parameters and constructor parameters; leave operator dunders
bare until the variant dispatch is fixed.** That is what goes in the NilPy docs.
This bug then stops being a blocker and becomes an ordinary ticket — still worth
fixing, no longer holding guidance hostage.

## 3. FILED, BUT THE TICKET UNDERSTATES IT — augmented assign on a bare parameter

`s.velocity += s.other` with `s` a **bare parameter**: `rc=217`,
`TypeError: expected a number, got object`. **Identical with and without an
operand annotation on `__iadd__`**, so annotation-indifferent. With an `__add__`
also defined on the class it **SIGSEGVs instead**.

`bug-n-augmented-assignment-to-an-unannotated-parameter-silently-loses-the-mutation`
(prio 70) is about the mutation being silently LOST. These throw. Same site,
different observable — check whether it is one cause before splitting it.

## 4. FILED AND OPEN — the rest of the variant-typing group

All in `backlog-nilpy`, all from the same subsystem, worth holding as one group:

- `bug-n-a-class-level-field-annotation-is-discarded-unless-the-class-is-a-dataclass` (75)
  — six routes set a field's type, and a bare `x: float` at class level is the
  one that is discarded. `PyClsAttrEqIdx` deliberately steps OVER the annotation.
- `bug-n-a-def-returning-a-multi-hop-attribute-chain-is-typed-by-the-hop-before-last` (80)
  — residual: `return mk().v` still wrong after `f40ffd630`.
- `bug-n-a-variant-comparison-heap-allocates-a-box-per-evaluation` (75).
- `bug-n-a-bitwise-or-shift-operator-on-a-variant-user-object-never-reaches-its-dunder` (45)
  — blocks five augmented operators.
- `bug-n-a-for-in-loop-that-rebinds-its-own-name-leaves-the-thread-registry-undrained` (40).

## 5. THE PERFORMANCE FINDING — it is the RECEIVER, and the worst spelling is the CONSTRUCTOR

`backlog-nilpy/feature-n-specialise-a-dunder-body-on-the-operand-type-the-call-site-already-knows.md`
(80) holds the measurements. The short version, because it reframes what to look
for:

An attribute read on a receiver whose class is not statically known runs the
FULL dynamic protocol — `pydynattr_get_v` -> `PyDynAttrKey` -> `pystr_of` ->
`TPyDict.indexof`, building a STRING KEY and probing a hash table, per attribute
per operation. A **field** read goes from 0 calls to 8. A **property** read
barely moves (22 ops / 3 calls annotated, 25 / 4 bare) — because a property was
already a call. So `@property` is not the tax; the unresolved receiver is.

Measured on real code, annotating the operand:

```
method          before (bare operand)        after (annotated operand)
Vec3.__add__     6260 B, 210 calls,  0 SSE  ->   873 B, 18 calls,  3 SSE
Vec3.dot         6645 B, 225 calls,  0 SSE  ->   579 B,  4 calls,  5 SSE
Quat.rotate     24674 B, 864 calls,  0 SSE  ->  2175 B, 18 calls, 30 SSE
```

Thirty float instructions where there had been NOT ONE, in a method whose source
is nothing but floating-point arithmetic.

**But resolving the receiver is not sufficient, and this is the part to chase.**
`Grid.at` in the demo has **zero** `pydynattr` calls — receiver fully resolved —
and still **zero float instructions in 12.5 kB**. `self.cell` resolves to a
*slot*; what is in the slot has no type, because `__init__` took bare
parameters:

```python
def __init__(self, cols, rows, cell, x0, z0, base, data):
    self.cell = cell          # cell has no type, so the field has no type
```

Same fixture, `__init__` parameters annotated: **1337 B -> 280 B, 48 calls -> 1,
0 -> 3 SSE, 0.38 s -> 0.02 s**, identical output. Nineteen times.

**The chain is: bare `__init__` parameter -> untyped field -> every arithmetic op
on that field is a runtime call.** It needs no dunder and no numeric code, only a
constructor written the way everybody writes constructors. Unlike §2 this is a
plain parameter annotation at a definition, so none of tonight's hazards touch
it.

**MEASURED: THE DANGEROUS ANNOTATION WAS NEVER THE ONE PAYING.** Five arms, all
built on one compiler sha with a guard refusing to print if it moved:

```
arm       Vec3.__add__   Quat.rotate   Grid.at   TiledGrid.at
b_no              6260         24674     12492          19608
b_op               873          2175     12492          19608   <- CRASHES (§2)
b_op2             6260          2175     12492          19608   <- runs
b_orig            6260         24674     12492          19608
```

`b_op2` is nine NON-dunder method-parameter annotations. It gets `Quat.rotate`
from 24.7 kB to 2.2 kB — the entire win — **and the program runs** (it ends on
the 60-second timeout, not on a crash). The dangerous operand annotation bought
only `Vec3.__add__`, which the demo barely executes.

**No frame rate is quoted for any of these arms, deliberately — see Provenance
below.**

**AND THE BIGGEST TARGETS ARE NOT IN `math3d.py` AT ALL:**

```
function                 bytes   calls   SSE   pydynattr
Grounding.accumulate     66127    2286     1          37
Craft._sail_her          29692     928     0          34
Body.step                21304     732     0          10
Buoyancy.accumulate      19256     605     2           8
Vessel.step              17535     626     0          14
```

**`Grounding.accumulate` is sixty-six kilobytes of machine code containing ONE
floating-point instruction.** Every `accumulate` in the integrator takes
`(self, state, env, acc)` with all three bare.

**Census across the whole demo: 95 classes, 82 constructors, 334 constructor
parameters, ZERO annotated.** Every field in the program is untyped. That is not
a criticism of the demo — it is how Python is written and on CPython it costs
nothing — but it means essentially the whole program compiles down the dynamic
path, and the `__init__` lever applies to all of it.

The diagnostic machinery already half exists — the compiler says
`error: Nil Python: cannot infer the type of field self.x0 - annotate it` when
inference FAILS. It does not fire when inference SUCCEEDS at `variant`. A WARNING
on that case, in a class whose methods do arithmetic on the field, would let
users find this themselves. That is probably the highest-leverage small feature
in this whole note.

## 6. WHERE THE DEMO'S TIME ACTUALLY GOES

By caller attribution (rbp chains, 58 of 70 samples, bucketed by innermost
demo-source frame): `Grid.at` 13.8%, `World.number` 12.1%,
`Vessel.__prop_get_state` 8.6%. **`Vec3.__add__` does not appear at all**;
`__iadd__` and `Vec3.create` are one sample each.

**Weight that evidence carefully: the chains come back SHALLOW.** The dynamic
dispatchers and hand-written runtime helpers do not set up `rbp`, so the walk
identifies the CALLEE reliably and the CALLER only sometimes — `Grid.at` appears
alone in 8 samples with its caller unrecoverable. Treat the buckets as a
ranking of callees, not as a call graph, and prefer skip-sweep evidence where
the two disagree.

So the vector dunders are noise in THIS program and a 10x on them cannot move
the frame rate. Hold the two claims apart: codegen improves enormously
(measured), and this program spends its time elsewhere (measured). **An
end-to-end null is Amdahl and refutes nothing.** Say that before you run the arm,
not after.

---

## Provenance — what the peer seat vouches for, in its own words

It closed out before this note was final and left a correction of record. **Use
this to decide how hard to lean on each number above.**

**Vouched unreservedly:**
- every STATIC count — bytes, calls, SSE, `pydynattr` — all read from one
  compiler's binaries with a guard that refuses to print a table if the sha
  moves;
- the three fixtures with matched controls: `(a + b).x`, the operand pair, and
  the `__init__` pair at 19x;
- the caller attribution, **with the shallowness caveat attached**;
- the 334-parameters / 0-annotated census.

**NOT vouched — do not quote, and do not let a later reader mistake them for
results: ANY end-to-end frame rate measured on 2026-09-15.** A superseded batch
runner was killed by the PID of its shell WRAPPER rather than the script, so the
script survived and ran its own interleaved A/B for about six minutes alongside
its replacement — two demo processes each measuring the other's contention, both
printing entirely normal-looking numbers. Every row in that window is void on
both sides, and round 1 of the replacement was discarded with it. **The only
reason the contamination could be dated is that the runner logs the load average
on every row.** Do that.

The last frame rates anyone may quote for this demo predate the day's arms:
**2.18 fps baseline, 0.66 with vsync.**

Still running, unattended and self-logging, with predictions timestamped ahead
of the results in `$SP/PREREG-water-sim-bisect.md`: `$SP/n25-out.txt` (the
interleaved four-arm table) and `$SP/n26-out.txt` (the `Grid`/`TiledGrid`
constructor arm). **Nobody needs to wait for them** — score them honestly
against the pre-registration when you get there, or ignore them.

## Working rules that cost real time tonight

- **A KILL IS NOT DONE UNTIL YOU HAVE LOOKED FOR THE JOB BY NAME.** Three
  instrument failures of one family in one night on the peer seat: `pgrep -f`
  matching its own shell, a wait-guard firing in the gap between two runs, and
  the wrapper-PID kill above. **In all three the command SUCCEEDED and its
  effect was not what its name implied** — which is why none of them announced
  itself and why the third one produced a plausible table instead of an error.

- **The checkout `/home/neo/frank-user` is SHARED with the peer seat.** Always
  stage explicitly; never `git add -A`. Leave
  `backlog-nilpy/addendum-the-property-warning-fires-on-the-safe-pair-and-is-silent-on-the-lethal-one.md`
  alone — it is theirs and untracked.
- **Do not rebuild `compiler/pascal26` while anyone is measuring.** It replaces
  the binary under their build and yours. Announce heavy runs; they will too.
- **A compiler sha in a provenance file may not be a commit.** `6f2f936350462995`
  is an uncommitted working tree. Write what it is beside it or nobody can
  resolve it later.
- **Catch the raise before you bisect.** The peer found the demo's real crash
  frame by breaking on `PyTypeError` and walking rbp — one 60-second run, no
  builds. Four bisect builds would have been eleven minutes and told them less.
- **CHECK THE ARITHMETIC OF THE EVIDENCE AGAINST THE ARITHMETIC OF THE CLAIM —
  A FACTOR OF TWO BETWEEN THEM IS THE REAL MECHANISM TRYING TO GET YOUR
  ATTENTION.** The peer seat named this as the one habit to inherit from the
  night, and it earned it by getting the same thing wrong twice: a `__slots__`
  claim, and a reading that `@property` access was itself the expensive thing.
  **Both times a count did not match the theory's arithmetic and the theory
  won.** The four-accessor table killed both at once — a property read is 22 ops
  / 3 calls annotated against 25 / 4 bare, which is nothing, while a FIELD read
  goes 0 calls to 8. The property was already a call; that is the whole
  explanation, and the numbers had been saying so before anyone listened.
- **DISCOUNT FOR A STATED REASON, AND THEN CHECK THE REASON.** Both seats
  mis-predicted tonight and the useful account is not "I am biased low" or
  "trust fixtures more". The peer discounted a fixture's transfer on Amdahl
  grounds, via caller attribution — and then found that same attribution is
  shallow because our dispatchers and hand-written helpers do not set up `rbp`.
  **The instrument was weak in exactly the direction that made the discount too
  large.** A discount you cannot name the reason for is a guess; one you can is
  a claim about an instrument, and instruments can be checked.
- **Vary the axis you are NOT suspicious of.** Four numbers were wrong tonight
  before the fifth was right: an inert benchmark (both arms compiled identically
  — `PXXDBG=n.locals` showed `tk=19` on both), a contaminated one (the loop bound
  was allocating per iteration, so it timed the allocator), and an inflated one
  (the expression was loop-invariant and only one arm hoisted it). **Print
  `PXXDBG=n.locals` and confirm the two arms actually differ before timing them.**
- **`PXXDBG=a.ir:<proc>` needs QUALIFIED method names** (`Vec3.add_bare`, not
  `add_bare`) or the dump is silently empty and the op count reads zero.
- **`grep -c dynattr` on a `.map` answers about the runtime library, not the call
  graph** — the RTL procs are listed whether called or not. It said 10 for both
  arms. Count IR ops instead.

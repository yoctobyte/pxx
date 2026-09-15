---
type: bug
track: N
prio: 70
status: open
slug: bug-n-augmented-assignment-to-an-unannotated-parameter-silently-loses-the-mutation
blocked-by: [bug-n-a-bitwise-or-shift-operator-on-a-variant-user-object-never-reaches-its-dunder]
summary: "An augmented assignment to an unannotated PARAMETER dispatches the plain dunder instead of the in-place one, so the caller never sees the mutation. Seven of twelve operators fixed 2026-09-15; `&= |= ^= <<= >>=` remain, blocked on the plain bitwise binop not reaching its dunder either."
---

# `p += x` on an UNANNOTATED PARAMETER never dispatches `__iadd__`, and silently loses the caller's mutation

**SEVEN OF TWELVE OPERATORS FIXED (2026-09-15). FIVE REMAIN AND THEY ARE
BLOCKED, NOT PENDING — SO THIS TICKET STAYS OPEN.**

Fixed: `+= -= *= /= //= %= **=`. Each now reaches its `__i<op>__` on a variant
receiver, byte-identical to CPython.

Still broken: `&= |= ^= <<= >>=`. **They cannot be repaired from this layer.**
The augmented marker selects a `pyaug<op>_v` out of the IR's variant-dispatch
arm, and for these five there is no arm: the PLAIN `c & 12` on a variant holding
a user object does not reach `__and__` either — it coerces the object to an int
(silent for `& | ^`, RunError 219 for `<< >>`). That is a defect one layer down,
filed as [[bug-n-a-bitwise-or-shift-operator-on-a-variant-user-object-never-reaches-its-dunder]],
and this ticket is `blocked-by` it in substance if not yet in frontmatter.

See "FIXED 2026-09-15 — the operator axis" at the foot. The month-older sibling
[[bug-nilpy-augmented-repeat-on-a-variant-target-still-rebinds]] keeps its own
residue (a dict VALUE target still rebinds) and is NOT closed by this.

**A WRONG VALUE, NOT A CRASH, on the ordinary accumulator idiom.** Measured
2026-09-15.

```python
class V:
    def __init__(self, x): self.x = x
    def __iadd__(self, o):
        self.x += o.x
        return self
    def __add__(self, o):
        return V(self.x + o.x)

D = V(0.5)
def f(p):        # p is a PARAMETER, unannotated
    p += D

a = V(1.0)
f(a)
# CPython: a.x == 1.5   (__iadd__ mutated the caller's object)
# NilPy:   a.x == 1.0   (__add__ made a new object, bound to the local)
```

Measured directly with `id()`:

| | in_place | caller_sees |
|---|---|---|
| NilPy, receiver is a PARAMETER | False | **1.00** |
| CPython, same | True | 1.50 |
| NilPy, receiver is a LOCAL | True | 1.50 |

**WITH BOTH DUNDERS DECLARED IT IS SILENT. WITH ONLY `__iadd__` IT IS LOUD** —
`TypeError: expected a number, got object`, because the target falls through to
the numeric path. The silent shape is the common one: declaring both `__iadd__`
and `__add__` is the normal idiom, and it is what `lekkerzeilen`'s `math3d.py`
does.

## THE FACTORIAL — it is the RECEIVER's storage class, and nothing else

Five rows, receiver and operand varied independently. `V` declares only
`__iadd__` so the failure is loud rather than silent:

| receiver | operand | NilPy | CPython |
|---|---|---|---|
| LOCAL | param | ok | ok |
| ATTRIBUTE | param | ok | ok |
| GLOBAL | — | ok | ok |
| PARAMETER | global | **FAIL** | ok |
| PARAMETER | local | **FAIL** | ok |
| PARAMETER | param | **FAIL** | ok |

The operand's storage class makes no difference. **I first attributed this to
the operand** — the two probes that disagreed differed in the operand as well as
in the class's dunder set, and I named the factor that varied in front of me.
The matrix above is what corrected it, and it is the fourth time in two days
that a factor named from the rows to hand was retired by one more row.

**AN ANNOTATED PARAMETER IS FINE**: `def f(p: V)` dispatches correctly. That is
the tell that names the cause.

## CAUSE, LOCATED IN SOURCE

`PyAugClassDunder` (`compiler/pyparser.inc:29139`) opens with

```pascal
  if Syms[symIdx].TypeKind <> tyClass then Exit;
```

so the whole `__iadd__`/`__add__` dispatch is keyed on the target's **STATIC**
type. An unannotated parameter is not statically `tyClass` — it arrives as a
Variant — so the arm exits, the caller keeps its path, and the numeric
`AN_BINOP` below runs on the instance handle. `PyAugClassDunderNode`, the
field-target twin at `:29182`, has the same shape and the same `IntToTypeKind(
ASTTk[lhsNode]) <> tyClass` gate; attributes happen to pass it because a field's
declared type is known.

This is the same defect as
`bug-nilpy-augmented-assign-on-a-class-instance-silently-yields-zero` and
`bug-nilpy-augmented-assign-to-a-class-typed-FIELD-silently-yields-zero`, both
already fixed and both cited in that function's own comments — **arriving
through the one target shape whose type is not known until run time.** The two
fixed arms are the statically-typed cases; the Variant case never got one. That
is exactly the normalise-don't-special-case shape: a construct reachable through
three target spellings, repaired twice, with the third left on the broken path.

## THE RUNTIME MACHINERY ALREADY EXISTS — this is a wiring job, not a new mechanism

`compiler/builtin/pylib.pas` already dispatches a user dunder from a Variant at
run time, by NAME:

- `PyUserArithCall1(selfObj, otherObj, otherV, dunder, out result)` — `:5377`
- `PyUserObjHasDunder(o, dunder)` — `:6332`

So "try `__iadd__`, else `__add__`, rebind" is expressible with what is there.
The shape of the fix is a pylib helper that takes both dunder names and does the
CPython rule at run time, plus an arm in the aug-assign lowering that routes a
Variant-typed target to it instead of falling through to `AN_BINOP`.

**DO NOT FIX THIS BY MAKING THE STATIC GATE LOOSER.** The gate is correct for
what it does; the missing thing is a runtime path for the case where the static
type is genuinely unknown. Widening `tyClass` to include Variant would send
every Variant `+=` — ints, floats, strings, lists — through user-dunder lookup.

## NOT A LEKKERZEILEN BLOCKER — checked, not assumed

The lekkerzeilen seat ran the census on both trees: **seven** augmented
assignments to a parameter, and none is exposed. Every one takes a SCALAR
(`angle` a float, `n` an int, `count` an int), which has no mutating `__iadd__`,
so CPython rebinds the local too and there is no divergence to have. And every
one of those functions RETURNS the value and every caller uses the return, so
even under the exact failure mode the value comes back out. Sites:
`vessel.py:17,19`, `traffic.py:348,350`, `traffic.py:113,115`,
`pcl/tkhtmlview.py:271`.

So this is ranked on GENERALITY — a silent wrong value on an ordinary idiom —
and not on the demo.

## REPRO

`$SCRATCH/vc/iadd.npy` (the five-row matrix) and `iadd4.npy` (the `id()`
in-place check) from session `01FcK7gV4FyP2pctkY9QUaPV`. Both are a few lines;
the file above reproduces it standalone. Compiler measured: `79551a1b6d05f02e`
(= `e59efc3f5`). CPython 3 is the oracle and disagrees on every failing row.

## A SEPARATE THING NOTICED IN PASSING, NOT FILED

A nested `class W: pass` inside a function body is a parse error
(`pascal26:N: error: expected expression`). Unrelated to this ticket and not
investigated — noted here only so the next person does not spend the minute I
did wondering why a probe would not compile.

## PARTIALLY FIXED 2026-09-15 — `+=` ONLY, AND THE SIBLINGS ARE MEASURED

**`+=` is fixed. `-=`, `*=` and every other in-place dunder are STILL BROKEN,
and this ticket stays OPEN for them.** Saying which arm was repaired matters
more than usual here, because this is precisely the shape
`normalise-dont-special-case.md` warns about: a construct reachable through
several spellings, repaired one spelling at a time, where the un-repaired path
is the one that stays broken.

### What landed

`pyaugadd_v` (`compiler/builtin/pylib.pas`) now tries the in-place dunder on the
left operand before falling back to `pyadd_v`:

```pascal
  if PyVarUserAug(a, b, '__iadd__', Result) then Exit;
  Result := pyadd_v(a, b);
```

with a new one-sided dispatcher `PyVarUserAug`, deliberately NOT `PyVarUserArith`
— that one also tries the REFLECTED dunder on the right operand, and there is no
such thing as a reflected in-place operation.

It is a one-line insertion because the machinery was already there: `pyaugadd_v`
already existed as the `+=`-on-a-variant entry point (it carries the
`TPyList.extend` arm for `xs += ys`), and `PyUserArithCall1` already dispatches a
user dunder from a variant BY NAME. No new mechanism, and no change to the
static arm, which is correct for what it does.

### Why only `+=`

The frontend marks only ONE operator as augmented. `PY_BINOP_AUGADD` is set at
`pyparser.inc:32399` and `:32147`, guarded by `(augTk = tkPlus) and (... =
tyVariant)`, and `ir.inc:12923` reads it to pick `pyaugadd_v` over `pyadd_v`.
Every other augmented operator lowers to the SAME node as its binary form, so
the runtime cannot tell `p -= x` from `p - x` and has nowhere to hang the
in-place attempt.

Measured after the fix, class declaring `__iadd__`/`__isub__`/`__imul__` and all
three binary forms, receiver a parameter:

| | NilPy | CPython |
|---|---|---|
| `p += D` | 12.0 **OK** | 12.0 |
| `p -= D` | 10.0 **LOST** | 8.0 |
| `p *= D` | 10.0 **LOST** | 20.0 |

### The shape of the remaining work

Generalise the marker from "this is an augmented ADD" to "this is an augmented
assignment", let `ir.inc` select a `pyaug<op>_v` per operator, and add the
missing runtime entries — `pyaugsub_v`, `pyaugmul_v`, `pyaugtruediv_v`,
`pyaugmod_v`, `pyaugfloordiv_v`, `pyaugpow_v`, `pyaugbitand_v`, `pyaugbitor_v`,
`pyaugbitxor_v`, `pyaugshl_v`, `pyaugshr_v`. Each is `pyaugadd_v`'s shape minus
the list arm: try `__i<op>__`, else the binary entry. Mechanical, three files,
and it retires the whole family rather than one more spelling.

**Do NOT add them one at a time as they are encountered.** That is how this
defect got here — the bare-name arm and the class-typed-FIELD arm were each
fixed on their own, and the third target shape was left.

### The fixture

`test/test_nilpy_augmented_assignment_on_a_parameter_dispatches_the_in_place_dunder.npy`,
wired. 12 rows, byte-identical to CPython. Two of them must NOT move and they
point in opposite directions:

- `rebind_caller` — a class declaring ONLY `__add__`. Python builds a new object
  and leaves the caller's alone. **A fix that made every `+=` in-place passes
  every other row in the file and breaks this one.**
- `lst` — `xs += ys` on a variant holding a list must stay `TPyList.extend`, in
  place. `PyVarUserObj` excludes `TPyList`/`TPyDict`/`TPyBytes`, which is what
  keeps the new arm out of it.

**VERIFIED TO FAIL ON THE PRE-FIX RUNTIME, and the first attempt to establish
that was itself wrong.** Compiling the fixture from a scratch tree holding a
reverted `pylib.pas` reported PASS — because **an exe-dir builtin beats a
CWD-relative one**, so the compiler invoked by absolute path had been reading the
LIVE builtin the whole time. The tell was a deliberate-garbage guard: appending
nonsense to the scratch `pylib.pas` still compiled clean, which is only possible
if that file is not being read. Copying the compiler binary BESIDE the reverted
builtin gave the real answer — `param_both WRONG got 1.00 want 1.50`, then
`TypeError: expected a number, got object`.

That is CLAUDE.md's silent-substitution arm arriving in a new place: the rules
file warns about a sibling CHECKOUT supplying the builtin, and this is the same
lookup answering about the exe dir instead. **A "the fixture passes on the old
build" result is worthless without a guard proving the old build was in use**,
and the guard costs one `printf`.

### THE SIBLING TICKET, FOUND BY GREPPING THE BACKLOG BEFORE CLOSING

[[bug-nilpy-augmented-repeat-on-a-variant-target-still-rebinds]] (prio 35) is
**the same defect in the same place**, one operator over, and it was filed a
month earlier. Its own body already states the shared rule:

> *"`+=` has exactly the same split and the same known gap ... One rule, two
> operators, one missing half each — fix them together."*

Both are the identical structure:

| | static arm (works) | variant arm (broken) |
|---|---|---|
| this ticket | `PyAugClassDunder`, gated `Syms[].TypeKind = tyClass` | user class `__iadd__` never dispatched |
| the sibling | `PyAugMulNode`, gated `PyNodeIsPyList(left)` | list `*=` rebinds instead of repeating in place |

In both, a statically-typed target was repaired at some earlier date, the gate
that made the repair possible is a COMPILE-TIME type test, and every target
whose type is only known at run time — a parameter, a dict value, a list element
— was left on the old path. In both, the fix is a runtime twin. The sibling
ticket even prescribes `pyvar_repeat_inplace` "plus the `+=` equivalent", which
is `pyaugadd_v`, which existed and until today did not try the dunder.

**So the remaining work on both tickets is ONE piece of work**, and the generalised
marker described above is what serves them together: once `ir.inc` can tell an
augmented node from a binary one for every operator, both the list/repeat
semantics and the in-place dunder have somewhere to hang. Doing them separately
is how there came to be two tickets for one gate.

I am not merging them — the sibling is older, has its own measurements and its
own prio, and merging would lose that. They should be worked together and closed
together.


## FIXED 2026-09-15 — the operator axis (`861b3ad34`, sha PENDING-COMMIT)

**The first fix was `+`-ONLY and the fixture passed.** `PY_BINOP_AUGADD` marked
`tkPlus` alone, so ten sibling operators kept the identical defect while the
green tier said nothing. That is the finding worth more than the fix: a
one-operator repair to a rule that spans twelve leaves eleven rows that no
existing row can see, and the fixture written for the first one CERTIFIES them.

### What changed

- `PY_BINOP_AUGADD` -> **`PY_BINOP_AUGMENTED`**, same value. The marker now says
  AUGMENTED and nothing else; the OPERATOR is already in `ASTIVal`, so one value
  serves the whole family. The old spelling is an alias so nothing outside had
  to move.
- `PyAugMarkedTok` (`pyparser.inc`) names the marked set and, in its own
  comment, names what is NOT in it and why — `*` because `PyAugMulNode` routes a
  variant `*=` through `pymul_v_inplace` and returns first, the five
  bitwise/shift tokens because there is no arm for a marker to select.
- `ir.inc` picks `pyaugsub_v` / `pyaugtruediv_v` / `pyaugfloordiv_v` /
  `pyaugfloormod_v` on a marked node, beside the `pyaugadd_v` row that was there.
- `pylib.pas` gains those four plus `pyaugpow_v`, each **calling the plain twin**
  rather than re-implementing it, which is what makes the non-user population
  provably unchanged. `pymul_v_inplace` gains the `__imul__` try in place.
- `**=` has no binary token, so it never reaches the marked `AN_BINOP` at all;
  `PyAugPowVariantNode` is its hand-built route, wired at both `tkPowEq` sites.

### The regression this caught, and it was mine

`PyAugPowVariantNode` initially took EVERY variant `**=`. That took `v **= 0.5`
on a variant holding -4 away from `PyMakePow` -> `pypow_cx`, which answers
CPython's `(1.2246467991473532e-16+2j)` **byte for byte** — and `pyaugpow_v`
raises on it. A row that was already correct went red.

It was found because the regression probe was diffed against a **rebuilt
pre-change compiler**, not against CPython: three rows differed from CPython and
only one of them was mine. The other two (`100 ** 0.5` at 1 ulp, and the dict
VALUE target still rebinding) are in the control too. *Attribute a delta to a
range before attributing it to yourself* — here the range was one commit and the
control cost two 25-second rebuilds.

`pypow_cx` takes two `Double`s, so `pyaugpow_v` cannot delegate to it — coercing
a variant to a Double is the step a user object does not survive — so the gate
mirrors `PyMakePow`'s own and lives at the parse site. **Residual, stated rather
than hidden:** `c **= 0.5` on a variant holding a user object still misses
`__ipow__`. It did not work before either, so declining neither fixes nor breaks
it.

### Gate

`make compiler/pascal26` **converged** (861b3ad3410e21a7, from 79551a1b6d05f02e);
`tools/gate.sh quick` GREEN after a reviewed `ast_slot_overloads.py --update`
(two rows, both ordinary child-node writes: `AN_ARG Left PyForceVariant(rhs)`,
`AN_CALL Left aA`). `make test-nilpy` and `make lib-test` green.

`test/test_nilpy_augmented_assignment_on_a_parameter_dispatches_the_in_place_dunder.npy`
extended with the operator axis and **byte-identical to CPython**. Its positive
control is a rebuild at the parent commit: the new rows read

    op_sub WRONG got 20 want 17 / op_mul 60 / op_div 5.0 / op_floordiv 5
    op_mod 6 / op_pow 400 ... AUGPARAM FAIL

while `op_add`, all seven `rebind_*` rows and all seven `scalar_*` rows pass on
BOTH compilers — so the redness is the fix and not the fixture.

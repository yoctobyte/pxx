---
track: N
type: bug
blocked-by: []
summary: "FIXED 2026-09-13. `getattr(obj, \"name\")` with a LITERAL name could not see a plain METHOD: with no default it raised `AttributeError` about a method the class declares, and WITH a default it silently returned the default -- which is lekkerzeilen `_has_ground`, a wrong line and exit 0. hasattr answered True for the same name throughout, because only ITS arm of the existence test consulted PyAttrExists. TWO defects: the literal path never reached the runtime resolver (now it does, the same one the COMPUTED spelling uses), and -- THE ROOT CAUSE -- PyMethodUsedAsValue had no arm for a literal getattr, so the bound-method pair it hands back was never normalised to the function-object ABI and returned its result in a register against a caller expecting the hidden-destination convention. That is why the attempt parked in this ticket entered the method correctly and then answered '' for a string and SEGFAULTED for an int. lekkerzeilen --starts is now BYTE-IDENTICAL to CPython. Gate quick GREEN. NOT covered: the same spelling on a BUILTIN container or str, which is loud in both forms and is filed separately."
prio: 65
status: done
owner: —
---

# getattr cannot see a method, and segfaults through a dynamic receiver

## Two repros, one cause, two severities

```python
class A:
    def ping(self, n):
        return n + 1

a = A()
print(getattr(a, "ping")(2))
```

Compiles; at run time:
`Unhandled exception: AttributeError: 'A' object has no attribute 'ping'`,
rc=217. CPython prints `3`. The receiver is statically an `A` and `A` declares
`ping` three lines above.

```python
class A:
    def ping(self, n):
        return n + 1

def use(o):
    return getattr(o, "ping")(2)

print(use(A()))
```

Identical apart from the receiver reaching the call as a variant. Compiles;
**SIGSEGV**, no message.

## The control

```python
class A:
    def __init__(self):
        self.v = 7

def use(o):
    return getattr(o, "v")

print(use(A()))      # prints 7 -- FIELDS resolve, on a variant receiver too
```

So the lookup exists and is wired to the field table only. The two bugs are
one gap at two severities: a wrong `AttributeError` where the class is known,
and an unchecked call through a null where it is not. The segfault is the part
that ranks this -- a compiling program has no diagnostic and no stack.


---

# 2026-09-13 -- re-measured, scoped, and an attempted fix that failed

Both repros above reproduce EXACTLY as written at 152b316c1 (tk1 rc=217 with
that AttributeError, tk2 SIGSEGV, the field control rc=0 printing 7). Nothing
here retracts them. What follows narrows the population, corrects one mechanism
claim, and records a dead end.

## The summary above was restated, and what changed in it

The old summary is preserved verbatim at the end of this section. One clause was
demoted from a mechanism to an observation: it said that "through a
DYNAMICALLY-typed receiver the same expression SEGFAULTS". The segfault is real
and still reproduces, but a genuine variant receiver is NOT the cause --
measured:

    class A:  def meth(self, a): return "A" + str(a)
    class B:  def meth(self, a): return "B" + str(a)
    def pick(w):
        if w == "a": return A()
        return B()
    v = pick("a")
    getattr(v, "meth")        -> a bound method, CORRECT
    getattr(v, "meth", None)  -> a bound method, CORRECT
    hasattr(v, "meth")        -> True, CORRECT

Two unrelated classes returned from one def is what actually produces a variant
receiver, and it resolves -- because with no static class the access falls
through to PyMakeDynAttrByExpr's runtime resolver, which DOES see methods. In
the second repro above, `use(o)`'s parameter has a single calling class and is
typed tyClass, so that repro is a class-typed receiver like the first one. The
two differ by whether the result is called immediately, not by the receiver's
typing. Why one raises and the other crashes is not established.

So what IS broken is narrower than the title: a LITERAL attribute name on a
STATICALLY class-typed receiver, for a plain METHOD. Measured correct and not in
scope: a computed name, a @property (PyMakePropRead), a field, and a genuine
variant receiver.

**That scoping has a testing consequence worth more than the fix.** A probe that
puts the attribute name in a loop variable -- the natural way to write a table
of attribute kinds -- exercises the COMPUTED path and reports everything
healthy. Mine did for twenty minutes and was correct about a different question
the whole time. Write the fixture with the name as a literal, and reach the
method under test ONLY through getattr (see the contamination note below).

## The sharper half: hasattr and getattr disagree

`hasattr(c, "meth")` is True and `getattr(c, "meth")` then raises. In
`pyparser.inc`, the getattr/hasattr intercept (search PyParseAttrName) computes
`atExists` from PyAttrExists -- which DOES know about methods -- under
`(not atIsGet)`, i.e. for hasattr only. That is the exact trade
bug-nilpy-hasattr-does-not-see-a-property named ("a wrongly-taken branch for a
crash"), fixed there for properties and never done for methods.

## The SILENT arm, which is what ranks this

With a default the caller deliberately skips the dynamic path (that is
`getattr(e, "errno", 1)`'s behaviour and it is deliberate), so some shapes return
the DEFAULT rather than raising. lekkerzeilen world `_has_ground`:

    key_at = getattr(region, "key_at", None)
    return lambda x, z: key_at(x, z) in index

`key_at` came back None, the lambda answered False for every position, and
--starts reported the remembered session position as belonging to another world.
`k in r.index` on the same values answers True. No diagnostic anywhere. This is
the last remaining wrong line of lekkerzeilen --starts.

## THE DEAD END -- read this before fixing

Attempted, measured, REVERTED. Kept as a stash named "getattr-sees-methods
attempt: resolves but the value does not call".

It adds `PyMakeMethodRead(recvNode, attr)` as the exact sibling of
PyMakePropRead -- ResolveNodeRec -> ci, FindUMeth -> fi, UMthProc_ -> mpi, then
PyMakeBoundMethod(mpi, recvNode) tagged tyVariant -- wired into the intercept
after the property arm. It RESOLVES and still does not work:

    getattr(w, "z")()   -> '' where CPython gives 'Z'
    getattr(w, "m")(1)  -> ENTERS m with a=1 and self.v=7 both correct,
                           then SEGFAULTS on the way back

The method is found, bound, and entered with the right receiver and arguments;
the RESULT marshalling fails. That is strictly worse than today's
AttributeError, which is why it is not landed.

Ruled out, so nobody repeats it:

- The proc index is RIGHT. PXXDBG=n.bfn instrumentation in both routes printed
  identical rows -- `ordinary-meth m ci=0 fi=159 mpi=2052 name=W.m isfunc=1
  nparams=2 ret=22` against `getattr-meth z ci=0 fi=160 mpi=2053 name=W.z
  isfunc=1 nparams=1 ret=23`. Same lookup, same isFunc, same arity.
- The bound-method CALL machinery is sound, including its fully dynamic forms.
  Through the ordinary paren-less read all six of these are correct: `(w.z)()`,
  a local, passed as a PARAMETER to another def, a local passed as a parameter,
  an element of a list literal, a value in a dict literal.
- It is NOT a missing dispatcher. That was the first hypothesis and it is wrong:
  pyeval is pulled unconditionally (ParseUsesUnitAmbient('pyeval')) and the proc
  count is identical between a working and a failing program (2053 both).
- It is NOT a missing signature record either: EmitPySignatures emits one for
  every NilPy def (PyProcIsNilPyDef).

**The contamination that will mislead you, and it did so twice.** An unrelated
ordinary `_unused = w.m` ANYWHERE in the program makes `getattr(w, "m")` work.
So any probe that reads the method the ordinary way before testing getattr
passes. It is per-METHOD, not per-program -- reading `w.m` the ordinary way does
NOT fix `getattr(w, "z")` in the same program, and that asymmetry is the row
that proves the difference is the ROUTE and not a unit being pulled in. It is
the rule about a measurement creating the condition it tests for, in its
third form: one passing part of the run supplies what the failing part needs.

## Recommendation

Two candidates, neither measured.

1. Find what the ordinary paren-less read does to the RESULT path that the
   intercept does not. The node is identical by construction, so the difference
   is the context it is returned into -- the intercept returns through
   `CurASTNode := atProp; LastExprTk := ...; Exit`, the ordinary site through
   ParsePostfix's `Result := node`. Dump the AST of the assignment in both
   (PXXDBG=a.ast) rather than reading the builders again: reading them is what
   produced all four ruled-out hypotheses above, and the time went there.
2. Route the literal-name method case to the same runtime resolver the COMPUTED
   name already uses (PyMakeDynAttrByExpr with a literal string node). That path
   is MEASURED correct for methods, so it trades a compile-time bind for a
   working answer, and it makes the literal and computed spellings ONE mechanism
   instead of two -- which is devdocs/dev/normalise-dont-special-case.md's
   argument and the reason the two spellings disagreed at all.

**Try option 2 first.** Option 1 is how the attached patch was written.

## Which SPELLINGS are safe, and the one that is worse than no check at all

Raised by a peer from the measurements above and then measured rather than
derived, because the conclusion is about what is SAFE and a derivation would
have been an argument. Three idioms, one class, one method:

    if hasattr(o, "m"): o.m(x)                   SAFE    -- prints M1
    if hasattr(o, "m"): f = getattr(o, "m")      BROKEN  -- the guard PASSES and
                                                            the fetch then raises
    nm = "m"; f = getattr(o, nm)                 WORKS   -- computed path

The middle row is the one to carry. **A codebase that defensively guards with
hasattr before fetching with getattr is worse off than one that does neither**:
the check is what steers you into the failure, because hasattr answers True for
exactly the names getattr refuses. That is this bug's worst shape and it is the
direct consequence of the two halves disagreeing.

It also has NO DEFAULT ARGUMENT, so it does not appear in a grep for
`getattr(..., None)` -- the obvious sweep pattern for the silent arm. Sweep for
both: a `getattr` with a literal name and no default, and a `hasattr` followed
within a few lines by a `getattr` of the same literal name. Measured over
lekkerzeilen/: ZERO of either, so that package is exposed only through the
three silent-default sites listed below. Another consumer may not be.

## The general hazard, which outlives this ticket

Stated here rather than as a footnote to the dead end, because the next
instance will not look like either of tonight's two. In both, **the thing that
made the test pass was not the thing under test, and it was invisible until
something unrelated removed it**: here an ordinary `_unused = w.m` elsewhere in
the program made `getattr(w, "m")` work (per-METHOD, so reading `w.m` does not
rescue `getattr(w, "z")`); in a peer's unrelated subsystem, a workaround
silently masked a broken kernel for an evening and surfaced only when the
workaround was switched off for another reason. The usable form of the question
is CLAUDE.md's: would this row still pass if it were the ONLY thing in the run?
For a fix you are validating, the sharper version is: does my probe reach the
thing under test by the route under test, and by no other?

## Population in lekkerzeilen

Swept by a peer over lekkerzeilen/ by name-matching def names against getattr /
hasattr probes -- a list of places to look, not a list of bugs, and it would
miss a probe naming a method on a non-lekkerzeilen object. Eleven probes name
something defined as a def. EIGHT are @property and are therefore out of scope
by the measurement above. Three name plain methods:

    lekkerzeilen/__main__.py:244   key_at   -> world.World.key_at   (the --starts line)
    lekkerzeilen/world.py:506      kind     -> bindings.Map.kind
    lekkerzeilen/ui.py:567         value    -> ui.Panel.value

ui.py:567 deserves a fixture row of its own: `value` is a plain METHOD on Panel
and a @property on Choice and Pick, so that one call site straddles the broken
and working halves and can return the default for some objects and the right
answer for others.

## The 2026-09-09 summary, superseded

> `getattr(obj, "name")` sees FIELDS only. Asked for a method it raises
> `AttributeError: 'A' object has no attribute 'ping'` about a method the class
> plainly declares -- and through a DYNAMICALLY-typed receiver the same
> expression SEGFAULTS the produced binary instead of raising. CPython returns a
> bound method for both. Compiles clean either way, so the fault has no
> diagnostic. Reproduces on the pin and at the tip. Found while measuring
> whether getattr could stand in for open-world dispatch
> (feature-n-open-world-method-dispatch-on-a-dynamically-typed-receiver); it
> cannot, and it is a crash on its own account.

It is accurate on both repros and on the field control, all three re-verified
2026-09-13. Only the variant-receiver DIAGNOSIS is demoted, and the prio moved
50 -> 65 for the silent-default arm, which it did not know about.


## RESOLUTION — 2026-09-13, fixed in two places

**The dead-end section below was right that the resolver was not one hypothesis
away from working. It was wrong about where to look, and so was I: the resolver
was never the defect. The ABI of the thing it hands back was.**

### (1) The literal path never reached the resolver

`PyAttrFieldIdx` answers "is it a declared FIELD"; `PyMakePropRead` answers "is
it a PROPERTY". A plain method is neither. `atExists` is

    (atFld >= 0) or ((not atIsGet) and PyAttrExists(atRecv, atName))

and the second arm — the only one that consults `PyAttrExists`, which DOES see
methods — is reached **only by hasattr**. That single `not atIsGet` is why the
two spellings disagreed about one name. With `atExists` False the name went to
the dynamic-attribute store, which holds no methods; with a default supplied,
`not (atIsGet and (atDflt >= 0))` skipped that arm altogether and the default
came back silently.

Fixed by handing the literal name to `PyMakeDynAttrByExpr` — the resolver the
COMPUTED spelling already used and which was measured correct for methods — so
the two spellings are one mechanism. The method predicate is lifted from
`PyAttrExists`' own tyClass arm, including the `PyPylibMethodAlias` half, without
which `o.m` would be fixed while `getattr(d, "keys")` stayed broken.

### (2) THE ROOT CAUSE: the bound method was never ABI-normalised

`PyMethodUsedAsValue` decides whether a method is normalised to the
function-object ABI (variant parameters, variant result). Its own comment says
what happens otherwise: *"a bound method returning a value crashed, and one
returning None happened to work."* It had an arm for a COMPUTED getattr — coarse
on purpose, normalising every method, because no token spells the name — and
**no arm for a literal one**, because until now a literal getattr never produced
a bound method.

That is the whole of the parked patch's failure. It resolved and entered the
method with the right receiver and arity, and the RESULT came back in a register
while the caller expected the hidden-destination convention: a string answered
`''`, an int segfaulted on return, and a method returning `None` worked by
accident because `None` needs no hidden destination. Four hypotheses were ruled
out below and none of them was this, because all four were about REACHING the
method.

Added `PyModuleGetattrsLiteral(nm)`, exact rather than coarse — the name is a
token in this spelling, so only the method actually fetched pays the boxing.

### What this buys, measured

- `lekkerzeilen --starts` is **byte-identical to CPython**. It was the one
  differing line, and it is why this ticket was at prio 65.
- `--help` byte-identical; `--conform` passes its own self-check with all six
  `pixels` digests identical to CPython; `--probe` differs only in the line that
  names the backend.
- Gate quick GREEN, 23 PASS / 0 FAIL.

### The fixture's design is part of the fix

`test/test_nilpy_getattr_with_a_literal_name_names_a_method.npy` deliberately
contains **no computed getattr**. `PyModuleHasComputedGetattr` is module-wide:
one computed getattr anywhere normalises every method, and every literal row
then passes on the unfixed compiler.

**That is measured, not feared.** The probe this fix was first verified with had
a computed-name row as a REGRESSION check. It reported all seven rows healthy
and the defect was still present — row 6 rescued rows 1 to 5. I wrote that probe
hours after banking the rule it breaks, which is the rule's own point: the
contaminant was inside the probe, in the right population, and honest.

Rows B, C and D pin the three ABI outcomes separately (non-empty string,
non-zero int that must survive the return, and `None` — the shape that worked by
accident). Row F is the positive control: a default must still be returned for
an absent name, and it is the row that fails if the new arm is gated too wide.
Control: the fixture raises `AttributeError: 'Real' object has no attribute
'key_at'` under pin v408.

### Explicitly NOT fixed

`getattr` with a literal method name on a **builtin** container or str.
`hasattr(d, "keys")` answers True while `getattr(d, "keys")` raises at run time
and `getattr(s, "upper")` is refused at COMPILE time. Both are LOUD, the
receiver is not a user class so the new arm correctly declines it, and it is
filed separately rather than folded in here.

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

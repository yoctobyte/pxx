---
track: N
prio: 40
type: bug
owner: frankb-8e
blocked-by: []
summary: "FIXED 2026-09-20 in PyCarrierNamedProc (compiler/pyparser.inc): a capturing nested def is carried as pyvar_of_callable(pyboundfn_bind(setsig(setown(new(@lifted,..))))) -- FIVE layers, not the two this ticket recorded -- so the carrier was unnamed, both coercion sites skipped their whole arm on -1, and the callable went into the procedural slot with NO diagnostic and a SIGSEGV behind it. Now descends from a pyvar_of_callable head and answers with the first AN_PYSIGREF/AN_PROCADDR, which lets the EXISTING refusal arm fire by name at both sites. Grants no capability: a lift appends captures as extra parameters, so the routine still fails arity and all-Variant and is still refused -- correctly, since a bare code slot retains nothing. NOTE the fixture asserts the DIAGNOSTIC, because pinned prints identical stdout with rc=0 and a value check cannot fail on a missing warning."
status: working
---

# A capturing nested def into a procedural slot segfaults with no diagnostic

## The shape

```python
import 'cbslot.pas' as cb


def outer(k):
    def inner(a, b):
        return a + b + k      # CAPTURES k
    s = cb.MkTwo(inner)       # handed by NAME
    return cb.CallTwo(s)


print(outer(5))
```

Compiles with **no diagnostic of any kind** and segfaults (exit 139).
Identical on `stable_linux_amd64/default/pinned` (v412) and at HEAD, so this
is not introduced by the callback-thunk work -- it is what that work left
behind.

## Why nothing is said

`PyCoerceCallableArgsIn`'s procedural-parameter arm asks
`PyCarrierNamedProc(node)` which routine a carrier was built for, and only
warns when that answers `>= 0`. For a lifted nested def the carrier is not one
of `PyMakeFuncValueFor`'s three recognised forms, so the answer is -1, the arm
is skipped entirely, and the value reaches the slot unremarked.

## Why this is a refusal and not a feature

The obvious-looking repair -- thunk it, like a top-level def -- is wrong, and
the reason is the same one that keeps a bound method out:

> A procedural slot holds a bare CODE address and retains nothing. A thunk for
> a capturing def would have to reach the lifted capture state at run time, so
> it would outlive what it reads.

Note the capturing case is **already excluded by construction** from the thunk
path, not by a hand-written guard: the lambda lift appends captured state as
extra parameters, so `outer.inner` has 3 parameters (`22 22 13`) against the
slot's 2 and fails both the arity test and the all-Variant test in
`PyDefFitsCallbackThunk`. Nothing needs new analysis to decide this -- the
decision is already correct.

**So the fix is a named REFUSAL at the carrier, not new capability.** Give
`PyCarrierNamedProc` (or the arm that calls it) an answer for the lifted-def
carrier shape that is "this is a callable the frontend can name, and it is one
that cannot be thunked", so the existing warning fires with the right reason.

## The family, for whoever takes this

Three ways a callable reaches a procedural slot, after `8826e6aec` and the
thunk work:

| handed in | today |
| --- | --- |
| a Pascal routine | works -- its address is stored |
| a top-level def | works -- a `$pycbthunk_` carries the slot's signature |
| a bound method | refused BY NAME, with the reason |
| a def of wrong arity | refused BY NAME, with the reason |
| **a capturing nested def** | **silent SIGSEGV** |

The last row is the only silent one left, which is the whole argument for
ranking it: every sibling either works or says why not.

## THE CARRIER SHAPE, MEASURED 2026-09-20 -- this ticket had GUESSED it

The text above says `PyCarrierNamedProc` "does not recognise the carrier shape
a capturing nested def produces". That was written from reasoning. Measured at
`c72af31f3a6e` with a probe printing the callee name at the coercion site, the
shape is **two layers deep**:

```
pyvar_of_callable( pyboundfn_bind( <lifted proc>, <captures> ) )
```

`pyvar_of_callable` is a FOURTH carrier spelling beside the three
`PyCarrierNamedProc` knows (`pybound_new_sig`, `pybound_new_star`,
`pybound_new`), and `pyboundfn_bind` is the closure binder inside it.

**An attempt was made and reverted rather than half-landed.** Teaching the
function to unwrap `pyvar_of_callable` and accept `pyboundfn_bind` gets as far
as the binder and still answers -1, because the AN_PROCADDR fallback reads only
the FIRST argument of the call and the lifted proc is not there. So the
remaining work is to find where in `pyboundfn_bind`'s argument list the routine
is, which is a small measurement this ticket now has the setup for.

**It is still a naming problem and not a capability one.** Once named, a lifted
routine carries its captures as EXTRA PARAMETERS, so it fails `ProcSigCompatible`
on arity and fails `PyDefFitsCallbackThunk`'s all-Variant test, and takes the
named refusal. That is the correct outcome and the whole goal.

## It is silent at BOTH coercion sites, which is why it survived two fixes

| site | a def | a bound method | a CAPTURING def |
| --- | --- | --- | --- |
| argument (`MkTwo(f)`) | thunk, works | refused by name | **silent SIGSEGV** |
| store (`e.two = f`) | thunk, works | refused by name | **silent SIGSEGV** |

Both sites ask `PyCarrierNamedProc` first and skip their whole arm on -1, so
one unrecognised carrier shape produces the identical silence at both. Fixing
the function fixes both rows at once -- which is the argument for fixing it
there rather than adding a check at either site.

## Acceptance

That program prints a diagnostic naming `inner` and the reason a capturing def
cannot be given a code address. It does NOT have to compile -- a warning that
leads somewhere is the goal, matching the rest of the family. A positive
control is cheap: the same program with `inner` not capturing `k` must keep
working (it takes the thunk path).

---

## RESOLVED 2026-09-20 (frankb-8e) — named at the carrier, refused by the existing arm

`compiler/pyparser.inc`, `PyCarrierNamedProc`. Exactly the repair this ticket
prescribed: **a named refusal at the carrier, not new capability.** Both
coercion sites now fire, from one change, as the ticket predicted.

    pascal26:6: warning: Nil Python: outer.inner does not have the signature of
    procedural parameter 'f', so the callable object is stored rather than a code
    address — calling through that slot will crash. Only a top-level def of
    matching arity gets a native-ABI thunk; a closure or bound method would need
    the carrier kept alive, which a bare code slot cannot do.

### THE SHAPE WAS FIVE LAYERS, NOT TWO — this ticket's own measurement was short

The section above says the carrier is `pyvar_of_callable(pyboundfn_bind(...))`
and calls that measured. **It is measured and it is incomplete.** Re-probed at
this line for callee NAMES:

    pyvar_of_callable( pyboundfn_bind( pyboundfn_setsig( pyboundfn_setown(
        pyboundfn_new( @<lifted proc>, 1, 1 ), 2 ), <sigref> ), ... ) )

**Five calls, not two**, and `pyboundfn_setsig`/`pyboundfn_setown`/
`pyboundfn_new` were not named anywhere in this ticket. That is why the earlier
attempt recorded above *"gets as far as the binder and still answers -1"* — it
was not that the `AN_PROCADDR` fallback reads the wrong argument, it is that
**the binder is three levels above the thing being looked for.** I reproduced
that same dead end first, with an unwrap that stopped at the binder, and it was
still silent. **A partial measurement is worse than none here, because it names
a destination that looks close enough to stop at.**

**How I got it and why the earlier routes failed:** `PXXDBG=a.ast` prints proc
INDICES, and so does `a.ir` — neither resolves a name, and I burned two rounds
trying to infer the names from indices and from a differential against the
working case. The answer took a five-line `WriteLn` of `Procs[callee].Name` at
the one line in question, built in 12s, reverted with
`git checkout HEAD -- <file>`. **Reach for the probe sooner than I did.**

### The fix

Scoped to a `pyvar_of_callable` head **on purpose**: the three existing
spellings reach their own walk untouched, so this can only ADD an answer and
cannot change one. From that head it descends the first argument, depth-capped
at 8, answering with the first `AN_PYSIGREF` or `AN_PROCADDR` at any level —
both carry the lifted proc's index.

**No new capability, which is the point.** A lambda lift appends captures as
EXTRA PARAMETERS, so once named the routine fails `ProcSigCompatible` on arity
and `PyDefFitsCallbackThunk`'s all-Variant test, and the caller takes the
refusal arm it already had. The decision was always correct; nothing could
reach it.

### Verification — and the assertion class is the whole story

Fixture `test_nilpy_a_capturing_nested_def_into_a_procedural_slot_is_refused_by_name`,
wired into `test-nilpy`. It hands the def over at BOTH sites and never calls
through the slot, so it warns AND exits 0 — the diagnostic is the acceptance,
and calling through remains a crash by design.

| | pinned v413 | after |
| --- | --- | --- |
| `by_argument.inner` named | **no** | yes |
| `by_store.inner` named | **no** | yes |
| `no_capture.inner` named | no | **no** (control: must not over-refuse) |
| `no_capture()` returns | 7 | 7 |
| stdout / exit status | 3 lines, rc=0 | **identical**, rc=0 |

**THE LAST ROW IS WHY THE MAKEFILE ROW GREPS THE LOG INSTEAD OF DIFFING THE
OUTPUT.** Pinned emits **zero** warnings and prints the **same three lines with
the same exit status**. A `diff` of stdout PASSES on the unfixed compiler and
could never have caught this. A missing-diagnostic defect cannot fail a value
check — the assertion has to read the quantity that actually moved.

The `no_capture` row is a real control and not decoration: a refusal that was
too broad would show up there as a warning and a wrong answer, not as silence.
Existing `test_nilpy_def_into_a_native_callback_slot` still passes with **0
warnings**, so no working path acquired a spurious one.

### What this does NOT do

**The capturing program still segfaults if it calls through the slot**, and the
acceptance section above says that is correct — *"a warning that leads
somewhere is the goal"*. Making it compile to something that works would need
the carrier kept alive behind a bare code address, which is the thing a
procedural slot cannot do.

Nothing here touches consumer 3 (ESP interrupts) of
`feature-n-a-nilpy-def-has-no-native-abi-entry-point-to-hand-to-a-c-callback`,
which is a different contract — boxing allocates, and an ISR that allocates is
a latent crash with good latency numbers.

Log: 2026-09-20 frankb-8e — resolved in PyCarrierNamedProc (compiler/pyparser.inc), commit 085c43903, which also wires test_nilpy_a_capturing_nested_def_into_a_procedural_slot_is_refused_by_name. NilPy tier green at 1046 rows, gate quick GREEN re-run after the Makefile change.

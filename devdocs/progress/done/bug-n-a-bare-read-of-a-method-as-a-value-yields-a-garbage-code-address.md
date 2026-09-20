---
slug: bug-n-a-bare-read-of-a-method-as-a-value-yields-a-garbage-code-address
type: bug
track: N
prio: 65
owner: frankb-8e
status: done
summary: "PyMethodUsedAsValue decides whether a method read as a VALUE is normalised to the all-variant function-object ABI, and its scan walked the MAIN FILE only -- so a value read living in an IMPORTED MODULE was invisible, the method kept its native signature, and pydynattr_get_v bound that code through pybound_new_star on a precondition that routine states in its own comment and cannot check. The result was a jump to a garbage code address rather than a diagnostic. FIXED 2026-09-20: the scan now walks every Python source range via PyPyRangeAt. Springs again wherever a frontend scan that decides an ABI is bounded by one file while the construct it decides about can appear in any."
owner:
---

# A bare read of a method as a value yields a garbage code address

## The shape

`test/nilpy_bareread/` plus
`test/test_nilpy_a_bare_read_of_a_method_crashes_when_a_call_site_takes_the_dynamic_path.npy`,
banked with this ticket. **Not wired into `test-nilpy`** — it fails at HEAD and
wiring it would redden the tier for every seat.

**THE FIXING COMMIT MUST DO TWO THINGS:** wire the fixture into `test-nilpy`,
**and delete its line from `test/UNWIRED.txt`.** Both, in that one commit. The
exemption is a countdown, not a steady state, and `tools/check_test_wiring.py`
re-reads that file every run — which is the only reason the condition is there
rather than only in the fixture's own header. A header instruction of exactly
this kind was written on 2026-09-14 (`f09f6bcde`), the fixing commit landed the
same day, and the three files it named sat unwired for six days because nothing
scans a source header.

```python
class Craft:
    def gusty(self, env):
        return env.gust(4.0)      # CALL site -- warns, dispatches at run time, WORKS

class Reader:
    def bare_gust(self, env):
        g = env.gust              # READ site -- same name as a VALUE. Silent. Crashes.
```

`env` is unannotated in both, so both are open-world. CPython prints `12.0`
twice; pxx prints the call row and then SIGSEGVs on the read row.

## What is measured, and what is not

| | |
| --- | --- |
| deterministic | 4/4, and under `setarch -R`, so not ASLR |
| RIP at the fault | **`0x4004ac`** — inside the ELF headers. Not null, not code. |
| the call site | emits `warning: no class declares a method or callable field .gust()` and is **correct** |
| the read site | emits **no diagnostic of any kind** |
| compiler | `d9e9b124ee790727`, pxx `381ea70ff` |

**The single variable is the call site.** Deleting the two lines of `Craft.gusty`
and changing nothing else makes the identical read work, and putting them back
restores the crash. Both directions measured on one tree.

**`0x4004ac` is the part worth keeping.** An unfilled slot gives `0x0`. A value
inside the ELF headers means something real was loaded and it was not a code
address — so this is a carrier built wrong, not a carrier never built. That
distinction is what separates it from its sibling below.

## What this is NOT

**It is not lekkerzeilen blocker 05, and I am not filing it as a reduction of
05.** It was found by applying 05's operator to a smaller population, and the
signatures differ: 05's recorded RIP is `0x0`, this is `0x4004ac`. A reduction
that reproduces *something* is not evidence it is the same phenomenon — 05's own
document already made that mistake once, by reducing against `type()` when the
operator was the bare read. Same family, two rows, each marked with what it
measured. If a fix here also clears 05 on the demo, that is the evidence that
joins them; until then they are separate.

**It is not blocker 03 and not import-order sensitive.** Swapping the two import
lines changes nothing, which is the axis 03 turned on.

## Where to look

The call path has an open-world dynamic dispatcher and warns when it uses it.
The read path evidently has no equivalent: it resolves the name against
something the call site left behind and builds a carrier from it. The carrier
family is `pyvar_of_callable` / `pyboundfn_bind` / `pybound_new*` in
`compiler/pyparser.inc`; `PyCarrierNamedProc` is the function that names a
carrier's target and it was extended on 2026-09-20 for the capturing-def case
(`085c43903`), so it is the natural first place to print from.

**Do not assume the fix is in the carrier.** The read may be resolving to the
wrong thing before any carrier is built, in which case naming the carrier better
would only move the garbage. Print what the read resolved to first.

## The general point, for whoever picks this up

One name, two uses, two mechanisms — and **the silent one is the wrong one**.
The call form is the one that looks risky (it warns, it defers to run time) and
it is correct; the read form looks trivial and produces an address that is not
code. Wherever a frontend serves a construct through two paths, the path that
emits no diagnostic is not the safe path, it is the unexamined one.


## Resolution (2026-09-20, frankb-8e)

**Fixed.** `PyMethodUsedAsValue` in `compiler/pyparser.inc` now walks every
Python source range via `PyPyRangeAt` instead of `1..MainProgramTokCount`.

### The measurement that found it, and the two hypotheses it killed

Neither of my first two candidates survived being printed, which is the whole
argument for printing rather than reasoning:

1. **"`PyMethodUsedAsValue` is the discriminator."** It answers **FALSE in both**
   the crashing and the working configuration. A no-change result, which is data
   about the model rather than about the code.
2. **"The read lowers differently."** Identical — `variantRecv=TRUE`, three
   reads, in both.

The discriminator was the RTTI entry at run time:

```
CRASHING  RetKind=19 (Double)   <- native signature, bound into an all-variant bridge
WORKING   RetKind=22 (Variant)  <- the normalised ABI pybound_new_star assumes
```

and then the scope:

```
read in the MAIN file : MainProgramTokCount=73      match at tok 39 -> TRUE
read in a MODULE      : MainProgramTokCount=236151  no match        -> FALSE
```

### The ticket's own mechanism sentence was wrong, and the fixture pays for it

This ticket said the bug springs when a call site elsewhere took the dynamic
path. **That is the trigger, not the cause.** The call site is what lets the
return type be inferred as `Double`; with no call site nothing pins the
parameter, the method defaults to Variant, and the bug **cannot appear**.

So a fixture written without that call site **passes on the unfixed compiler**.
That is this repo's certifies-the-defect shape, and the wired row carries a
comment saying the call site is load-bearing so nobody "simplifies" it away.

### Why `PyPyRangeAt` and not `TokCount`

`PyPyRangeAt` yields the main file plus every appended `.py`/`.npy` module and
**skips Pascal units**. An unbounded scan once met `parts.at(k)` in `pylib.pas`
— Pascal, one argument — and wrongly vetoed `Grid.at`'s `z` (2026-09-15, token
68229). The guard against the naive widening was already written down. The same
shape is applied to the class scans, whose `PyTokBodyEnd` takes a `limit`
because "the class may sit in a module the parser has not reached".

### Verification

| | |
| --- | --- |
| banked fixture | `rc=139` -> `rc=0`, matches the CPython oracle |
| the 4/4 crasher package | 3/3 clean |
| build | `converged after 1 round(s)` |
| fixture | wired into `test-nilpy`, `UNWIRED.txt` exemption deleted in the same commit |
| wiring census | rc=0 |

### This did NOT clear lekkerzeilen blocker 05, and that is the point

05 has the same operator — a bare method read — and this fix does nothing for
it: `PROBE A` prints, `PROBE B` does not, `rc=139`. **That is the evidence that
would have joined them, and it does not exist.** The separation was made on one
digit, RIP `0x4004ac` against `0x0` — a carrier built wrong against one never
built — and it now rests on a measurement rather than a judgement call.

### The residual, named with an owner

`pybound_new_star` still binds `mi^.Code` on an **unverifiable precondition**.
It is handed `mi^.RetKind <> 0` as a mere *has-result* boolean and never checks
the kind is Variant. This fix removes the way we knew to violate that
precondition; it does not make the violation detectable. **A one-line guard
there — refuse, or diagnose, when `RetKind <> 22` — converts any future
instance from a jump into the ELF headers to a message.** Not done here because
it wants its own fixture and a decision about refuse-versus-coerce, and
smuggling it into this commit would leave both unmeasured. Filed as the next
piece of work on this mechanism.

---
slug: bug-n-a-bare-read-of-a-method-as-a-value-yields-a-garbage-code-address
type: bug
track: N
prio: 65
status: open
summary: "Reading a method as a VALUE off a receiver whose class is not known statically produces a carrier holding an address that is not code, and calling through it jumps into the ELF headers. It springs when the same attribute name ALSO appears at a call site that took the open-world dynamic-dispatch path; remove that call site and the identical read works. The call site warns and is correct, the read site emits no diagnostic at all, so the only two uses of one name are served by two mechanisms of which one is silent and wrong."
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

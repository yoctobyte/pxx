---
slug: bug-nilpy-a-python-override-of-a-virtual-pascal-method-segfaults-when-called-back-from-the-pascal-side
track: N
type: bug
prio: 65
status: backlog
owner: ""
created: 2026-09-21
found-by: frankb-8e
blocked-by: []
summary: "A Python class that subclasses a Pascal class from lib/rtl and OVERRIDES one of its `virtual` methods SEGFAULTS when the Pascal side calls that method back through the vtable. The override is entered -- gdb has it in the Python body with correct arguments -- and the fault is on leaving it. The condition that springs it is a virtual call originating in PASCAL code and landing in a NILPY method body; a nilpy->nilpy override and a Pascal->Pascal override are both fine, so neither the frontend's own tests nor the RTL's can reach it. Worked example is `configparser.ConfigParser.optionxform`, whose unit header (lib/rtl/configparser.pas:17-25) declares it virtual FOR THIS PATTERN and quotes the subclass verbatim -- the author explicitly guarded against the override 'silently never running' and the mechanism fails the other way instead. Not scoped to configparser: any `virtual` in a lib/rtl unit that a Python program may override has this shape, and the RTL deliberately marks such methods virtual, so the population is every one of them. Nine-line repro with a passing negative control below. Blocks feature-demo-songformatter-pxx-target (p68): settings.py compiles with two warnings and segfaults at module level, deterministically, while CPython runs it clean."
---

# A Python override of a `virtual` Pascal method segfaults on the call back

## The repro, and its negative control

    # b8e_cfg.py -- SEGFAULTS under pxx, runs clean under CPython
    import configparser

    class CasePreserving(configparser.ConfigParser):
        def optionxform(self, optionstr):
            return optionstr

    cfg = CasePreserving()
    cfg.read('probe.ini')          # probe.ini: "[Main]\nAlpha = 1\nBeta = 2\n"
    print('read ok')

**Control — the same program with the subclass removed, reading the same file,
succeeds.** That is what isolates the variable to the override rather than to
`read`, to the file, or to the mimic:

    import configparser
    cfg = configparser.ConfigParser()
    cfg.read('probe.ini')
    print('read ok')               # -> "read ok", rc=0

    pxx  subclass:    SIGSEGV (rc=139), 3/3 runs
    pxx  no subclass: read ok,  rc=0
    cpython both:     read ok,  rc=0

Measured 2026-09-21 against **pin v414, binary sha256 `aeadb1754b80`**, x86-64.

**The `.ini` must have a section header.** My first reduction used a sectionless
file; CPython raises `MissingSectionHeaderError` and `optionxform` is never
reached, so the repro "passed" for the wrong reason. Stated because the next
person will write the same fixture.

## Where it faults

Rebuilt `-g -O2`, the location is exact and it is INSIDE the Python body:

    Program received signal SIGSEGV
    #0  CasePreservingConfigParser.optionxform
          (self=0x7fffd74010e0, optionstr=0x7fffd74474e8 'WindowSize')
          at settings.py:60
    60          return optionstr
    #1  0x0000000000565ded in ?? ()

So the dispatch **works** — the right override is entered, with a live `self`
and a correct `optionstr`. The fault is on the `return`, and the caller frame
(Pascal, inside `ConfigParser.get`/`set`, which call `optionxform(option)` at
`configparser.pas:154/166/182`) has no symbols. Whoever takes this should start
at how a nilpy method body returns an `AnsiString` to a Pascal caller that
reached it through a vtable slot, not at configparser.

## Why the corpus cannot see it

The crossing is **Pascal code making a virtual call that lands in a nilpy
method body.** A nilpy program overriding a nilpy class is fine; a Pascal
program overriding a Pascal class is fine. Only the mixed direction faults, and
it is reachable only from a `.npy` program that subclasses an RTL class — which
no fixture does.

## Why it is not scoped to configparser

`lib/rtl/configparser.pas:17-25` marks `optionxform` virtual and says why:

> `optionxform` is VIRTUAL because that is the whole reason real code
> subclasses ConfigParser ... Python methods are always virtual; Pascal's are
> not, so without `virtual` the override would compile and **silently never
> run**.

The author anticipated this exact pattern, quoted songformatter's own class
verbatim, and guarded against the silent-no-op failure. **Every `virtual` in a
lib/rtl unit that a Python program might override is the same shape**, and the
RTL marks methods virtual precisely when it expects an override — so the
population is not one method, it is the set the RTL has deliberately opened.

## NOT a bug, recorded so it is not refiled

The same probing showed pxx accepting a sectionless `.ini` where CPython raises
`MissingSectionHeaderError`. **NilPy is UPWARD compatible with CPython, one
direction** — accepting what CPython rejects is a feature, not a defect.

## What it blocks

`feature-demo-songformatter-pxx-target` (p68). `settings.py` from the real app
compiles under pin v414 with two unrelated warnings and then segfaults at module
level on `cfg.read(CONFIG_FILE)`, deterministically, while CPython runs the same
file clean. Three of the app's five modules build and two of those run; this is
the only *crash* in the set, the other failure being a missing PIL binding.

## Positive control when a fix lands, both arms

The repro above must run and print `read ok`, **and** the no-subclass control
must still do so — a fix that stops the Pascal side calling the override at all
would silence the crash and reintroduce exactly the silent-no-op failure the
unit header was written to prevent. Assert that the override's *value* is used:
read back an option whose case is preserved (`Alpha`, not `alpha`), which no
default `optionxform` can produce.

## Related

- `feature-demo-songformatter-pxx-target` — the blocked demo.
- `lib/rtl/configparser.pas:17` — the unit documenting the intent.

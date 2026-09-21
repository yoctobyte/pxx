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
summary: "MECHANISM FOUND 2026-09-21: a Python method overriding a Pascal `virtual` is installed in the vtable slot with NO ABI ADAPTER, and the two sides disagree about how a result comes back. The nilpy body returns a 16-byte Python value by writing it through a HIDDEN DESTINATION POINTER in %rdi; the Pascal slot is `function optionxform(const s: AnsiString): AnsiString`, which returns 8 bytes in %rax and passes no such pointer. So on any return path that needs a memory copy the body executes `rep movsb` of 16 bytes to %rdi = 0 and faults. Dispatch itself is correct -- right override, live self, correct argument. The condition that springs it is a virtual call originating in PASCAL code and landing in a NILPY method body; a nilpy->nilpy override and a Pascal->Pascal override are both fine, so neither the frontend's own tests nor the RTL's can reach it. Worked example is `configparser.ConfigParser.optionxform`, whose unit header (lib/rtl/configparser.pas:17-25) declares it virtual FOR THIS PATTERN and quotes the subclass verbatim -- the author explicitly guarded against the override 'silently never running' and the mechanism fails the other way instead. Not scoped to configparser: any `virtual` in a lib/rtl unit that a Python program may override has this shape, and the RTL deliberately marks such methods virtual, so the population is every one of them. Nine-line repro with a passing negative control below. Blocks feature-demo-songformatter-pxx-target (p68): settings.py compiles with two warnings and segfaults at module level, deterministically, while CPython runs it clean."
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

## THE MECHANISM (measured 2026-09-21, this is the cause, not the symptom)

    => 0x5529fd <C.optionxform+260>:  rep movsb (%rsi),(%rdi)
       rsi 0x7fffffffc5f0   (valid)
       rdi 0x0              <-- 16-byte result written to NULL
       rcx 0x10

**A Python method overriding a Pascal `virtual` goes into the vtable slot with
no ABI adapter.** The nilpy body returns a **16-byte** Python value through a
**hidden destination pointer in `%rdi`**. The Pascal slot's signature is
`function optionxform(const s: AnsiString): AnsiString` — **8 bytes in `%rax`,
no hidden pointer passed.** So `%rdi` holds whatever it held, here `0`, and the
body copies 16 bytes to address zero.

**THIS EXPLAINS WHY THE CRASH DEPENDS ON THE BODY, which is what makes the bug
look non-deterministic when it is not.** A body whose result the compiler can
materialise directly never takes the copy path; one whose result must be copied
out of a stack slot does. Deterministic 3/3 in both directions:

| override body | result |
| --- | --- |
| `return optionstr` | **SEGV** |
| `s = optionstr; return s` | **SEGV** |
| `return optionstr[:]` | **SEGV** |
| `return 7` | **SEGV** |
| `return optionstr.upper().lower()` | **SEGV** |
| `return "fixed"` | ok |
| `return optionstr.lower()` | ok |
| `return optionstr + ""` | ok |
| `return str(optionstr)` | ok |
| `pass` | ok |

**Note rows 5 and 7: `optionstr.upper().lower()` and `optionstr.lower()` produce
the IDENTICAL string and land on opposite sides.** So the fault is not in the
value and not in aliasing the parameter — it is in which return path the body
compiles to. Any story that explains this by what is returned is wrong; I had
two such stories before reading the registers.

**A TRAP I FELL INTO, recorded because the disassembly invites it.** The faulting
block reads `lea -0x20(%rbp),%esi` — a 32-bit destination, which looks exactly
like an address-truncation bug, and I had it written down as the cause. **The
registers say otherwise: `%rsi` is a correct 64-bit address and `%rdi` is
null.** Reading the disassembly instead of the registers produced a confident,
precise, wrong mechanism. Check the registers.

## What a fix looks like (not attempted — see scope)

An **adapter thunk** at the seam: a generated shim with the Pascal signature
that calls the nilpy body and moves the result between the two conventions.
There is precedent in the same file — `PyGetOrMakeCloneThunk`
(`pyparser.inc:17514`) already synthesises `$pyclonethunk_N` for the clone
trampoline — so the machinery pattern exists and is not being applied here.

**This is a project, not a patch**, which is why it is banked with the mechanism
named rather than half-fixed: it needs a decision about which conventions the
seam must bridge in general (result width, `self`, exceptions crossing back),
not just this one return.

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

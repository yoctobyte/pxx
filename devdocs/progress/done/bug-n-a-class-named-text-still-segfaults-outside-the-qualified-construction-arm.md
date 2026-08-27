---
track: N
prio: 65
type: bug
blocked-by: []
summary: "A NilPy `class Text` still binds the RTL's `Text` file record everywhere except the qualified-construction arm that [[bug-nilpy-text-class-name-binds-the-rtl-file-record]] fixed: `self.f = t.up()` and even `self.f = t` on a `Text` instance SEGFAULT. Renaming the class to anything else makes all three shapes work."
status: done
owner: agent-A
---

# A class named `Text` still segfaults outside the one arm that was fixed

Found 2026-08-27 while fixing
[[bug-n-a-field-takes-its-type-from-the-first-token-of-its-right-hand-side]] —
it was the control written to check that ticket's named hazard (a parameter
shadowing a class name). The hazard did not materialise; this did.

**Pre-existing**: identical under `stable_linux_amd64/default/pinned` and at
HEAD with that fix applied.

```python
class Text:
    def __init__(self, s):
        self.s = s

    def up(self):
        return self.s.upper()


class Wrap:
    def __init__(self, text):
        self.text = text.up()


print(Wrap(Text("ab")).text)     # CPython AB     pxx SIGSEGV
```

## Measured boundary — the shadowing is a red herring

| shape | pxx |
| --- | --- |
| `def __init__(self, text): self.text = text.up()` (param shadows the class) | **SIGSEGV** |
| `def __init__(self, t): self.text = t.up()` (no shadowing at all) | **SIGSEGV** |
| `def __init__(self, text): self.text = text` (single-token RHS) | **SIGSEGV** |
| the same three with `class Text` renamed to `class Boxy` | all correct |

The parameter name does not matter and the right-hand side's shape does not
matter. **The class being called `Text` is the whole trigger.**

## Why this is not the closed ticket

[[bug-nilpy-text-class-name-binds-the-rtl-file-record]] is `done/` and its fix is
real — but it is scoped to ONE arm of the field pre-pass, the QUALIFIED
construction `self.t = tk.Text(...)`, where it calls `FindUClassNonRecord`
instead of `FindUClass`. Its own note in `compiler/pyparser.inc` says so:
"NonRecord, both times". Every other place that resolves a class NAME still
takes the first row, which for `Text` is the RTL's file record — so a field
typed as that record gets a heap object stored in it and the first read walks a
file-variable's guts.

The shape of the real fix is therefore the sibling-grep the closed ticket did
not do: `FindUClass` vs `FindUClassNonRecord` at every name-resolution site that
can see a NilPy class, not just the one that was reproduced. Count them before
choosing; if the answer is "all of them", the honest fix is that NilPy class
lookup never returns a record row at all.

`Text` is not an exotic name — it is a Tkinter widget, and the closed ticket
came from Tkinter code.

## Gate

The four rows above matching CPython, with the class named `Text`, plus the
renamed control.


---

## RESOLVED — 2026-08-27, agent-A

Fixed. The repro is **four lines**, and every specific in the ticket above —
the field, the parameter, the right-hand side, the method call — is incidental:

```python
class Text:
    pass


print("declared only")
```

SIGSEGV. **Declaring the class is the whole trigger**; nothing has to construct
it, store it or read it. The ticket's `Wrap(Text("ab")).text` was three layers of
scaffolding around a fault that needed none of them.

### Measured

`gdb` gave a bare `0x4e3711` (no symbols in the produced binary), resolved
against the program's own `.map`:

```
0x4e3711 -> __init_textfile
```

`__init_<unit>` is a UNIT INITIALISER, and `lib/rtl/textfile.pas`'s is:

```pascal
initialization
  Input.Handle := 0;
  ...
```

A trace inside `FindUClassNonRecord` then named the cause outright:

```
ZZFUC lo=text cur=432 res=0 resunit=-1        (cur 432 = unit textfile)
```

While **unit textfile was compiling**, `Text` resolved to row 0 — the NilPy
MAIN PROGRAM's class — so `var Input, Output: Text` were typed as that class and
`Input.Handle := 0` wrote through an uninitialised class pointer. The program
died before its first statement.

### Root cause — the `declUnit < 0` shortcut, on the class side

A main-program class is stamped `UClsUnitIdx = -1`, and `DeclVisible` answers
True for anything negative. Its own comment says why, and names this ticket
without knowing it:

> `declUnit < 0` is ALWAYS visible … -1 is two things at once in this table — a
> compiler-registered intrinsic … and a routine declared by the main program …
> separating the second would need a marker the rows do not carry, **and a unit
> reaching the program's own routine is not a case the corpus shows.**

On the class side it is exactly the case, and it does not resolve oddly — it
segfaults. [[bug-a-tkinters-text-class-captures-the-rtl-text-record-in-other-units]]
fixed the identical capture for a class declared in a UNIT, by making this
lookup obey visibility; the program-declared row went straight through the
shortcut and kept it.

### The ticket's proposed fix was the wrong axis

The write-up above says the answer is the `FindUClass` vs `FindUClassNonRecord`
sibling-grep — "count them before choosing; if the answer is all of them, the
honest fix is that NilPy class lookup never returns a record row at all". It is
not: `FindUClassNonRecord` was already being asked, and it is what returned the
CLASS where the RTL needed its own RECORD. The axis is **visibility**, not
record-vs-class — the same axis the earlier ticket landed on. Worth recording,
because the plausible-sounding plan would have made the fault worse.

### The fix

`compiler/symtab.inc` gains `ClassRowVisibleHere(ci, lo)` — the class-side twin
of `DeclVisible` — and `FindUClass` / `FindUClassNonRecord` both ask it in place
of the open-coded `ClassNameIsAmbientIntrinsic(lo) or DeclVisible(...)` they each
carried. It adds one rule: **while a UNIT is being compiled
(`CurrentUnitIdx >= 0`), a class row stamped with the program (`< 0`) is not
visible**, unless the name is an ambient intrinsic. `DeclVisibilityProbe` still
wins, because that flag means "does this name exist ANYWHERE" — a diagnostic
question, never a resolving one.

**The marker DeclVisible says the rows do not carry turns out to be unnecessary
for classes, and that was measured rather than assumed.** With a NilPy
`class Text` loaded, the rows carrying `-1` are exactly:

```
ZZROW 0 name=Text   isrec=0      (the program's)
ZZROW 1 name=TGuid  isrec=1
ZZROW 2 name=TObject isrec=0
```

— TObject and TGuid being precisely what `ClassNameIsAmbientIntrinsic` names. So
the existing name filter is complete on the class side and this rule hides
nothing else. It is also plain Pascal (a unit is compiled before the program and
cannot see its declarations) and plain Python (a module cannot see its
importer's names).

### Verified

Every row of the ticket's table, plus the rows it did not have:

| shape | before | after |
| --- | --- | --- |
| `class Text: pass` and nothing else | **SIGSEGV** | correct |
| `x = Text()` | SIGSEGV | correct |
| `self.text = text.up()` (param shadows the class) | SIGSEGV | correct |
| `self.text = t.up()` (no shadowing) | SIGSEGV | correct |
| `self.text = text` (single-token RHS) | SIGSEGV | correct |
| real text-file I/O **in the same program** | n/a (never ran) | correct |
| the same five with the class renamed | correct | correct |

All eleven `examples/tk/**` programs (the tkinter façade, whose `lib/pcl` really
does declare `Text = class(Widget)` in a UNIT — untouched by this rule) still
compile, including `uses_tkinter_and_configparser.pas`, the Pascal regression
that the earlier ticket left behind.

### Gate

`make compiler/pascal26` → `self-host fixedpoint: verified — 1 round(s)` (the
Pascal side's own proof that this shared lookup did not move).
`tools/gate.sh quick` → GREEN. Witness
`test/test_nilpy_class_named_like_an_rtl_record.npy` registered in `test-core`,
`.expected` generated by CPython, SIGSEGV at pinned v381 and green now.

## Log
- 2026-08-27 — resolved, commit f3422cd14.

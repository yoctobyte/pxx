---
track: N
prio: 65
type: bug
blocked-by: []
summary: "A NilPy program that imports unit A (declaring `Text = class`) before unit B SILENTLY REBINDS `Text` inside B — an ordinary Pascal unit that never names A: SizeOf goes 4128 (the RTL file record) -> 8 (a class pointer), and it COMPILES. `import tkinter` then `import configparser` is the arm where it happens to hit an overload check. TRIAGED 2026-08-29: the cause stated below is WRONG — NilPy DID inherit the visibility fix and the class lookup returns the correct row; an earlier arm of ParseTypeRef claims the name and IsClassType is never reached. Three-file repro, no tkinter needed. Handed off to A/N (pasparser_decl.inc / symtab.inc)."
status: working
owner: frankA
---

# NilPy import order leaks a class name into a later-compiled RTL unit

- **Type:** bug (Nil Python frontend — unit/import scoping) — **Track N**.
- **Filed:** 2026-08-29 by the wasm lane while re-measuring
  [[feature-demo-songformatter-pxx-target]] against pin v392 (`60b060bb54a8`).

## Repro

```python
import tkinter
import configparser
print("ok")
```

```
pascal26:354: error: no overload of Assign matches these arguments
  argument types: (class, AnsiString)
  candidates:
    Assign(record, AnsiString)
  in: lib/rtl/configparser.pas
```

Swap the two lines and it compiles.

## Cause

`lib/pcl/tkinter.pas:312` declares `Text = class(Widget)` — the Tk text widget.
`lib/rtl/configparser.pas:350` declares `var f: Text` meaning the RTL's file
type, and then calls `Assign(f, path)` / `Reset(f)` / `Eof(f)` on it. When
tkinter is imported first, its class is already in the flat class namespace and
captures the name, so every file operation in `ConfigParser.read` and
`.write` fails to match.

## The control is what makes this Track N and not another instance of the flat namespace

Pure Pascal does NOT reproduce it, in either order:

| program | result |
| --- | --- |
| `uses tkinter, configparser` | **OK** |
| `uses configparser, tkinter` | **OK** |
| `import tkinter` / `import configparser` (NilPy) | **fails** |
| `import configparser` / `import tkinter` (NilPy) | OK |

[[bug-pascal-uses-is-transitive]] is **done**, and the two Pascal rows are that
fix working: a unit's classes no longer leak into a sibling compiled after it.
The NilPy import path did not inherit it. So this is not a re-litigation of
[[decide-class-namespace-scoping]] — that fork was resolved-by-cause on the
grounds that proper unit-scoped `uses` dissolves it, and for Pascal it did.
This is the same fix missing on the other frontend's path.

## This is NOT a reopening of [[bug-a-tkinters-text-class-captures-the-rtl-text-record-in-other-units]]

That ticket is in `done/`, fixed at `8c8a95a69` ("the class-over-record
preference obeys unit visibility"), and its title matches this symptom exactly:
same `Text` class, same `configparser.pas`, same `Assign` error text. Its repro
is five lines of pure Pascal:

```pascal
program cp3;
uses tkinter, configparser;
begin
  WriteLn('both ok');
end.
```

**That repro passes today.** So does the reverse order. Both rows in the table
above are that fix working, and they are in this ticket precisely so the next
reader does not open the closed ticket, recognise the symptom, and conclude the
question is settled. A closed ticket that matches your symptom is worse than an
open one: an open one gets re-read, a closed one closes the question.

What is left is the half that fix did not reach — NilPy's `import`, which does
not go through the Pascal `uses` path and did not inherit its unit visibility.
The two-line Python repro at the top fails on a tree where the five-line Pascal
repro passes, which is the whole claim, and it is the reason this is filed in N
rather than reopened in A.

## Not the name `Text`, and not the `from` list

Worth recording because the obvious theory is wrong twice:

* `from tkinter import Text` looks like the culprit and is not. `from tkinter
  import Frame` — naming a completely different class — fails identically,
  because the whole unit is compiled either way.
* `import tkinter as tk` and plain `import tkinter` both fail. The alias is not
  involved.

The trigger is *any* import of tkinter before configparser.

## Impact

Three of songformatter's five modules stop here: `convertrawtext.py`,
`SongFormatter.py` (both import tkinter at the top and reach configparser
through `settings.py`), and it is the first wall for the application as a whole.
Reordering imports is an app-source edit, which this track's mission forbids —
songformatter's whole point is compiling unmodified CPython source, and CPython
does not care about import order here.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical, plus the two-line
repro above compiling in both orders, plus the two Pascal control rows staying
green so the fix is not bought by re-breaking `uses`.

---

## Triage 2026-08-29 (frankC) — the stated cause is WRONG, and the bug is worse than described. HANDED OFF to Track A/N.

Measured at `b4053bcb7e52`, a self-hosted fixedpoint build of HEAD. Every row
below was run, not reasoned. **Two findings change what the next agent should
look at, and one changes the ticket's severity.**

### 1. It is a SILENT WRONG BINDING, not a compile error

The `Assign` failure is one arm — the arm where the wrong type happens to meet
an overload check. Bind the same name somewhere that does not check, and it
compiles and runs with the wrong type:

```pascal
{ zcls2.pas }
unit zcls2;
interface
type Text = class public y: Integer; end;
implementation
end.

{ zuser5.pas }
unit zuser5;
interface
uses textfile;
procedure Go;
implementation
procedure Go; var f: Text; begin WriteLn('sizeof=', SizeOf(f)); end;
end.
```

| driver | `SizeOf(f)` |
| --- | --- |
| `program ms; uses zcls2, zuser5;` | **4128** — the RTL file record. Correct. |
| `import 'zcls2.pas'` then `import 'zuser5.pas'` | **8** — a class pointer. **WRONG, and it COMPILES.** |
| `import 'zuser5.pas'` then `import 'zcls2.pas'` | 4128 — correct |
| `import 'zuser5.pas'` alone | 4128 — correct |

`zuser5.pas` is ordinary Pascal with an ordinary `uses textfile`, and it does
not name `zcls2`. Its meaning changes because of the order in which a **NilPy**
program imported two unrelated units. Under CLAUDE.md's compat table this is the
silent-wrong-behavior row, so `bug-` is the right kind and the prio should not
be read down: a program can bind `Text` to the wrong type and still run.

The ticket's summary should say *silently binds*, not *fails to compile*.

### 2. The stated cause — "NilPy's import path never inherited the `uses` fix" — is not what happens

It DID inherit it. With a temporary probe printing unit names for every
candidate row (added under `PXXDBG=a.uclass`, measured, **reverted — not
committed**), the failing NilPy compile of `zuser5` reports:

```
row=101 isrec=TRUE  decl=textfile cur=zuser5 vis=TRUE  rank=26 amb=TRUE
row=108 isrec=FALSE decl=zcls2    cur=zuser5 vis=FALSE rank=-1 amb=FALSE
```

`zcls2`'s class row is **correctly invisible**, `textfile`'s record row
**correctly wins**, and the passing Pascal control reports the same verdict with
different row numbers. So `FindUClass` / `FindUClassNonRecord` /
`ClassRowVisibleHere` / `UsesRankOf` — the machinery `8c8a95a69` fixed — is
**not** the defect. `--warn-uses-leak` is a red herring for the same reason: it
emits the identical `class 'Text' resolved ... through unreachable unit` warning
on the **passing** Pascal run. The warning is not the failure.

Something downstream of that lookup rebinds the name.

### 3. Where to look — two leads, one measured, one structural

**Lead A (measured).** `IsClassType` is **never called** during the failing
NilPy compile, but IS called during the passing Pascal compile. So an *earlier*
arm of `ParseTypeRef` (`compiler/pasparser_decl.inc`, the final `else` at ~557)
claims `Text` under NilPy and never reaches the `IsClassType` arm at ~596. The
first thing to print is the `tnHasAlias := FindTypeAlias(lo) >= 0` guard at ~415
and which arm actually fires.

**Lead B (structural, NOT yet verified — do not write it into a fix without
printing it first).** Both class lookups end with an alias fallback that has
**no visibility gate**, unlike the row scan directly above it in each:

* `FindUClass` (`compiler/symtab.inc` ~1080): scan gated by `ClassRowVisibleHere`,
  then `for i := 0 to UClsAliasCount - 1 do ... Result := UClsAliasCi[i]` — ungated.
* `FindUClassNonRecord` (~1830): same shape, same ungated tail.

`8c8a95a69` guarded the scans and left both alias tails blind. That is exactly
the `normalise-dont-special-case` "fixed one arm, never grepped for the sibling"
shape; an alias table is visibility-blind by construction and order-sensitive in
precisely the way the table in §1 is. It fits every observation — but it is a
hypothesis with a structural argument, not a measurement, and this repo's
history is full of plausible unmeasured stories recorded as root causes. **Print
`FindTypeAlias('text')` before believing it.**

### 4. Ruled out, so nobody re-walks them

* Not the Python module *resolver*: all three spellings fail, including explicit
  `import 'tkinter.pas' as tk` / `import 'configparser.pas' as cp`.
* Not the extra units NilPy loads: Pascal `uses pylib, tkinter, configparser`
  compiles.
* Not the import statement: a NilPy program whose only statement imports a pure
  **Pascal** wrapper unit (`unit zwrap; uses zcls2, zuser3;`) fails, while
  `program mq; uses zwrap;` compiles. The trigger is the NilPy *compilation
  context*, not the import syntax.
* Not `--warn-uses-leak`'s finding (see §2).
* Not the name `Text` and not the `from` list — already recorded above, and
  re-confirmed: the minimal repro uses a user class in a user unit.

### 5. Handoff

The fix is in `compiler/pasparser_decl.inc` and/or `compiler/symtab.inc` —
shared Track A ground, outside Track C's lane. frankC declared these files
out of scope when it claimed the ticket and is not widening into them. Moved
`working/` -> `unfinished/` so the lock is released rather than left held;
frankA holds A+N and both files. Diagnosis above is the whole of what was
learned; the repro in §1 is three files and needs neither tkinter nor
configparser.

### 6. On the `Gate:` line above

`make test-nilpy` is superseded by CLAUDE.md's per-fix loop
(`decide-gate-line-convention`, 2026-08-01) and was not run. The gate for
whoever fixes this is `make compiler/pascal26` plus the §1 table in all four
rows plus the two Pascal control rows; Track T sweeps the breadth.

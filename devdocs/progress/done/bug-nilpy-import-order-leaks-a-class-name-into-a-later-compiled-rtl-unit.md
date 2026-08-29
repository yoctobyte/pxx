---
track: N
prio: 65
type: bug
blocked-by: []
summary: "A NilPy program that imports unit A (declaring `Text = class`) before unit B SILENTLY REBINDS `Text` inside B — an ordinary Pascal unit that never names A: SizeOf goes 4128 (the RTL file record) -> 8 (a class pointer), and it COMPILES. `import tkinter` then `import configparser` is the arm where it happens to hit an overload check. TRIAGED 2026-08-29: the cause stated below is WRONG — NilPy DID inherit the visibility fix and the class lookup returns the correct row; an earlier arm of ParseTypeRef claims the name and IsClassType is never reached. Three-file repro, no tkinter needed. Handed off to A/N (pasparser_decl.inc / symtab.inc)."
status: done
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

---

## RESOLVED 2026-08-29 (frankA) — an init only one frontend ran, and a sentinel whose default is a valid index

frankC's lead A was right (`IsClassType` is never reached) and its lead B was
wrong (the ungated alias tails are not involved). The arm that claims the name
is `nestCi`, one above `IsClassType` — but the *reason* it fires is one level
below where anyone was looking, and it is not the unbalanced restore that was
predicted.

### The root cause

`ParsingClassBodyCi` means "no class scope is open" when it is `-1`. It is
initialised in **exactly one place**: `pasparser_prog.inc:569`, inside
**`ParseProgram`** — the *Pascal* entry point. Every other frontend enters
through its own `Parse*Program` and never runs it, so the global keeps its **BSS
default of 0** — and 0 is not a sentinel, it is a **valid `UCls` index**. Class 0
is `TGuid`. So a NilPy compile believed it was inside `TGuid`'s class body from
the first token to the last.

From there the chain is all pre-existing, correct code doing its job:

1. `AddClassLikeType` (`pasparser_class.inc:383`) registers a class-like type as
   a **nested type of `ParsingClassBodyCi`** whenever it is `>= 0`. So every
   top-level class in every imported unit became a nested type of `TGuid` —
   `textfile`'s `Text` **record** and `zcls2`'s `Text` **class** alike.
2. `ParseTypeKind` consults `FindNestedType` **before** `IsClassType`.
3. Class-scope lookup is deliberately **not** visibility-gated — correctly, since
   a nested type is reachable by its bare name inside its owner's body.

So `var f: Text` resolved to whichever `Text` won the nested-type lookup, decided
by import order.

**This is why the triage's puzzle resolved the way it did.** frankC measured the
visibility layer returning the *correct* verdict (`vis=FALSE` for `zcls2`) while
the wrong type still came out, and that is exactly right: nothing in the
visibility layer is broken, and it is simply **not the layer that answered**.
`ci` (from `FindUClass`) was 101 — the record, correct — in *both* NilPy runs;
`nestCi` overrode it.

### Measured, `lo=Text`, all three drivers

| driver | `ParsingClassBodyCi` | `nestCi` | `ci` | `SizeOf` |
| --- | --- | --- | --- | ---: |
| Pascal `uses zcls2, zuser5` | **−1** | −1 → final else | 9 | 4128 ✓ |
| NilPy, good order | **0 (`TGuid`)** | 101 = textfile *record* | 101 | 4128 ✓ |
| NilPy, bad order | **0 (`TGuid`)** | 74×101, **1×108 = `zcls2`'s class** | 101 | **8** ✗ |

Every restore in the NilPy run returned to **0**, *including the first* — so
`savedPCB` was already 0 before any class body opened. **Not a leaked restore:
the save/restore pairs are balanced and neither range contains an `Exit`.** The
predicted "unbalanced restore" shape would have been fixed by balancing a
restore, which would have changed nothing here. The hole is an *absence*, not a
leak.

### The fix, and the sibling it also closes

`ResetDeclScopeSentinels` (`symtab.inc`), called **before the frontend
dispatch** in `compiler.pas` — so it covers every driver, which is the same call
made three lines above it for `EmitTlsMainInstall` (*"one call site rather than
one per driver"*, `bug-a-threadsafe-segfaults-on-every-nilpy-program`).
`ParseProgram` calls the same routine instead of keeping its own copy of the
literals, so there is one definition rather than two — the copy is what stays
broken.

It also initialises **`ParsingClassConstCi`**, the sibling sentinel sitting on
the adjacent line of the same block, with the same `-1`-vs-BSS-0 problem and the
same single init. Latent, unreported, and the next instance. **ALGOL, Erlang,
Rust, Zig, C and asm all had the identical hole** — this was never a NilPy bug,
it was a Pascal-entry-only init that only NilPy had grown enough class-declaring
imports to expose.

`PyLoopElseFlag := -1; { no enclosing loop yet; 0 is a real Syms index }` sits
four lines from the new call site — the same bug class, recognised once for one
variable and not generalised.

### Gate

| | baseline | fixed |
| --- | --- | --- |
| `import tkinter` / `import configparser` (the filed repro) | `no overload of Assign … (class, AnsiString)` | **compiles, prints ok** |
| reverse order | compiles | compiles |
| §1 `SizeOf` table, bad order | **8** | **4128** |
| §1 table, other three rows | 4128 | 4128 |
| Pascal controls both orders (`8c8a95a69`) | green | **green** |

**frankwasm's reconciliation is confirmed: one capture, two manifestations, one
fix** — loud where the captured type meets overload resolution, silent where
only size is read. The baseline column was re-measured on this tree with the fix
stashed, not taken from the pin.

Self-host fixedpoint 1 round `a7716528fa25` (identical across a stash/restore
cycle); `tools/gate.sh quick` GREEN.

New gated test `test_nilpy_import_order_does_not_rebind_a_type` (+ `_rev`, +2
helper units in `test/nilpy_units/`). **Both orders are pinned**, because only
one of them was ever wrong and pinning just that one would let a later change
fix it by breaking the other and still look green. Verified to FAIL on the
stashed baseline (`WRONG: rebound to something 8 bytes`).

### Correcting this ticket's own record

The summary said *"NilPy's import path never inherited the Pascal-side
visibility fix"*. It had. The visibility fix (`8c8a95a69`) works on both paths
and is untouched here. The divergence was upstream of it and had nothing to do
with `uses` transitivity.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

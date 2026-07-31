---
summary: "Pascal: `lst[j]^.Field` on a TPropList resolves only the FIRST field — every other one is 'no such member'; via a local variable it works"
type: bug
track: A
prio: 55
---

# `arr[i]^.Field` loses the pointed-to record type — but only in some units

- **Type:** bug (compiler — record/field resolution — **Track A**)
- **Opened:** 2026-07-31 by Track B, running the GUI suite for
  [[feature-pcl-seam-seal]]. **Pre-existing**, not caused by that work: the same
  compile fails identically on a stashed tree.

## Symptom

Eight lines, against the shipped RTL:

```pascal
program p;
uses typinfo;
var lst: TPropList; j: Integer;
begin
  j := 0;
  if lst[j]^.Kind = 5 then WriteLn('x');
end.
```

```
pascal26:6: error: "Kind": no such member on this record/class
```

`TPropList` is `array[0..511] of PPropInfo` and `TPropInfo` plainly has a `Kind`
field — `var r: TPropInfo; r.Kind := 1;` compiles.

## What is and is not affected

| form | result |
| --- | --- |
| `lst[j]^.NamePtr` — the FIRST field of the record | **ok** |
| `lst[j]^.Kind`, `.TypeRef`, `.GetKind`, `.OrdType` — any later field | **error** |
| `p := lst[j]; p^.Kind` — the same deref via a local | **ok** |
| `var r: TPropInfo; r.Kind` | **ok** |

Only offset 0 resolves, which reads as: the element type is lost and the
expression falls back to a bare pointer dereference.

## What was ruled out (measured, not reasoned)

- **Not the shape of the types.** A synthetic unit declaring the same
  `record` / `^record` / `array[0..511] of ^record` chain, with the same leading
  `PString` field, compiles the identical expression fine.
- **Not the unit boundary.** The synthetic version above is in a unit too.
- **Not unit size / symbol-table growth.** `typinfo`'s INTERFACE alone (its real
  declarations, empty implementation) compiles the expression fine, and stays
  fine with 400 dummy functions appended.
- **Not the `var kind: Int64` parameter of `GetFieldPtr`.** Pascal is
  case-insensitive so that identifier was the obvious suspect; renaming it
  throughout does not fix it.
- **Not `GetFieldPtr := @PUInt8(instance)[fi^.Offset];`** — a cast-index-deref
  chain, the other obvious suspect. Replacing it does not fix it.

So it needs something in `lib/rtl/typinfo.pas`'s IMPLEMENTATION, and that
something has not been isolated. A cut-the-file-and-append-`end.` bisect points
at the region ending with `GetFieldPtr`, but that evidence is weak — every cut
also removes declarations, so the boundary may only mark the first syntactically
valid cut rather than the guilty construct. Stated as unknown rather than
guessed.

## Why it matters

It blocks the **eliah IDE** build, which is the one red in `tools/gui_suite.sh`:

```
FAIL  eliah_ide -- compile:   near: plist  j    >>> Kind
```

`apps/ide/eliah/main.pas:784` is `plist[j]^.Kind`, i.e. exactly this.

The suite USED to run the stale binary from a previous build after that FAIL and
report `OK eliah_ide (real window 1100x727)` two lines later, so the red read
half-green. Fixed on the Track B side (`tools/gui_suite.sh` is Track B's file):
every build now removes its output before compiling, and eliah's window checks
are gated on the build succeeding, so the run ends

```
FAIL  eliah_ide -- compile:   near: plist  j    >>> Kind
SKIP  eliah_ide (window checks) -- it did not build
```

The compile failure itself is unchanged and still belongs to this ticket.

The failure is at least LOUD. But "only the first field of a record is
reachable" is one typo away from being silent: a record whose first field
happens to have the same type as the one you meant would compile and read the
wrong bytes.

## Gate

`make test` + self-host byte-identical, plus a regression compiling the eight
lines above, and `tools/gui_suite.sh` reaching a green `eliah_ide -- compile`.

## Resolution (2026-07-31, claude-A3)

**Root cause, measured, not guessed:** `TPropList = array[0..511] of
PPropInfo` is a NAMED ARRAY-TYPE ALIAS whose element is a pointer-to-record.
The compiler's array-type-alias table (`ArrType*` in `compiler/defs.inc`) has
`ArrTypeElemRec` for a RECORD element's id, but had **no slot at all** for a
POINTER element's pointee record id. `ParseTypeKind` computes that pointee id
correctly (into the global `LastTypePointerElemRec`) while parsing `of
PPropInfo` at alias-DEFINITION time — but nothing ever stored it, so it was
silently discarded. Every later consumer of the alias (`var lst: TPropList`,
a field, a param, a function result) read back `ArrTypeElemRec` (fine, for the
record case) but for the pointer case fell through to whatever the single
global `LastTypePointerElemRec` happened to still hold — leftover from the
LAST unrelated pointer-typed declaration parsed anywhere earlier in the
compilation. In `typinfo.pas` that was `GetFieldPtr`'s `fi: PFieldInfo` local
(the last routine in the unit), which is why the prior weak bisect pointed at
that exact spot, and why `TFieldInfo`'s first field (also named `NamePtr`)
made `lst[j]^.NamePtr` "work" while every other field errored. It's why a
synthetic unit with an IDENTICAL type shape didn't reproduce: nothing about
the bug depends on the shape, only on what pointer-typed declaration happened
to be parsed last before the alias got used — accidentally still-correct in a
short synthetic file, definitely wrong after typinfo's dozen-plus routines.

**Fix:** added `ArrTypePtrElemRec` (`compiler/defs.inc`), a table parallel to
`ArrTypeElemRec`, populated at both array-type-alias definition sites and
restored into `LastTypePointerElemRec` at every site in `compiler/parser.inc`
that already restores `LastTypeRecId` from `ArrTypeElemRec` for a named-array
consumer (var, class/record field incl. the C-struct-field mirror, param,
dynamic-array-of-named-array-alias, N-D merge, function return type).

**Verification:**
- `test/test_arr_of_ptr_elemrec_b354.pas` (new, wired into `make test-core`):
  a minimal named array-of-pointer alias with a decoy pointer-typed local
  parsed in between definition and use — reproduces the leaked-global shape
  directly. Confirmed it silently prints the WRONG values (`10 10 10` instead
  of `10 20 30`) against the pre-fix pinned binary, and correct values against
  the fix.
  - This test happens to hit the DIFFERENT (silent-wrong-value) manifestation
    the ticket flagged as the scarier variant of this bug, vs. the loud
    compile error typinfo's own shape hit — same root cause, both fixed.
- The ticket's 8-line repro now compiles; extended it with a populated
  `TPropList` (not just the nil-deref smoke case) and confirmed `Kind`, not
  just `NamePtr`, reads the correct value.
- Self-host fixedpoint: byte-identical.
- `tools/testmgr.py --tier limited`: 1107/1107 pass (2 skips, missing
  third-party corpus, unrelated).
- `tools/gui_suite.sh` / eliah IDE: the fix gets `apps/ide/eliah/main.pas`
  PAST the `plist[j]^.Kind` line (784) that this bug blocked, confirming the
  fix in the real caller, not just synthetic tests. Compilation now reaches a
  SECOND, unrelated wall at line 1431 (`EliahForm.Win.Caption` — no `Win`
  member exists anywhere in `lib/pcl` or `apps/ide/garin`): a pre-existing
  app-level bug, not a compiler bug (verified nothing in the class hierarchy
  declares `Win`, and no other `.Win.` usage exists in the tree). Filed as
  `bug-eliah-ide-win-caption-no-such-member` (Track B) rather than fixed here
  — out of Track A scope, and this ticket's compiler-side fix is independently
  complete and verified. `tools/gui_suite.sh` will not reach a fully green
  `eliah_ide -- compile` until that follow-up lands too.

## Log
- 2026-07-31 — resolved, commit 819722d56.

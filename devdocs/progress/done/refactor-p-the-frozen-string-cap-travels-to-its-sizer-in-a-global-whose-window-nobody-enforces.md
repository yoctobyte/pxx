---
slug: refactor-p-the-frozen-string-cap-travels-to-its-sizer-in-a-global-whose-window-nobody-enforces
title: "`SizeOfSlot`'s two arguments arrive from a call and a global, coupled only by a window"
track: P
prio: 45
type: refactor
status: done
owner: frankZ
blocked-by: []
summary: "DONE 2026-09-09 -- ROUTE 4 OF THE (kind, companion) TAXONOMY IS EMPTY. `SizeOfSlot(tk, cap)` and `TypeStorageSize(tk, recId)` take a kind and a companion the CALLER assembles; eleven of the thirteen `SizeOfSlot` sites took both halves from ONE indexed carrier and two did not -- the SizeOf type-name arm in `pasparser_expr.inc` read the GLOBAL `LastTypeStrCap` at the point of use, and the `file of` element site in `pasparser_decl.inc` captured it into locals three lines after its own `ParseTypeKind`. Both now call `ParseTypeKindSized(var recId, strCap): TTypeKind`, which returns all three from one call, so a mismatched pair is no longer expressible at either. Both were CORRECT before the change; what had no owner was the temporal WINDOW, and the window had already been violated once with a silent wrong value ([[bug-a-nd-array-function-result-indexes-the-wrong-slot]], fixed by a dedicated carrier, which is the same move). NOT A GATE ROW: routes 4-5 are exactly the ones not mechanically checkable at the call site. THE FIXTURE'S CONTROLS ARE THE REUSABLE HALF AND TWO OF THEM FAILED TO FIRE FIRST. Its four `SizeOf(<name>)` rows never reach the changed resolver (`PXXDBG=p.sized`, a probe added here, fires exactly twice and both times from `file of`) -- the re-parse arm is gated by `BuiltinTypeNameNeedsDecl`'s six builtin names and a user alias is answered by the already-paired alias arm at `pasparser_expr.inc:3987`. And the `file` row, which DOES reach it, stayed green under a deliberate breakage because a typed file is written and read through the SAME element width, so the count, the value and the position are all invariant to that width being wrong; only the BYTE length separates them (33 correct vs 24 broken), which is why the fixture reopens both files as `file of Byte`. RESIDUAL: the globals still exist, so a caller added later can reopen a window, and no Pascal program can sample that population."
---

# The cap and the kind arrive by different roads, and only a window joins them

- **Type:** refactor (a latent-defect shape with a measured precedent) — **Track P**
- **Found:** 2026-09-06, sweeping the record-sizing arms for a peer's
  (kind, companion) question. Route 4 of 5.

## The two sites

```pascal
{ pasparser_expr.inc:3663 -- reads the global AT USE }
szDeclTk := ParseTypeKind;
if (szDeclTk = tyRecord) and (LastTypeRecId <> REC_NONE) then
  prevTok := RecSize(LastTypeRecId)
else
  prevTok := SizeOfSlot(szDeclTk, LastTypeStrCap);

{ pasparser_decl.inc:1033 -- CAPTURES into locals first, which is the safe form }
fileElemTk  := ParseTypeKind();
fileElemRec := LastTypeRecId;
fileElemCap := LastTypeStrCap;
```

The second is what discipline looks like and nothing makes it the rule. Both
read three globals that `ParseTypeKind` set as a side effect; the first reads
them at the point of use, the second within three lines of the call.

## Why this is not the other four routes

| route | pair comes from | checkable at the call site? |
| --- | --- | --- |
| 1 same record | one `Syms[i]` / `Alias*[ai]` | yes — a mismatch is not expressible |
| 2 same lookup pair | two arrays, one index | yes |
| 3 paired resolver | one function returning both | yes |
| **4 parameter + global** | **a call, and a global channel** | **no** |
| 5 state machine | the parse's own history | no, but it has ONE owner |

Route 5 at least has a single owner for its history. **Route 4's invariant has
none**: the setter is `ParseTypeKind`, the reader is any caller, and the
contract between them is a comment in `defs.inc`.

## The fix that already worked once

Not a gate row and not a tighter window — **a dedicated carrier**, which is what
`ArrTypeElemStrCap` is and why it exists. The same move applies here: have
`ParseTypeKind` return the cap (or fill a small record) rather than leave it in
a global for the caller to pick up in time.

## Done when

`SizeOfSlot`'s companion is reachable from the same expression that produced its
kind at all thirteen call sites, so route 4 is empty and the taxonomy's
unmechanisable half is routes 5 only.

## Done — 2026-09-09, and the fixture's own controls are the finding

`ParseTypeKindSized(var recId, strCap): TTypeKind` sits beside `ParseTypeKind`
in `pasparser_decl.inc` and returns all three from one call. Both route-4 sites
now take it (`pasparser_expr.inc`'s SizeOf type-name arm, `pasparser_decl.inc`'s
`file of` element), so **route 4 is empty** and the taxonomy's unmechanisable
half is route 5 only. Wired: `test/test_sizeof_of_a_frozen_string_type_name.pas`
→ `test_sizeof_frozen_name26`, byte-identical to fpc 3.2.2.

**TWO POSITIVE CONTROLS FAILED TO FIRE BEFORE ONE DID, AND BOTH FAILURES WERE
THE FIXTURE'S FAULT, NOT THE REFACTOR'S.** They are worth more than the row.

**First: the fixture was AIMED AT A SITE IT NEVER REACHES.** Its four
`SizeOf(<name>)` rows do not enter the changed resolver at all. Measured with a
probe registered as `PXXDBG=p.sized`: it fires **exactly twice** for the whole
program, both times from the `file of` element site. The SizeOf re-parse arm is
gated by `BuiltinTypeNameNeedsDecl`, which holds **six names** — `shortstring`,
`textfile`, `file`, `pchar`, `pansichar`, `pwidechar` — and `S10` is a user
alias, answered by the alias arm at `pasparser_expr.inc:3987`, which already
takes `AliasTk[i]` with `AliasStrCap[i]` from one indexed carrier. That is
route 1. **The rows were pinning a path that never had this defect**, and the
ticket's own repro sketch is what made that look like the changed one. They are
kept, labelled, and are not a control.

**Second, and the general one: the readout COLLAPSED the two answers.** The
`file` row does reach the changed site, and with the alias cap write deleted
from `ParseTypeKind` it still printed `3 cc 3` — correct count, correct value,
correct position, wrong element width. A typed file is written and read through
the **same** width, so `FileSize`, the value and `FilePos` are all invariant to
that width being wrong. Only the BYTE length separates them, and the fixture
was not printing it. Reopening both files as `file of Byte` gives `bytes 33 12`
correct against **`bytes 24 12`** under the control — the row now fails on the
control binary and passes on the real one, both asserted.

So this fixture ran green through two deliberate breakages of the code it was
written for. It is `A GUARD THAT CANNOT FAIL IS NOT A GUARD` and
`CHOOSE A PROBE WHOSE RIGHT ANSWER DIFFERS FROM THE DEFAULT` arriving together,
and neither would have been noticed from the output: **a self-consistently wrong
width is indistinguishable from a correct one at every readout except the one
outside the file's own type.**

**Residual, stated rather than closed:** the refactor removes the window at the
two sites that had it; it does not make a FUTURE caller unable to open one,
because `LastTypeStrCap` and friends still exist for the arms that set them. No
Pascal program can sample "a caller added later", so nothing here is a control
for that and the fixture says so in its own header.

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 14547b15f.

**One near-miss worth a line, because it nearly landed:** the CONTROL binary —
built before the `Erase` calls existed — was run once from the repo root, and
`git add -A` staged `sizeoffrozen.dat` and `sizeoffrozen2.dat` as new files.
Caught by reading `git status` rather than by any check. A fixture that writes
to its CWD produces artefacts that a blanket add will commit, and the ones that
get you are from the throwaway binaries you built to break it, not from the
fixture you are shipping. The shipped fixture Erases both files however it is
wired; nothing enforces that for the next one.

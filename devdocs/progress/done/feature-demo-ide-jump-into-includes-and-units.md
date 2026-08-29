---
slug: feature-demo-ide-jump-into-includes-and-units
track: B
prio: 35
type: feature
blocked-by: []
summary: "garin's diagnostic parser keys off `a number between the first two colons` and carries no file, on the stated assumption that the compiler names one main unit. Since 2026-08-21 that is no longer true: a diagnostic in an include or a `uses`d unit is followed by an `in: <path>` line, which the IDE currently drops, so jump-to-error lands on the wrong file."
status: done
owner: frank-b
---

# The IDE cannot jump into an include or a unit

`apps/ide/garin/builder.pas` parses compiler output as
`<prefix>:<line>: <message>` and comments that *"the source file is the caller's
business (the compiler names one main unit)"*.

That assumption held until
`bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file`. The compiler now
emits, under a diagnostic whose token did not come from the main source:

```
pascal26:63: error: expected expression
  in: test/incdiag/badinc.inc
  near:  procedure Bogus  begin if >>> then  end
```

The line number is now a real line **of that file**, not of the main source — so
an IDE that keeps the number and drops the path jumps to line 63 of the wrong
file, which is worse than the old behaviour where the number was wrong in a way
nobody could act on.

## The ask

- `TDiagList` carries an optional file per diagnostic: a bare `  in: <path>`
  line attaches to the diagnostic above it.
- The faces (eliah's error list, ilja) open that file when jumping.
- `bochan/main.pas`'s canned sample output gains a case with an `in:` line so the
  rendering is exercised without a compile.

Deliberately NOT a compiler change: the `in:` line was put on its own line
precisely so the existing `<prefix>:<line>:` contract keeps working, and an IDE
that ignores it behaves exactly as it did before. This ticket is the upgrade,
not a repair.

## Gate

Track B: build with `$(PXX_STABLE)`, `make demos`. A diagnostic in an include
opens the include.

## Resolution (frank-b, 2026-08-29)

### What landed

`TDiagList` carries an optional file per diagnostic. `DiagFile(i)` returns `''`
when the compiler emitted no `in:` line, and `''` keeps the old meaning exactly:
the main unit, which is the caller's business because the caller named it. That
is a real distinction rather than a missing value — `test_incdiag_main_fail`
asserts the compiler does **not** emit `in:` for the main source.

The recogniser keys on the **indent plus the literal `in:`**, not on
colon-splitting. Two reasons, both measured against real output: a path may
contain a colon and the diagnostic parser's "number between the first two
colons" would take a bite out of it; and the indent is what the compiler's
format actually guarantees as the continuation marker (`near:` is indented the
same way and must stay ignored). A stray `in:` with no diagnostic above it is
dropped rather than promoted into a diagnostic the compiler never reported.

`eliah` opens the named file before jumping. When the file will not open it
moves the caret **nowhere** and says so in the output pane: falling back to
"then at least scroll the current file" would reintroduce precisely the bug —
a confident jump into the wrong buffer. The error list now renders
`badinc.inc:63: error: ...` when a file is known, because two rows reading
`L63:` are otherwise indistinguishable while pointing into different files.

`bochan`'s canned sample gained the `in:`/`near:` continuations, copied from
real pinned-compiler output rather than composed, plus the orphan case.

`ilja` does not exist. The README lists it as "(later)" and there is no
directory, so eliah is the only face there was to change.

### Verified end to end, not just on the fixture

A fixture proves the fixture parses. I also fed `TDiagList` the **real** output
of all three shapes:

| source | count | line | file |
| --- | --- | --- | --- |
| `test_incdiag_main_fail` | 1 | 10 | `` (correctly unnamed) |
| `test_incdiag_inc_fail` | 1 | 63 | `test/incdiag/badinc.inc` |
| `test_incdiag_unit_fail` | 1 | 13 | `test/incdiag/badunit.pas` |

Line 63 of `badinc.inc` and line 13 of `badunit.pas` are both the actual
offending `if then;`, so the jump target is right and not merely present.

`eliah --smoke` gained the include case as the ticket's own acceptance
criterion. **Checked that it is not vacuous:** with the open-the-file branch
neutered and everything else identical, it fails with
`SMOKE FAIL: clicking an include diagnostic did not open the include`. A green
that would be green anyway is the failure mode I have been tripping over all
session.

Gates: `apps/ide/test.sh` 168/168, `eliah --smoke` OK, and eliah links
`libgtk-3.so.0`. No compiler change, as specified.

### Two pre-existing breakages found on the way, both fixed here

Neither is this feature, but the feature could not be verified around them.

1. **`apps/ide/build.sh` passed no GTK3 include root**, so eliah was being
   compiled against GTK2 headers while linking `libgtk-3.so.0` — the silent
   ABI mismatch from
   [[feature-b-pcl-should-assert-its-gtk-version-rather-than-rely-on-an-accident]],
   live in the IDE. The assertion I landed an hour earlier is what surfaced it,
   which is the first thing it caught.
2. **eliah's `uses` was missing `gtk3_c`.** An interface uses-clause does not
   re-export, so `gtk_main_quit`, `gtk_button_clicked` and `g_timeout_add` were
   undefined even though `gtk3` sees them. `lib/pcl/gtk3widgets.pas` already
   spells it the way this now does. Verified this is version-independent: the
   transitive lookup fails under GTK2 and GTK3 headers alike.

**Together those mean eliah did not build at all before this ticket**, and
nothing said so, because `grep "apps/ide" Makefile` returns nothing — the whole
IDE is unwired. Noted on
[[chore-a-wire-the-nine-passing-orphan-tests-and-gate-check-test-wiring]] rather
than in a new ticket.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.

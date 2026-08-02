---
track: B
prio: 40
type: bug
blocked-by: []
status: done
owner: claude-B
---

# `apps/ide/eliah/main.pas:1431` — `EliahForm.Win.Caption`: no `Win` member exists

Found while verifying `bug-pascal-array-of-pointer-deref-loses-the-record-type`
(a Track A compiler fix): once that fix landed, `apps/ide/eliah/main.pas` gets
past the `plist[j]^.Kind` line it was previously blocked on (line 784) and
compilation now progresses much further into the file, but stops at a
**second, unrelated** wall:

```
pascal26:1431: error: "Win": no such member on this record/class
  near:  if Length  EliahForm  >>> Win  Caption
```

```pascal
    { status title reflects the open design + node count }
    EliahForm.UpdateTitle;
    if Length(EliahForm.Win.Caption) = 0 then begin writeln('SMOKE FAIL: title empty'); Halt(1); end;
```

`EliahForm` is a `TEliahForm = class(TForm)` (`apps/ide/eliah/main.pas:60`).
Neither `TForm` (`lib/pcl/forms.pas`) nor any class in its chain
(`TWinControl`, `TControl` in `lib/pcl/controls.pas`) declares a `Win` field
or property — `Caption` lives directly on `TControl`, so this line likely
should just be `EliahForm.Caption` (a stray `.Win` that was never valid), or
`Win` was meant to be a real property that was never added. Grepped the whole
tree for `.Win.` / `property Win` in `lib/pcl/**` and `apps/**` — no other use
exists anywhere, so this is not an established PCL pattern being missed by the
compiler.

This blocks `tools/gui_suite.sh` reaching a green `eliah_ide -- compile` step
(the Gate on the ticket above named that as a goal); once this is fixed, re-run
`tools/gui_suite.sh` to confirm the eliah IDE build is fully green.

## Not Track A
Confirmed this is not a compiler bug: the member genuinely doesn't exist on
any class in the hierarchy anywhere in `lib/pcl` or `apps/ide/garin`. This is
an app-level bug in `apps/ide/eliah/main.pas` itself (or a missing PCL
feature it was written against) — file-owned by Track B (apps built with pxx
are Track E, file-owned by B) per `CLAUDE.md`'s Track E note.

## Resolved 2026-08-02 — option (a), and the code says so rather than the odds

The ticket offered (a) drop `.Win` or (b) add a real `Win` property, and
reasoned that (a) was "more likely given no other reference exists". The
deciding evidence is one line up rather than an absence: `UpdateTitle`, the
procedure the smoke check is verifying, ends with

```pascal
  Self.Caption := s;        { apps/ide/eliah/main.pas:631 }
```

So the value the check wants is on `Caption` itself. `EliahForm.Win.Caption`
would have been reading a different thing even if `Win` existed — (b) would have
made it compile and still assert nothing useful. Changed to
`EliahForm.Caption`.

Confirmed: `main.pas` compiles (it needs `-Fuapps/ide/garin` for the shared
`buffer`/`runner` units, as `tools/gui_suite.sh` does), and `eliah --smoke`
prints `SMOKE OK`, which is the step this ticket said it was blocking.

## Suggested fix direction
Read `apps/ide/eliah/main.pas` around line 1431 and its git history / any
sibling `.Win` usage (there is none) to decide: (a) drop `.Win` and just call
`EliahForm.Caption`, or (b) if `Win` is meant to be a distinct wrapped-window
object, add the property. (a) is more likely given no other reference exists.

## Log
- 2026-08-02 — resolved, commit PENDING.

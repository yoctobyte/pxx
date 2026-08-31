---
summary: "CLI: --widgetset=<name> as sugar for -dWIDGETSET_<NAME>, so the flag reads like Lazarus' -ws"
type: feature
track: A
prio: 20
---

# `--widgetset=<name>` — the CLI half of widgetset selection

- **Type:** feature (compiler CLI — **Track A**, small)
- **Opened:** 2026-07-31 by Track B, landing
  [[feature-pcl-widgetset-select]]. That ticket said the compiler touch should
  be filed as its own Track A slice if cleaner; it is, because the library half
  needed no compiler change at all.

## What already works, without this

Selection and the sparse (widgetset x OS) matrix live entirely in
`lib/pcl/interfaces.pas` and are driven by an ordinary define:

```sh
pxx -dWIDGETSET_GTK3 ...        # also the default when none is given
pxx -dWIDGETSET_WIN32 ...       # refused, with the reason, at compile time
```

The default build is byte-identical to an explicit `-dWIDGETSET_GTK3`, and every
unsupported cell is a hard compile error naming the combination and why. All of
that is asserted in `tools/gui_suite.sh`.

## What this ticket adds

Only the spelling. `--widgetset=gtk3` reads like Lazarus' `-ws gtk3` and is what
a user coming from Lazarus will reach for; it should set the corresponding
`WIDGETSET_<NAME>` define and change nothing else.

- Parse `--widgetset=<name>` in the option loop.
- Uppercase the name and `PasDefine('WIDGETSET_' + upper)`.
- An unknown name is worth rejecting at the CLI with the list of known ones,
  since `interfaces.pas` can only diagnose the names it has arms for and an
  unknown define would silently fall through to the gtk3 default.

Deliberately NOT part of this: the matrix itself. Keeping the table in
`interfaces.pas` is what makes "adding a widgetset = one arm plus one
TWidgetSet subclass" true; teaching the compiler about widgetsets would put
half the rule in the wrong repo layer.

## Gate

`make test` + self-host byte-identical; `--widgetset=gtk3` produces a binary
byte-identical to `-dWIDGETSET_GTK3`, and `--widgetset=nonsense` is rejected by
name.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, unchanged.** `pxx --widgetset=gtk3 …` against
the pinned compiler still answers `unknown option: --widgetset=gtk3`, so the
CLI half has not landed incidentally. Still small and still only a spelling —
the `-dWIDGETSET_*` path it would sugar continues to work.

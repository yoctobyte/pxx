---
slug: feature-c-diagnostics-name-the-module-they-are-in
track: C
prio: 30
type: feature
blocked-by: []
summary: "A Pascal diagnostic now prints `in: <path>` when the error is in an include or a `uses`d unit. The C frontend has the same information already — CModRange* is populated in every build, not just under -g — and prints nothing, so an error in a crtl module or an included header still reports a bare line number."
status: backlog
---

# C diagnostics could name their module and do not

Fallout from `bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file`,
which gave the Pascal side an `in: <path>` context line under the diagnostic
whenever the offending token did not come from the main source.

The C frontend needs no new plumbing to do the same:

- `CModRange*` (defs.inc) already maps token index → the `.c` module, and is
  **explicitly not gated on `DebugInfo`** — the duplicate-definition check needs
  it in every build (`bug-c-static-functions-in-different-crtl-modules-collide`).
- `CModuleOfTok(t)` already reads it back, returning a `KeyStrs[]` index.
- `WriteDiagSourceFile` in `lexer.inc` is the single place that decides what to
  print; today it consults only the Pascal table and so says nothing for C.

So the shape is: when the Pascal table has no answer, ask the C one. Two
details to get right rather than assume:

1. **Headers vs modules.** `CModRange*` deliberately attributes a static defined
   in a header to the module that *included* it — which is right for the
   duplicate check and possibly wrong for an error message, where the user wants
   the header. The preprocessor's own `# <line> "<path>"` markers carry the
   header path; `CPPathAtDepth` may already have what is wanted.
2. **The main `.c` must stay silent**, exactly as the main `.pas` does — the user
   typed that name.

## Gate

An error in an included header, and one in a second `.c` module, each name the
file they are in; an error in the main `.c` prints no `in:` line. Self-host
byte-identical. The Pascal rows in `test-core` (`test_incdiag_*`) must stay green
— they assert that a Pascal main source prints no `in:` line, which is the same
rule.

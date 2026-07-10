---
prio: 40
---

# C frontend: support `-D<name>[=<value>]` command-line macro defines

- **Type:** feature (C frontend / driver) — **Track C** (`compiler/cpreproc.inc` predefines
  + the driver arg parse).
- **Status:** working

## What
pxx does not honour `-D` on the command line for C. During the duktape bring-up,
`-D__STDC_VERSION__=199901L` had no effect (a predefined-macro probe still reported it
undefined), so there was no way to inject or override a preprocessor macro without editing
`cpreproc.inc` and rebuilding the compiler.

## Why it matters
`-D` is the standard knob for configuring third-party C: feature flags, `DUK_USE_*` /
`SQLITE_*` / `-DNDEBUG`-style build options, and quick bisection of macro-gated code paths
during corpus bring-up. Every corpus target (sqlite, tcc, duktape, …) is normally built
with a handful of `-D`s; today we can only approximate that by baking defaults into
`cpreproc.inc`.

## Scope
- Parse `-D<name>` (value defaults to `1`) and `-D<name>=<value>` in the C driver, and seed
  them as predefined macros in `CPreprocess` alongside the built-in `__STDC__` /
  `__x86_64__` / `__LP64__` / `__STDC_VERSION__` literals (see
  [[bug-c-preproc-missing-stdc-version-predefine]]).
- Optionally `-U<name>` to undefine.
- **Check whether the Pascal frontend already accepts `-D`** (conditional-define switches):
  if so, mirror the plumbing rather than adding a parallel path.

Not urgent — no corpus target is blocked *solely* on this today (duktape's two real walls
were the predefine + the macro-arg string bug, both fixed directly). Nice-to-have that pays
off across the whole C corpus.

[[bug-c-preproc-missing-stdc-version-predefine]] · [[feature-c-corpus-duktape]]

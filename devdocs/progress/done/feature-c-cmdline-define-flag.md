---
prio: 40
---

# C frontend: support `-D<name>[=<value>]` command-line macro defines

- **Type:** feature (C frontend / driver) — **Track C** (`compiler/cpreproc.inc` predefines
  + the driver arg parse).
- **Status:** done

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

## RESOLVED 2026-07-10

`-D<name>[=<value>]` and `-U<name>` now seed the C preprocessor. The driver
already parsed `-D`/`-U` but routed them only to the Pascal name-only define
table; added a parallel raw capture (`CCmdDefRaw`/`CCmdUndefRaw`, defs.inc)
applied in `CPreprocess` via `CPApplyCmdlineDefines` — after the built-in
`__STDC__`/`__STDC_VERSION__`/… literals (so `-D` overrides a builtin,
newest-wins) and undefs last (so `-U` beats a same-name `-D`). `-D<name>` with
no `=` defaults to `1` (cpp convention); values are strings (`-DBAR=42`,
`-D__STDC_VERSION__=199901L`). `-U` reuses `CPUndef` (kills all stacked entries),
so it can remove a predefined builtin.

Verified: `-DFOO`→1, `-DBAR=42`, `-DNDEBUG`, `-U__STDC_VERSION__` drops the
builtin. Regression `test/cdefine_flag_b239.c` (Makefile test-core, built with
`-DGUARD=42 -DON -DOFFME -UOFFME`, exit 42). Self-host byte-identical;
testmgr quick GREEN; c-testsuite 220/220.

## Log
- 2026-07-10 — resolved, commit fb1baedf.

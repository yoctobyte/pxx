---
track: N
prio: 75
type: feature
blocked-by: []
summary: "Every .py module reachable from the main program is lexed onto the token stream BEFORE any module body is parsed (PyLexImportClosure), and the importer reuses those tokens, so call-site parameter typing (PyParamTypeFromSites) scans every Python range instead of the def's own file. Sites are attributed to a def by receiver class (token-only, by name, subclasses count) and by arity/keywords, so same-named methods in different classes no longer veto each other. Int claims are back on. Fixture: test_nilpy_call_sites_are_visible_across_modules. Demo: compiles, 290 of 1501 parameters typed, the hot rows (Quat.rotate, Vec3.dot, Grid.at) unchanged for reasons named below."
status: done
---

# Lex the import closure before parsing, so call-site typing sees every caller

**Mechanism.** After the main program's tokens are lexed, `PyLexImportClosure`
walks every `import`/`from` statement at every depth (`PyLexImportClosureRange`)
and resolves each module through the ordinary importer (`ParseUsesUnit` with
`PyLexClosureMode` set and `SoftUnitResolve` on). In closure mode
`ParseUsesUnitBody` stops right after `ResolveUsesUnitSource`: it rolls the unit
slot back, lexes the module with `PyLexModuleForClosure` (which plants the
`-g` file range and recurses into the module's own imports, `CurUnitDir` set to
the module's directory for package-relative imports) and exits without
parsing. A guarded import whose module does not exist resolves to nothing and
is skipped, exactly as the real import later is. When the real import arrives,
the `.py` arm asks `PyLexedRangeStart(path)` and parses from the recorded
token start instead of lexing again (`PXXDBG=n.closure` prints both the
`lexed` and the `reuses tokens from` lines). No uses-edge is recorded in
closure mode, so the unit graph is unchanged.

**Attribution.** With every module visible, `.at(` is declared by six classes
in the demo and `at(self, x, z)` would veto on `Route.at(distance)`. So a site
belongs to a def only when (1) its receiver, statically read token-only
(`self`, `Cls(...)`, `mod.Cls(...)`, a local with one binding, a field the
typer knows), names a class related by descent to the def's class
(`PyClassDeclTok` / `PyClassNthBase` / `PyClassNamesRelated`; an unknown class
or base is treated as related, so nothing is lost by ignorance), and (2) its
argument list fits the header: positional count within the non-star
parameters, every keyword declared, every parameter without a default given.
A site that does not fit is skipped, not counted as a veto. Module-qualified
constructions and calls (`pkg.shapes.Box(2)`) count as sites for modes 0 and
2: while they were excluded, `Box(2)` was invisible next to late.py's
`Box(2.5)` and `Box(2).area(2)` printed 4.0 for CPython's 4.

**Ints are claimed again** (`PyIsSiteIntTk`, bools still veto): the reason
they were off was the invisible caller, and the fixture rows Grid.cols /
Grid.rows / drift.n / tick.n flipped from veto to tk=13 as the old ticket
predicted. The local typer's tail accepts an int base too.

**Demo (lekkerzeilen, 2026-09-16, scratch build, `--threadsafe`):** compiles
in 125 s (165 s before, same box, not a controlled comparison), value rows of
the peer's parity test unchanged. Census: 1501 unique parameter rows, 290
typed (186 float, 56 int, 48 str), 757 give up at the FIRST site; 638 sites
were filtered by attribution (215 of them one-argument calls that did not fit,
i.e. the `Route.at(distance)` class the peer's static model predicted). The
hot rows did not move, and the trace says why: `at.x`/`at.z` give up on a
caller local `sx` the local typer cannot type (`local sx of def@248419 ok=0`),
`rotate.v`, `dot.o`, `inverse_rotate.v` give up because the argument is a
Vec3, which is the class-typed lever (next ticket), and `__add__.o` has no
sites because operators do not spell `.__add__(`.

**Residuals, owner this seat:** an untypeable argument vetoes the whole def at
the first site (a `sites=1 gaveup=1` row may have many sites), which is the
conservative reading and the biggest remaining population; `getattr(o, "f")(x)`
callers are invisible; `from pkg import submodule` was and is unsupported ("no
unit named pkg", pre-existing); a module named only in a dead `if` arm is lexed
(harmless, costs tokens); an empty `__init__.py` is not lexed at all.

Fixture: `test/test_nilpy_call_sites_are_visible_across_modules.npy` with
`test/nilpy_clo_geom.py`, `test/nilpy_clo_user.py`, `test/nilpy_clopkg/`.
On the one-file-at-a-time importer its values still match (the typing changes
codegen, not results) and its census and reuse rows fail, which is the
positive control.

## Log

- 2026-09-16 frankuser (Fable): built and measured; 130 Makefile rows of every NilPy test that imports a sibling module green on the scratch binary before the rebuild, commit 5dbee723e.

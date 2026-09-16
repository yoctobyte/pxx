---
track: N
prio: 70
type: feature
blocked-by: []
summary: "A module-level constant passed as an argument -- `v.step(SIM_DT)` with `SIM_DT = 1.0 / 60.0` at the top of the file -- is a typed call site for call-site parameter typing (PyModuleConstType): bound exactly once in its file, at depth 0, as a plain `NAME = expr` of scalar type, never named by an import, not a local or parameter of the enclosing def. Third lever after the import closure and the class-typed parameter. Fixture: test_nilpy_a_module_constant_is_a_typed_call_site."
status: done
---

# A module-level constant is a typed call site

The Arm A census of the lekkerzeilen demo (2026-09-16) showed `Vessel.step`'s
`dt` giving up on its one site, `vessel.step(SIM_DT)`: a module-level
constant, which the local typer (a def's own bindings) cannot see. The
lekkerzeilen seat counted the shape: 474 module-level bindings in 37
modules, 472 bound exactly once, 284 to a literal or literal arithmetic (131
int, 105 float, 48 str).

**Mechanism.** In the site loop of `PyParamTypeFromSites`, a bare-identifier
argument that is neither a parameter nor a binding of the enclosing def
(`PyHeaderHasParam`, `PyBodyBindsName`) is asked of `PyModuleConstType(nm,
fileLo, fileHi)` over the site's own Python range: the name must be bound
exactly once in the file, at indentation depth 0 (a binding inside a
module-level `if`/`try` does not count), as a plain `NAME = expr` (no chain,
no tuple target, no augmented step), never appear in an `import`/`from`
statement, and the expression must type as float, int or str with no def
scope; a bool is not claimed. The constant is then one more SITE for the
parameter and must agree with every other site, so a float constant beside
an int site still vetoes: the lever adds evidence, never overrides the rule.
`PyTokBindsName` is the binding test shared with `PyBodyBindsName`.

**Residuals, owner this seat:** a constant imported by name (`from consts
import SCALE`) is not typed in the importing file (the binding is elsewhere);
`x or 12.0`, a subscript, a list element remain untypeable.

## Log

- 2026-09-16 frankuser (Fable): built on a scratch binary while Arm B's tier ran; fixture green, the four site-typing fixtures green, commit 4e2507c6b.
- 2026-09-16 lekkerzeilen seat's score of a7f5e0817948428f (Arm C + the three fixes): value parity 52 lines bit-identical to CPython (284 constants claimed, 131 int, nothing truncated); full-map diff Arm B -> C 126 symbols, net +7252 B; baseline -> C 292 symbols, net -60541 B. SailRig.best_sheet 2414 -> 607 B, 81 -> 8 calls, sse 1 -> 3. One regression, _read_furniture +8471 B / +354 calls: its `into` parameter's two sites both pass `self.furniture`, a field bound to `[]`, so the self-field typing (fix d) gave `into` a TPyList class claim -- the same claim an annotation `into: list` makes -- and the typed list receiver compiles LARGER with no arithmetic gained. Banked as an observation: a claim removes dispatch, and whether that shrinks or grows a body is a codegen property the census cannot see; the map diff can.

---
track: N
prio: 75
type: feature
blocked-by: []
summary: "A bare parameter whose call sites all pass an instance of ONE class is typed as that class (PyParamTypeFromSites answers tyClass with PyPSLastCi), and a constructor parameter typed that way makes a class-typed field; the body's attribute reads on it become field reads instead of variant lookups. Certain sites only: self, a construction, a local bound once to a construction, a caller's parameter its own sites typed. A `= None` default, a second class, an untypeable site or a body rebinding vetoes. Fixture: test_nilpy_a_bare_parameter_is_typed_as_a_class_from_its_call_sites."
status: done
---

# Type a bare parameter as a class from its call sites

The second lever on top of the import closure (feature-n-lex-the-import-
closure-...). The demo's hot methods take objects: `Quat.rotate(self, v)`,
`Vec3.dot(self, o)`, `inverse_rotate(self, v)` all gave up at the first site
in the closure census because the argument was a Vec3 -- a class, which the
scalar typer could not claim. Now it can.

**Mechanism.** In `PyParamTypeFromSites`, a site's argument names a class
when the expression typer answers tyClass with a class index, when the
caller's own parameter was typed as a class by ITS sites (the existing
recursion, reading `PyPSLastCi`), or when the argument is exactly `self`,
exactly `Cls(...)` / `mod.Cls(...)`, or a local of the enclosing def bound
once to a construction -- read by `PyStaticReceiverClass`, the same reader
that attributes a `.name(` site by its receiver, given the argument's end
where the `.` would sit. An expression that merely ENDS in a construction
(`a + Vec3(...)`) is whatever the operator returns and is not read. Every
site must name the same class; a subclass at one site and its base at
another is a disagreement. A `= None` default vetoes (a class slot holds no
None), and so does any untypeable site, even beside a class default (a
variant reaching a class slot is not a loud coercion). The class must be
registered when the answer is computed (`FindUClassNonRecord`; a class in a
module the parser has not reached is a name only), and the body must not
rebind the parameter at all (`PyBodyBindsName`: `v = v.norm()` or `v =
None` would store something else into a class slot). The answer is memoised
with its class index (`PyPSMemoCi`), so the shell, the pre-pass and the body
parse agree. Consumers: the def header and `PyParseMethod` set the param's
class index from `PyPSLastCi`; the constructor field typer gives the field
`REC_UCLASS_BASE + ci`. The class pre-pass registers the parameter as
tyClass without a rec id, exactly as an annotated class parameter is.

**What it does to the earlier fixture:** `tick(g, dt, n)` in
test_nilpy_a_bare_parameter_is_typed_from_its_call_sites now types `g` as a
Grid (`tk=6 cls=Grid`), values unchanged.

**Residuals, owner this seat:** a class declared LATER in the same module
than the def whose parameter it would type is not registered yet at the
pre-pass and the (memoised) answer is variant; a module-level constant as an
argument (`v.step(SIM_DT)`) is untypeable -- the local typer knows only the
def's locals -- and that is the next lever (Vessel.step's `dt` in the demo
gives up on exactly that); an element of a list (`for item in rows:
item.span`) is untypeable.

## Log

- 2026-09-16 frankuser (Fable): built on a scratch binary while the closure's tier ran; fixture green, psites and closure fixtures green.

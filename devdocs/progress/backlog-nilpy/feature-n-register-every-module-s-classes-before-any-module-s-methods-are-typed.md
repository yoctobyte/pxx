---
track: N
prio: 75
type: feature
blocked-by: []
summary: "Call-site parameter typing sees every module's SITES (the import closure is lexed first), but classes are still registered one module at a time, so a field of a class in a later module (sim.py's self.torque, a Vec3) is unknown when an earlier module's method parameter (math3d.py's Quat.rotate v) is asked and memoised. Register every module's classes -- names, fields, method signatures -- over the whole closure before any module's methods are typed; then class-typed fields feed sites and the demo's Quat.rotate gate (P16/P17, 11 of 14 sites already provably Vec3) becomes reachable."
status: open
---

# Register every module's classes before any module's methods are typed

**Measured 2026-09-16, both sides.** The lekkerzeilen seat traced the demo's
`.rotate(` sites: 11 of 14 are provably Vec3 (a construction or a local bound
to one); the three others pass `Quat.inverse_rotate`'s `v` and `to_world`'s
`body_offset`, whose own sites pass FIELDS -- `self.torque`,
`self.angular_velocity`, `.bow`, `.offset`, `.mount` -- bound in sim.py's
constructors as `Vec3.zero()` or from a parameter every construction passes a
Vec3 for. The compiler-side probe (`$SP/fld/main.npy`, class V then class B
with `self.u = V(1.0, 2.0)` and `self.t.dot(self.u)` in B.step): with the
enclosing class lent to the typer, `self.u` is STILL untypeable at V.dot's
first ask, because B is registered after V and the answer is memoised at the
first ask (the three header parses must agree, so the memo cannot be
revisited). Chains are one round short by construction: the class-typed
lever (feature-n-type-a-bare-parameter-as-a-class-from-its-call-sites) types
a parameter from fields only when the field's class was registered EARLIER
in the stream.

**The shape of the fix.** The closure already lexes every module before the
main program's first pre-pass (PyLexImportClosure). Add a class pre-pass over
the whole closure in the same place: for every Python range, register the
classes (names and parents), then their fields (the `fieldsOnly` mode of
PyRegisterClassMembers), then the method signatures -- so that when any
module's parameter is asked, every class of the program is known. What has
to be understood first: classes are registered into their UNIT's scope
(ParsePyUnit / CompiledUnit slots), and PyRegisterClassMembers runs under a
current-unit context (CurrentUnitIdx, visibility for FindUClassNonRecord);
the pre-pass would have to enter each module's unit slot without parsing its
body, the same trick PyLexClosureMode plays in ParseUsesUnitBody, and the
real import must then skip what was registered (PyMembersHoisted is the
existing per-class "already registered" flag). The class-typed parameter
answers memoised during this pass are final, which is what makes the order
matter: names for all, then fields for all, then methods for all.

**Order of value, from the demo:** Body.step lost a third of its code from
class-typed parameters alone; with class-typed fields the same lever reaches
Quat.rotate, Vec3.dot, and every `self.<vec>` argument in sim.py.

**The seam already exists, per module.** The class-member hoist pass in
pyparser.inc (the `phase` loop over `class` headers, ~43120) is already
two-phase for exactly this reason inside one module: phase 0 DETECTS what
every class assigns to every field (PyCollectClassFieldJoins) with the
comment "nothing here may depend on a class registered later, which is the
whole reason the pass exists", phase 1 registers members, and PyParseClass
skips its own second run through PyMembersHoisted. The closure-wide version
is that loop run over every Python range (PyPyRangeAt) under each range's
unit slot, before ParsePyUnit's per-module run, which then finds everything
hoisted. ParsePyUnit itself sets PyScanLo/MainProgramTokCount per module and
runs PyPreScanImports, PyCollectModuleLocalsAST; the hoist head is
saved/restored around it (savedHoist).

Owner: the seat that built the typer (frankuser). Depends on nothing.

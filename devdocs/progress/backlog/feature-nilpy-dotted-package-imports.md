---
summary: "nilpy: dotted package imports — `from reportlab.pdfgen import canvas`, so a shim can be NAMED for the module it implements"
type: feature
track: N
prio: 55
---

# nilpy: dotted package imports

- **Type:** feature (Nil-Python frontend, import resolution) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26. The one concrete blocker for the naming strategy in
  `devdocs/dev/python-compat-tiers.md`.

## Why

NilPy maps `import X` onto the Pascal unit resolver's `uses X`, which is what let
`re`, `configparser` and `tkinter` be provided with NO frontend work: name the unit
for the module and importing code resolves unchanged. That is the whole T1 strategy
and it is worth a lot — an application compiled by pxx should not have to be edited
to say so.

It stops at a dot. `from reportlab.pdfgen import canvas` names a PACKAGE and a
submodule, and a Pascal unit name cannot contain one, so no unit called `reportlab`
satisfies that import. songformatter needs exactly this form, and it is the norm in
real Python — `os.path`, `xml.etree.ElementTree`, `reportlab.lib.colors`.

Until it lands, T1 shims only work for modules imported by a single bare name.

## Shape

Two parts:

1. **Resolve a dotted module path to a unit.** Either a package layout —
   `lib/py/reportlab/pdfgen.pas` reached from `reportlab.pdfgen` — or a documented
   mangling (`reportlab.pdfgen` -> unit `reportlab_pdfgen`). The layout is nicer to
   read and groups a package's shims together; the mangling is less machinery.
   Pick one and write it in the tiers doc.
2. **Accept the dotted form in both import statements**: `from a.b import c` and
   `import a.b` / `import a.b as ab`. The plain `from <unit> import name` case
   already works (commit "dotted base classes and from <unit> import name"); this
   extends the module side of it.

Note the existing three-segment handling in `PyStdlibCallAhead` is for dotted
CALLS (`os.path.join`), a different thing — that table maps a call onto a pylib
function. This ticket is about the IMPORT resolving to a unit.

## Consequence when it lands

`pxxpdf` gets renamed to `reportlab` (or a `reportlab` package of shims over the
same pdfgen backend), and songformatter's fallback import comes OUT — the app goes
back to unmodified source, which is the point.

## Gate

`make test-nilpy` green with a `.npy` importing a two-segment package shim from
`test/nilpy_units`, in both the `from a.b import c` and `import a.b` forms, +
`--tier quick` + self-host byte-identical.

---
summary: "nilpy: dotted package imports — `from reportlab.pdfgen import canvas`, so a shim can be NAMED for the module it implements"
type: feature
track: N
prio: 55
---

# nilpy: dotted package imports

- **Type:** feature (Nil-Python frontend, import resolution) — **Track N**
- **Status:** done
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

**Decided (Rene, 2026-07-26): resolution is a MAPPING, and the unit keeps OUR name.**
`import reportlab` resolves to a unit named `mimic_reportlab`; a dotted path mangles
onto the same scheme, `reportlab.pdfgen` -> `mimic_reportlab_pdfgen`. No file in the
tree carries the upstream name, the tree says what each shim is, and the dotted case
needs no package-directory machinery. Reasoning in
`devdocs/dev/python-compat-tiers.md`.

Two parts:

1. **A shim mapping in the import resolver.** Python module name (dotted or not) ->
   `mimic_<mangled>` unit, consulted when the plain unit lookup fails, so ordinary
   `uses`/`import` behaviour is untouched. Report the substitution
   (`reportlab -> mimic_reportlab (shim, subset)`), and add a `--no-shims` flag that
   makes any substitution an error — that flag is how a "compiled with no shims"
   claim gets proven later.
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

## Already fixed — verified 2026-07-31, closing

The decided `mimic_<mangled>` mapping landed since this ticket was filed.
Re-measured directly against the real `mimic_reportlab_*` shims already in
`lib/pcl`: `from reportlab.pdfgen import canvas`, `import reportlab.lib.colors`
and `import reportlab.lib.pagesizes as pagesizes` all resolve correctly,
each printing the exact substitution report the "Shape" section above asked
for (`reportlab_pdfgen -> mimic_reportlab_pdfgen (shim, subset)`). Checked
the failure mode too, to make sure it's the right kind: `import
xml.etree.ElementTree` fails with "no shim mimic_xml_etree_elementtree" —
i.e. the RESOLUTION mechanism works and the failure is a missing individual
shim (nobody has written an ElementTree mimic), not a mechanism gap.

Added `test/test_nilpy_dotted_package_import.npy` — no test previously
pinned this mechanism directly (songformatter's own gate is elsewhere and
not part of `make test-nilpy`).

## Gate

`make test-nilpy` green with a `.npy` importing a two-segment package shim from
`test/nilpy_units`, in both the `from a.b import c` and `import a.b` forms, +
`--tier quick` + self-host byte-identical.

## Log
- 2026-07-31 — resolved, commit ade766a5b.

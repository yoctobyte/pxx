---
slug: bug-n-a-unit-alias-rebind-is-silently-ignored
track: N
type: bug
prio: 40
status: backlog
owner: ""
created: 2026-09-10
found-by: frankZ
tags: [nilpy, imports, aliases, cpython-divergence]
blocked-by: []
summary: "`from . import a as x` then `from . import b as x` answers A; CPython answers B. `FindUnitOrAlias` scans the alias table from index 0 and takes the FIRST row for a name, so a rebinding is appended and never reached -- silently, with no diagnostic. Split off from bug-n-a-dead-guarded-import-arm-still-binds-its-unit-alias, which was the same table biting through a dead try arm and is fixed; this is the straight-line half and has NO corpus consumer today. Not merely 'make the scan take the last row': the NilPy shim substitutions (`<module> -> mimic_<module>`) share this table and are registered globally rather than per statement, so last-wins would change which unit a shimmed module resolves to. The measurement that decides it is whether any shim row is ever legitimately overridden by a later registration."
---

# Measured 2026-09-10, compiler `6d53c745ea69`

```python
from . import one as backend      # one.B == 99
from . import two as backend      # two.B == 27
print(backend.B)                  # pxx: 99      CPython: 27
```

Order is textual and the first registration wins; the second row is appended to
`UnitAliasName`/`UnitAliasReal` and `FindUnitOrAlias` never reaches it. No
diagnostic — a rebinding simply does nothing.

# Why it is filed rather than fixed

**No corpus consumer.** It was found while measuring the seam idiom, whose
rebinding goes through a `try`/`except` and is fixed. A straight-line rebind of a
module alias is rare in real Python because it has no purpose: the second import
is the only one anyone reads.

**And the obvious fix is not obviously right.** The table is not only Python's
`import as`. It also holds:

- `uses X as Y` from Pascal (`feature-uses-alias-as`);
- the NilPy shim mapping, `<module>` -> `mimic_<module>`, registered so a
  qualifier resolves onto the shim;
- the dotted-package rows (`pkga.sub` -> `pkga_sub`).

`FindUnitOrAlias` CHASES the chain — `ps -> pkga_sub -> mimic_pkga_sub` — and
the chase re-enters the same first-match scan at every hop. Flipping the scan to
last-wins changes the chase, not just the lookup, and the comment on
`FindUnitOrAlias` records that an explicit alias winning over a same-named unit
was itself a deliberate fix (`lib/pcl/tk.pas` shadowing `import tkinter as tk`).

# The measurement that would settle it

**Is any row in this table ever legitimately overridden by a LATER
registration?** If shim and package rows are only ever registered once per name,
last-wins is safe and is a two-line change. If a later row is ever meant to lose
— and the `tk` case suggests the table's rows are not all peers — then the fix
is a per-KIND rule, not a scan direction, and it is a bigger job than the bug
deserves at this rank.

Instrument: count duplicate names in `UnitAliasName` at the end of a compilation
of the NilPy corpus, grouped by which site registered them.

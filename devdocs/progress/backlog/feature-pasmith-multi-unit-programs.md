---
summary: "pasmith: generate multi-UNIT programs — the last structurally unreachable bug class"
type: feature
prio: 55
---

# pasmith: multi-unit programs

- **Type:** feature (Track T — the tool). Findings file into the owning lane as always.
- **Status:** backlog
- **Opened:** 2026-07-14, split out of [[feature-pasmith-widen-grammar]] when the rest of
  that widening landed.

## Why

Every other rung on the widening list is in ([[feature-pasmith-widen-grammar]]): records
+ forward pointers, enums/sets, arrays, `string[N]`, exception hierarchies, parameter
modes, OOP, ansistring. **Multi-unit is the one gap left, and it is a structural one** —
several of the worst bugs we have shipped were unit-ORDER dependent and simply cannot be
expressed by a single-file generator:

- exception class matching across units — `on E: T` missed a descendant declared in a
  *later* unit (b339);
- symbol resolution / import bugs, where the defect only appears when the importer is
  large or the import order changes;
- initialization-section ordering.

## Shape

Emit N units plus a program: each unit declares types (records, enums, exception
classes), some of them referring to types from earlier units; each exports procedures and
functions; the program uses them in a random order. The checksum discipline is unchanged
(one number out), so the oracle machinery needs nothing new.

The real work is in the **driver**, not the generator: `tools/pasmith_run.py` currently
compiles one file. It has to write a unit set to a directory, put that directory on both
compilers' unit paths (`fpc -Fu`, `pxx -Fu`) and compile the program against it — and the
seed must still reproduce the whole set byte-for-byte.

## Acceptance

`pasmith --seed N --units 3` emits a program plus 3 units that FPC accepts (the
generator's contract), the driver compiles and runs the set under every oracle, and a
divergence still names its statement via the trace diff. One bounded run logged here,
clean or not.

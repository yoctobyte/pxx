---
slug: feature-n-the-sqlite3-module-db-api-over-the-c-library
track: N
type: feature
prio: 65
status: backlog
owner: ""
created: 2026-09-10
found-by: frankB
tags: [nilpy, stdlib, sqlite3, shim, lekkerzeilen]
blocked-by: []
summary: "`import sqlite3` binds NOTHING, so `sqlite3.connect(path)` is `no member connect came of the qualifier sqlite3`. It is the wall on lekkerzeilen/world.py:188, and atlas.py reports the SAME line number through `from . import world` — two subjects, one site. The import machinery already maps a NilPy import onto the unit resolver, so a C header in /usr/include links identically; that is not the gap. The gap is that `connect`/`execute`/`fetchone` are Python DB-API names and the header exports `sqlite3_open`/`sqlite3_prepare_v2`, so a mimic_sqlite3.pas shim over the C library is what is missing. The surface the corpus needs is small and measured below: connect (with uri=), Error, and on the connection execute / fetchone / close, with execute ITERABLE and its rows unpacking as tuples."
---

# The wall, measured 2026-09-10 at compiler `a812b9549413`

```
lekkerzeilen/world :: pascal26:188: error: no member connect came of the
  qualifier sqlite3 -- check what sqlite3 resolves to; an import that bound
  nothing gives exactly this (sqlite3.connect)
lekkerzeilen/atlas :: pascal26:188: (the same text)
```

**`atlas.py:188` is `if box is None:` and has no sqlite3 within a hundred
lines.** Both rows are `world.py:188`, reached through `from . import world` —
an error raised inside an imported module prints with THAT module's line number
and no file name. One site, two subjects. Do not rank this on two modules.

# THE SURFACE THE CORPUS ACTUALLY NEEDS — measured, not taken from the module index

Every `sqlite3.` reference in lekkerzeilen:

```
  gauges.py:174   self.db = sqlite3.connect(path)
  atlas.py:104    db = sqlite3.connect("file:%s?mode=ro" % index, uri=True)
  app.py:878      except (sqlite3.Error, OSError) as exc:
  world.py:188    db = sqlite3.connect(self.path)
  world.py:524    db = sqlite3.connect("file:%s?mode=ro" % pathname2url(path), uri=True)
  world.py:525    except sqlite3.Error:
  world.py:701    db = sqlite3.connect(self.path)
  world.py:753    db = sqlite3.connect(self.path)
```

and on the connection object:

```
  db.execute(sql)                 iterated directly, rows unpacked as tuples
  db.execute(sql, (name,))        one bound parameter
  db.execute(...).fetchone()      and tested against None / for truthiness
  db.close()
  dict(db.execute("SELECT key, value FROM meta"))     a cursor into a dict
  {row[1] for row in db.execute("PRAGMA table_info(furniture)")}
```

**Four connection members and one module function.** No Cursor object is ever
named, no `commit`, no `executemany`, no `row_factory`, no context manager.
`uri=True` is a KEYWORD argument, which matters for where the shim can live —
see the note on the table below.

# What is NOT the gap

`PyParseImportRun` already maps a NilPy `import` onto the same unit resolver a
Pascal `uses` uses, and `compiler/pyparser.inc` names sqlite3 as its own worked
example of a C header being imported and dynamically linked. So the LINKING is
solved. What no header can supply is the DB-API: CPython's `sqlite3` is a
wrapper module, and `connect` / `execute` / `fetchone` exist nowhere in
`sqlite3.h`.

# Where the shim goes, and the one thing that decides it

A `lib/rtl/mimic_sqlite3.pas` reached by the `mimic_` fallback, exactly as
`mimic_queue` and `mimic_struct` are — `import sqlite3` then resolves there and
`--no-shims` can still turn the substitution into an error.

**It must be a CLASS with methods, not entries in the dotted-call table**, and
`uri=True` is why: the table takes positional arguments only
([[bug-n-a-stdlib-dotted-call-cannot-take-a-keyword-argument]]), while a
keyword binds to a Pascal parameter NAME on an ordinary constructor —
`Queue(maxsize=2)` proves that path works and `lib/rtl/mimic_queue.pas` records
what it cost to get there.

# The hard part, and it is not the C calls

`db.execute(sql)` is ITERATED and its rows UNPACK as tuples of mixed type:

```python
for name, kind, stride, verts, indices in db.execute(...):
```

So execute must return something with NilPy's iteration protocol whose elements
are TPyLists of variants, and the column values have to carry their sqlite type
tag across. `dict(cursor)` needs the same object to be accepted by `dict()`.
That is the design work; `sqlite3_open` / `prepare_v2` / `step` / `column_*` is
the easy half.

# Positive control

`sqlite3.connect(":memory:")`, a `CREATE TABLE` and two `INSERT`s, then the
three shapes above — iterate-and-unpack, `dict(cursor)`, `fetchone()` — diffed
against CPython on the same source. **A test that only opens a connection and
closes it passes without any of the row machinery working**, which is the whole
of what this ticket is for.

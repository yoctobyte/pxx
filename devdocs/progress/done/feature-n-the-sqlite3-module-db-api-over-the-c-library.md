---
slug: feature-n-the-sqlite3-module-db-api-over-the-c-library
track: N
type: feature
prio: 65
status: done
owner: frankB
created: 2026-09-10
found-by: frankB
tags: [nilpy, stdlib, sqlite3, shim, lekkerzeilen]
blocked-by: []
summary: "`import sqlite3` bound NOTHING, so `sqlite3.connect(path)` was `no member connect came of the qualifier sqlite3`. FIXED by lib/rtl/mimic_sqlite3.pas, a DB-API shim over the system libsqlite3 reached through the `mimic_` fallback. The wall is cleared on all FOUR lekkerzeilen modules that name sqlite3 (world, atlas, gauges, app) plus `__main__` behind gauges. The linking was never the gap -- a NilPy import already maps onto the unit resolver, so a C header links identically; the gap was that `connect`/`execute`/`fetchone` are DB-API names that exist nowhere in sqlite3.h. Shipped surface: `connect(database, uri=)`, `Error`, and on the connection `execute` / `executemany` / `executescript` / `commit` / `rollback` / `close` / `total_changes`, with a cursor that iterates, unpacks, slices and answers `fetchone` / `fetchall`."
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


---

# RESOLVED 2026-09-10 — `lib/rtl/mimic_sqlite3.pas`

Compiler binary `8ea6cf9845db`; nothing in `compiler/**` was touched, so this
is entirely a library unit plus one test.

## Two corrections to what is written ABOVE, and the second is the same mistake twice

**The population line was wrong: FOUR modules name sqlite3, not two.** The
census row that produced this ticket reported world and atlas, and atlas was
correctly identified here as a cascade of world's line 188 — that part stands.
What the ticket then did was rank the ticket on the CENSUS ROWS instead of on
the corpus, and a first-failure census reports the first wall per subject, so
gauges (whose first wall was `import threading`) and app (whose first wall is
`import ctypes`) were invisible. Grepping the package:

```
  atlas.py:31,104        gauges.py:35,174        world.py:12,188,512,524,525,
  app.py:13,878                                    531,701,753,754,762,858
```

**And the member surface was measured on world and atlas and asserted over all
of them.** The ticket says in its own words *"No Cursor object is ever named,
no `commit`, no `executemany`"*. gauges.py does all three, plus `executescript`
and `total_changes`:

```
  gauges.py:175  self.db.executescript(SCHEMA)
  gauges.py:176  self.db.commit()
  gauges.py:183  self.db.executemany(...)
  gauges.py:188  before = self.db.total_changes
```

That is **exactly the correction frankZ made to my threading ticket eight hours
earlier** — `name=` was passed at all four Thread construction sites and was
missing from a surface list I had called complete — and the generalisation I
wrote down at the time is the one that catches this: **an API surface is what a
module OFFERS; a corpus surface is what the corpus ASKS FOR, and only the second
specifies a shim.** I had the rule and did not apply it to my own next ticket.
The failure mode is specific and worth naming: I enumerated `sqlite3.` matches
(which finds every module) and then enumerated MEMBERS only on the two modules
the census had named. One grep was over the corpus and the next was over the
census's own output. A shim built to the shorter list refuses 100% of gauges
while looking finished.

## What shipped

The header of `lib/rtl/mimic_sqlite3.pas` carries the mechanism. Three things
that cost time and would cost it again:

1. **`uses sysutils, strings, pylib` — the pylib-LAST order, which is the
   reverse of every other mimic unit.** pylib and sysutils each declare a class
   named `Exception`; they are siblings under `ExceptionBase`, not one class.
   pylib renders `str(e)` from the message only for `o is Exception` with
   PYLIB's. Measured: with the usual `uses pylib, sysutils`, `"%s" % exc` on a
   caught `sqlite3.Error` printed `<__main__.Error object at 0x...>` while a
   builtin `ValueError` and a NilPy `class MyErr(Exception)` both printed their
   message — one concept, three spellings, one of them in the wrong tree.
   app.py:878 is that line. `mimic_urllib_error.pas` documents the same hazard
   and dodges it by descending from `OSError`, a name only pylib declares; that
   is not open here, because app.py catches `(sqlite3.Error, OSError)` as two
   different things. `class(pylib.Exception)` is not accepted by the dialect
   (`base type not found: pylib`), so the uses order is the whole mechanism.

2. **`total_changes` is a `property`, not a parameterless function.** In Pascal
   those two look interchangeable; from NilPy they are not. A `function
   total_changes: Integer` read as `db.total_changes` answers
   `<bound method at 0x...>` — NilPy hands back a bound method exactly as
   Python's `obj.method` does, and cannot know this one was meant as an
   attribute. This is the INSTANCE-side sibling of the qualified-module-constant
   gap fixed the same evening for `math.pi`, and the resolution is the opposite
   one: there the fix was in the compiler, here the shim is simply written in
   the spelling that means what it says.

3. **A zero-length bind through a NULL pointer becomes SQL NULL.**
   `sqlite3_bind_blob`/`_bind_text` document that a nil data pointer makes the
   call equivalent to `sqlite3_bind_null` *regardless of the length*, so `b""`
   round-tripped as `None` and `len()` on it raised TypeError three statements
   later, with nothing in the failure naming the bind. A stack byte is bound
   instead; TRANSIENT copies immediately, so its address is a fine source for
   zero bytes.

A Pascal class from a mimic unit satisfies NilPy's iterator protocol in full —
measured before any of the above was written, with a throwaway unit: `for a, b
in rows`, `list(rows)` and `dict(rows)` all work, because `PyUserObjNoArgDunder`
dispatches `__iter__`/`__next__` through the RTTI at run time and does not care
which frontend declared the class.

## Transactions are reproduced, not flattened

CPython's legacy `isolation_level=""` opens an implicit transaction before the
first write and holds it to `commit()`, so `close()` without a commit LOSES the
writes. Flattening that to autocommit would make an unfaithful program work here
and fail under CPython, so it is reproduced. The discriminator is
`sqlite3_stmt_readonly` — asked of the prepared statement's opcodes, not of the
SQL text — which gets INSERT, UPDATE, DELETE, REPLACE, CREATE and a write
through a trigger right without this unit parsing any SQL, and reports
BEGIN/COMMIT/ROLLBACK as read-only so the flag cannot trip over its own
transaction control.

## The positive control the ticket asked for, built

`test/test_nilpy_the_sqlite3_module.npy`, wired into `test-nilpy`, **byte-
identical to CPython on all 30 rows** with the database directory handed in
through `PXX_SQLTEST_DIR` from a fresh `mktemp -d`. Every shape is one the
corpus writes and each is there because a shim can be "finished" and fail it:
iterate-and-unpack (five names), `dict(cursor)`, `fetchone() is None`,
`bool(fetchone())`, a row that SLICES, a set comprehension over a `PRAGMA`,
`executemany`, `total_changes` as an attribute, `uri=True` against a missing
file and against a real one, `except sqlite3.Error` with `"%s" % exc`, NULL
columns as None, a BLOB with an embedded zero byte, and the two transaction rows
(close-without-commit loses the write; rollback undoes it).

**Three rows were deliberately reworded away from the oracle's own output**:
`sorted(meta.items())`, `row[1:]` and `fetchall()` render pairs as `('k','v')`
under CPython and `['k','v']` here, because NilPy has no tuple type. That is a
DIALECT property and not a sqlite3 one, and an oracle-generated expectation
would have banked it in the wrong file. Printed key-by-key and through a
comprehension instead.

## The walls behind this one, measured at `8ea6cf9845db`

```
  world     pascal26:447: error: expected expression        <- Furniture(**dict(zip(...)))
  atlas     pascal26:447: (the same, through `from . import world`)
  gauges    pascal26:422: error: expected ')' before '.'    <- except (urllib.error.URLError, ...)
  __main__  pascal26:422: (the same, through gauges)
  app       pascal26:10: import: no unit named ctypes and no shim mimic_ctypes
```

`--threadsafe` is required for gauges/`__main__`/app; without it they stop at
the threading diagnostic, which is the compiler working. **Two same-line-number
cascades again** (447 across world/atlas, 422 across gauges/`__main__`) — the
sixth and seventh confirmed instances in this corpus. Neither new wall is
sqlite3's and neither is filed here.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7e2a50150.

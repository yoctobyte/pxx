---
slug: bug-n-no-shims-refuses-instead-of-resolving-what-the-shim-shadowed
track: N
type: bug
prio: 40
status: done
owner: unassigned
created: 2026-09-11
found-by: frankB
tags: [nilpy, imports, shims, cli]
blocked-by: []
summary: "FIXED 2026-09-11 (786b88673e62). `--no-shims` REFUSED a shimmed import outright -- `no unit named sqlite3 (--no-shims refuses the mimic_ substitution)` -- instead of resolving it as if the shim were absent, so for a name that ALSO resolves another way the flag meant `do not import` rather than `do not substitute`. It now falls through to the host-header probe, which is what its own message always claimed. Found by landing lib/rtl/mimic_sqlite3.pas: the shim WINS over /usr/include/sqlite3.h, correctly and as pasparser_proc.inc predicted by name, and that took two pinned tests with it in BOTH spellings. Both now compile under the flag."
---

# What it does, measured 2026-09-11 at compiler `848d67a6757a`

```
$ printf 'import string\nprint(1)\n' > /tmp/st.npy
$ pascal26 /tmp/st.npy /tmp/st
note: string -> mimic_string (shim, subset)
ok: ...
$ pascal26 --no-shims /tmp/st.npy /tmp/st
pascal26:1: error: import: no unit named string (--no-shims refuses the mimic_ substitution)
```

`/usr/include/string.h` and `/usr/include/sqlite3.h` are both present.

# Why it matters, and how it was found

`import sqlite3` resolved to `/usr/include/sqlite3.h` through the ordinary unit
resolver and linked libsqlite3 directly. `compiler/pyparser.inc` uses that as
its own worked example of a C header being imported, and
`test/test_nilpy_import_sqlite.npy` pins it by calling
`sqlite3_libversion_number()`.

Landing `lib/rtl/mimic_sqlite3.pas` made the shim win, and that test went RED —
correctly, and the capability was gone in BOTH spellings: with shims the mimic
answers, without them the import is refused. Worked around in the shim by
EXPORTING the C entry points it binds, which restores the pinned test and is
allowed by Track N's rule (CPython has no `sqlite3_step`, so a program using it
is one CPython rejects). **That workaround does not generalise**: it covers the
entry points one shim happens to need, not sqlite3.h.

# The fork, stated as what we want rather than as a mechanism

Does `--no-shims` mean **"do not substitute"** — resolve the name the way the
compiler would if no `mimic_` unit existed — or **"refuse anything a shim would
have answered"**?

The first reading is what the flag's own message says it does (*"refuses the
mimic_ substitution"*) and is what makes it useful for the purpose it was
added for: finding out what a program really needs. The second is what it
implements. Nobody chose the second; it is what falling out of the resolver
early does.

# Not taken because it is not obviously narrow

The change is one arm in the import resolver, but it widens what `--no-shims`
ACCEPTS, and the existing `--no-shims` rows in the suite were written against
today's behaviour. Whoever takes it should check those rows first: a test
asserting that `--no-shims` refuses a name that also has a header would go from
green to red for a reason that is the fix working.

# Positive control

`import sqlite3` under `--no-shims`, asserting it COMPILES and that
`sqlite3_libversion_number()` answers — the header route, reached with the shim
present but disabled. And the negative: a shimmed name with NO other
resolution (`import queue`) must still be refused, or the flag has stopped
meaning anything.

---

## 2026-09-11, frankB — fixed. The first reading, which is the one the message already claimed

Compiler `786b88673e62`. `--no-shims` now resolves a shimmed name as if the
`mimic_` unit were absent: the two conditions that guarded the host-header probe
in `compiler/pasparser_proc.inc` gained `NoShims or (not PyMimicShimExists(...))`
where they previously required the shim to be missing. The flag's refusal
message is unchanged in spirit and sharper in wording — `no unit named X
(--no-shims refuses the mimic_ substitution, and nothing else of that name
resolved)` — so a refusal now says which of the two things happened.

**The shim EXPORT workaround this ticket describes is reverted.** It restored
one test and not the other, and the reason it could not is worth keeping:
`sqlite3_open`'s NilPy spelling returns the handle, where the C function returns
a status and writes the handle through an out-parameter. **Out-param return
lifting is a frontend TRANSFORMATION applied to a C declaration, not a name that
can be re-exported from a Pascal unit** — so exporting `sqlite3_open` from the
shim gives a program the symbol and the wrong shape, and
`test_nilpy_sqlite_crud.npy` stayed red while `test_nilpy_import_sqlite.npy`
went green. Two tests, one workaround, and the half that passed is the half that
only needed a name. The bindings are private again in `mimic_sqlite3.pas`.

Both pinned tests now compile with `--no-shims` in the Makefile, with a header
note in each `.npy` saying that the flag is load-bearing and why — a reader who
drops it gets the DB-API module, which is what a Python program means by
`import sqlite3` and is correct.

`pasparser_proc.inc`'s host-header probe comment predicted this collision by
name, in advance, and said the shim should win. It was right about the
precedence; the missing piece was the door out of it. Comment updated in place
to record that its own example came true on 2026-09-11.

Positive control as specified: `import sqlite3` under `--no-shims` compiles and
`sqlite3_libversion_number()` answers a well-formed 3.x.y. Negative control:
`--no-shims` on a shimmed name with no other resolution is still refused, and
the suite already had TWO rows asserting it, both green — the `.py` shim row
(`FAIL: --no-shims accepted a mimic_ .py shim`) and the dotted-import row, which
additionally greps the log for `no-shims` so it cannot pass on some other
refusal.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

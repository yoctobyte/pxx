---
summary: "test-nilpy hard-codes sqlite 3.45.1's version number, so the suite is red on any box with a different system sqlite"
type: bug
track: N
prio: 60
---

# `test_nilpy_import_sqlite` asserts the *host's* SQLite version

- **Type:** bug — test portability (Track N, `.npy` tests)
- **Found:** 2026-08-01 by Track T while enrolling `test-nilpy` into the watcher
  tiers ([[bug-t-xeon-job-set-covers-only-a-third-of-nilpy-tests]]).

## The defect

`Makefile:216`:

```make
./$(COMPILER) test/test_nilpy_import_sqlite.npy /tmp/test_nilpy_import_sqlite26
test "$$(/tmp/test_nilpy_import_sqlite26)" = "3045001"
```

and the test itself is two lines:

```python
import sqlite3
print(sqlite3_libversion_number())
```

`sqlite3_libversion_number()` returns `major*1000000 + minor*1000 + patch` of
**whatever `libsqlite3.so.0` the box has**. The assertion pins `3045001` =
**SQLite 3.45.1**.

| box | system sqlite | returns | result |
|---|---|---|---|
| borg | 3.45.1 | `3045001` | passes |
| xeon | 3.46.1 | `3046001` | **fails** |

Measured on xeon: `sqlite3 --version` → 3.46.1, program prints `3046001`,
exit 0. Nothing is wrong with the compiler, the import, or the dynamic link —
the FFI call works perfectly and returns the correct answer for this host. The
assertion is simply wrong to demand a specific one.

`make test-nilpy` therefore fails at the second recipe line on xeon, taking the
whole target down before the other ~860 lines run.

## Why it went unnoticed

The whole `test-nilpy` target was outside the watcher's job set (that is the
sibling Track T ticket), so it has only ever been run on boxes that happen to
ship SQLite 3.45.1. The moment it is enrolled on a second box with a different
distro, it reds.

## Fix

The test is a good one — it proves `import sqlite3` resolves a C header and
dynamically links a real `.so` — so keep it and assert something invariant:

- a **lower bound**: the number is ≥ some minimum the API requires, or
- **agreement with the host**, comparing against `sqlite3 --version` computed
  into the same encoding, which keeps the test meaningful on every box:

```make
test "$$(/tmp/test_nilpy_import_sqlite26)" = "$$(sqlite3 --version | awk '{split($$1,v,"."); print v[1]*1000000 + v[2]*1000 + v[3]}')"
```

- or simply assert it is non-zero and well-formed, if the point is only "the
  symbol resolved and was callable".

Pinning an exact upstream version in an assertion makes the test a report on
the build box rather than on pxx.

## Note for the enrollment

Track T is enrolling `test-nilpy` regardless — 238 `.npy` files being invisible
is the larger problem, and one correctly-attributed red is better than that.
Expect this single job to be RED on xeon until the assertion is fixed; it is
**not** a compiler regression and should not be triaged as one.

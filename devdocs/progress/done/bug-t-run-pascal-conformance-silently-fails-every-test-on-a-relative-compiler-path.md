---
slug: bug-t-run-pascal-conformance-silently-fails-every-test-on-a-relative-compiler-path
title: "run_pascal_conformance.sh reports every test as a COMPILE ERROR when given a relative compiler path"
track: T
prio: 55
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-25
summary: "`tools/run_pascal_conformance.sh ./compiler/pascal26 ...` fails 51 of 107 tgeneric tests; the same run with `/home/neo/frank1/compiler/pascal26` passes 61 and fails 0. The runner `cd`s into the suite dir before invoking the compiler, so a relative `$CC` no longer resolves — and the failure surfaces as `compile error`, i.e. as a COMPILER bug, for every test at once."
---

# Symptom

```
$ tools/run_pascal_conformance.sh ./compiler/pascal26 library_candidates/fpc-testsuite/tests/test --only 'tgeneric*'
test-pascal-conformance: 10 pass, 51 fail, 43 skip, 3 auto-gated (of 107)

$ tools/run_pascal_conformance.sh /home/neo/frank1/compiler/pascal26 \
      /home/neo/frank1/library_candidates/fpc-testsuite/tests/test --only 'tgeneric*'
test-pascal-conformance: 61 pass, 0 fail, 43 skip, 3 auto-gated (of 107)
```

The per-test output names the real cause, but only if you look at one:

```
FAIL tgeneric12.pp — compile error:
    timeout: failed to execute process: No such file or directory (os error 2)
```

# Cause

Both compile paths run the compiler from inside another directory:

```sh
( cd "$SUITE"  && timeout "$TIMEOUT_S" "$CC" $CCFLAGS "$name" "$bin" ) ...
( cd "$WORK"   && timeout "$TIMEOUT_S" "$CC" $CCFLAGS "drv_$uname.pas" "$bin" ) ...
```

`$CC` defaults to `$ROOT/compiler/pascal26` (absolute), so the default invocation
is fine and testmgr's is fine. Only an operator passing the path by hand hits it
— which is exactly the debugging position where a wall of red is most expensive,
because it reads as "my change broke 51 tests".

`$SUITE` has the same shape and the same fix.

# Fix

Absolutise both at parse time, right after the positional arguments are taken:

```sh
case "$CC"    in /*) ;; *) CC="$(CDPATH= cd -- "$(dirname -- "$CC")" && pwd)/$(basename -- "$CC")" ;; esac
case "$SUITE" in /*) ;; *) SUITE="$(CDPATH= cd -- "$SUITE" && pwd)" ;; esac
```

and, separately, make a compiler that cannot be EXECUTED a hard error rather than
a per-test compile failure: the `[ -x "$CC" ]` check already exists but runs
before the `cd`, so it passes on a relative path that will not resolve later.

`tools/run_c_conformance.sh` should be checked for the same shape (it is the
file this one was written from).

## Fixed 2026-08-26 (Track T)

Both paths are absolutised immediately after the positional arguments are taken,
before anything can `cd`, and the `[ -x "$CC" ]` check moved to *after* that —
which is what makes it meaningful. It used to run against the path as given, so
a relative path that would not resolve post-`cd` passed the check and then
failed 51 times, one test at a time. A compiler that cannot be executed is now a
hard error: the difference between "your setup is wrong" and "your compiler is
broken" is exactly what this ticket is about.

Verified, same command as the symptom above:

| invocation | before | after |
| --- | --- | --- |
| `./compiler/pascal26 library_candidates/...` | 10 pass, **51 fail** | **62 pass, 0 fail**, 42 skip |
| absolute paths | 61 pass, 0 fail | 62 pass, 0 fail, 42 skip |

Relative and absolute now agree exactly, which is the property that was missing.

**`tools/run_c_conformance.sh` does NOT have this bug** — checked, because this
file was written from it and the ticket asked. It takes `$CC` and `$SUITE` the
same way, but it never `cd`s, so a relative path keeps resolving and the failure
cannot occur. Same argument shape, no manifestation. Left alone rather than
"fixed" symmetrically: an edit that changes no behaviour still has to be read
and understood by the next person, and a comment claiming to fix a bug that was
never there is worse than no comment.

If a `cd` is ever added there, this is the trap to remember — which is why that
sentence is in this ticket rather than in a comment nobody will find.

## Log
- 2026-08-26 — resolved, commit PENDING-COMMIT.

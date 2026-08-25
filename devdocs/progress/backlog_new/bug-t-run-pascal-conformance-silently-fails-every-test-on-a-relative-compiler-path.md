---
slug: bug-t-run-pascal-conformance-silently-fails-every-test-on-a-relative-compiler-path
title: "run_pascal_conformance.sh reports every test as a COMPILE ERROR when given a relative compiler path"
track: T
prio: 25
type: bug
blocked-by: []
status: backlog_new
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

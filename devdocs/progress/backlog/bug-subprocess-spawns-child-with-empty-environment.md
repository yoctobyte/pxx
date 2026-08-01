---
track: B
prio: 45
type: bug
---

# Every spawned child process gets a completely empty environment

Found 2026-08-01 while researching [[decide-env-write-side]] (the write-side
policy question). This is independent of that decision — it's not about
writes, it's that no environment reaches a child at all, even unmodified.

## What's there

`lib/rtl/subprocess.pas` (`Popen.Create`) and `lib/rtl/sysutils.pas` (its own
`PalVforkAndExec` call site) both hard-code:

```pascal
var env: array[0..0] of PChar;
...
env[0] := nil;
...
pid := PalVforkAndExec(PChar(prog), @argvp[0], @env[0], ...);
```

So `subprocess.Popen`/`run`/`call` and sysutils' own process-spawn path both
pass an empty `envp` unconditionally. A pxx-compiled program that spawns a
child today hands it `PATH=`/`HOME=`/`TZ=`/nothing — not even the parent's
own unmodified environment, regardless of whether that program ever touches
`os.environ`/`setenv` itself.

## Why this is a bug, not (only) the write-side feature gap

The read side of environment access (`GetEnvironmentVariable`,
`os.environ.get`, C `getenv`) is done and correct within the current
process. This is a different, narrower thing: a plain `subprocess.run(["some_tool"])`
with no environment manipulation anywhere in the program still gets a tool
that can't find `PATH`, doesn't know `$HOME`, etc. — silently, since nothing
errors, the child just behaves as if run with `env -i`.

## Fix

Pass the same environment buffer the read side already loads (from
`/proc/self/environ`) as `envp` at both `PalVforkAndExec` call sites, instead
of the hardcoded empty array. This is the read-only baseline and should land
regardless of which option [[decide-env-write-side]] picks — even "don't
support writing" (option 1) shouldn't mean "children start with nothing."
If/when the write-side decision lands, the same buffer (now possibly
mutated) is what gets passed here — this fix is the prerequisite either way.

## Gate

`make test` + a subprocess test that spawns a child reading a variable the
parent inherited from ITS OWN environment (not one the test program set),
confirming it's visible to the child.

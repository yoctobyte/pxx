---
track: B
prio: 45
type: bug
status: done
owner: claude-B
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

## Resolved 2026-08-02

Reproduced first, exactly as filed — a child spawned by a pxx program saw
nothing:

```
parent HOME=[/home/rene]   parent PATH set=TRUE
child  HOME=[]             child count=1        <- the whole environment
```

### Fix

`sysutils` now exposes `EnvironmentBlock`, and both spawn sites pass it instead
of a hard-coded `nil` terminator.

The environment is not copied to build it. `EnvLoad` already read
`/proc/self/environ`, whose records are **already** the NUL-terminated
`NAME=VALUE` strings `execve`'s `envp` wants — it just parsed them into Pascal
strings and dropped the block. That block is now kept (`EnvRaw`) and `envp` is a
table of pointers into it, so the read side and the child's environment are the
same bytes.

Two ordering constraints, both noted at the definition:

- `EnvironmentBlock` is called in the **parent, before vfork**, because on first
  use it does I/O and after vfork the child must not.
- The pointers target a global that is never freed, so they stay valid through
  the child's exec (which shares this address space until it execs).

An empty `envp` remains a valid `envp`: if `/proc/self/environ` cannot be
opened, the table is `[nil]` and behaviour is what it was, which is right for a
process that genuinely has no environment.

### Verified

| | before | after | host |
| --- | --- | --- | --- |
| `ExecutePipeline` child `HOME` | *(empty)* | `/home/rene` | `/home/rene` |
| child variable count | 1 | 71 | 71 |
| `subprocess.call` child sees `HOME`/`PATH` | no | yes | — |

Both call sites are covered: `ExecutePipeline` (sysutils) and
`subprocess.Popen` (the NilPy façade, checked from a `.npy` program).

### The regression test was checked against the bug

`test/lib_child_env.pas`, wired into `lib-test`. It was rebuilt against a copy
of the pre-fix RTL to confirm it actually fails there — and that turned up
something worth recording:

> With an empty `envp`, `test -n "$PATH"` **still succeeds**, because `/bin/sh`
> synthesises a default `PATH` when it inherits none.

So a test written around PATH — the obvious variable, and the one this ticket's
own prose leads with — would have passed against the bug. `HOME` has no such
fallback, and comparing it to the parent's actual value is stronger still. Both
are in the test, along with a negative case (a variable nobody set is still
unset in the child, so the assertions are not passing for a trivial reason).

## Log
- 2026-08-02 — resolved, commit PENDING.

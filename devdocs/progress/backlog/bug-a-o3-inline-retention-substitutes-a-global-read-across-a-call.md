---
summary: "-O3 silently returns the wrong value: the non-leaf inline slice treats a GLOBAL read as re-readable and can evaluate it on the wrong side of the retained body's inner call, which writes it. localtime loses its timezone offset"
type: bug
track: A
prio: 80
---

# -O3 reads a global across the call that writes it (silent wrong value)

- **Type:** bug, silent miscompile — **Track A** (Track O work: `parser.inc`
  inline retention + `ir.inc` splice)
- **Filed:** 2026-08-02 by `claude@xeon` (Track T) from the `optdiff` oracle.
  **T owns the tool, never the bug** — bisected to one line and handed over.
- Found by `optdiff#shard8/12` at `28eb1a105ddb`, i.e. the -O-level
  differential caught it, not a test.

## The symptom

```
$ ./compiler/pascal26 -O2 -Ilib/crtl/include -Ilib/crtl/src test/ctime_localtime.c /tmp/a && /tmp/a
1700000000 utc=2023-11-14 22:13:20 local=2023-11-14 23:13:20     <- correct
$ ./compiler/pascal26 -O3 -Ilib/crtl/include -Ilib/crtl/src test/ctime_localtime.c /tmp/b && /tmp/b
1700000000 utc=2023-11-14 22:13:20 local=2023-11-14 22:13:20     <- local == utc
```

At -O3 the timezone offset silently becomes **0**. No crash, no diagnostic, a
plausible wrong value — the exact class the debugging playbook says is the
expensive one. Confirmed on a clean tree at HEAD after reverting every probe.

## Bisected to ONE gate

Each of the `OptLevel >= 3` gates was disabled in turn (set to `>= 4`), rebuilt,
and retested. Turning all of them off restores correct output; the single
responsible one is

```
compiler/parser.inc:273     if OptLevel < 3 then Exit;    { non-leaf inline slice }
```

Ruled out individually, each with its own build: nested inlining
(`ir.inc:7421`), inline slice 2c (`parser.inc:551`), argument deferral
(`ir_codegen.inc:4504`). The float-tree xmm sites were off in the all-off run
and are not implicated on their own.

## Mechanism — the protection covers ARGUMENTS, and this is a GLOBAL

The non-leaf slice lets a retained inline body contain a real call. Its own
comment names the hazard and the guard:

> The `InlineRetentionSawCall` flag makes the splice temp-capture every
> argument: a direct-substituted pure arg would otherwise be re-read AFTER the
> inner call's side effects.

and `ir.inc:3531` honours it:

```pascal
if InlineBodyHasCall[cpi] then anyImpure := True;   { force temp-capture of every ARG }
```

But `InlineExprSimple` also accepts a **global** as a simple, re-readable
expression element (`parser.inc`, the `skGlobal`/`skConst` arm), and nothing
temp-captures *that*. A global read inside the retained body can therefore be
evaluated on the wrong side of the body's own inner call — the call that writes
it.

`lib/crtl/src/time.c` is precisely that shape:

```c
static long pxx_tz_offset(long long t) {
  const unsigned char *b = (const unsigned char *)pxx_tz_buf;
  ...
  pxx_tz_load();          /* CALL — writes pxx_tz_buf / pxx_tz_len / pxx_tz_loaded */
  len = pxx_tz_len;       /* GLOBAL read, must happen AFTER the call */
  if (len < 44) return 0; /* reads 0 -> offset 0 -> local == utc */
}
```

Read `pxx_tz_len` before `pxx_tz_load()` instead of after and you get exactly
the observed output. `skConst` is fine (immutable); `skGlobal` is not.

## Suggested fix direction

Treat a global read the way an impure argument is already treated **when the
retained body contains a call**: either refuse `skGlobal` in `InlineExprSimple`
once `InlineRetentionSawCall` is set (simplest, costs a little inlining), or
temp-capture global reads into locals at the splice in source order alongside
the arguments (keeps the win, more work). Note the ordering trap in the first
option: the call may be *seen after* the global in validation order, so a
single forward pass is not enough — validate, then re-check.

Whatever lands, the invariant to write down is the one the code already half
states: **inside a call-bearing retained body, nothing mutable may be
substituted for re-reading — arguments and globals alike.**

## Gate

`test/ctime_localtime.c` produces identical output at -O0/-O2/-O3, `optdiff`
shard 8/12 goes green, and the self-host fixedpoint stays byte-identical (this
transform is -O3-only, so -O0/-O2 codegen must not move at all).

## Note for whoever fixes it

The optdiff report also carried a `Segmentation fault (core dumped)` line
adjacent to this diff. Direct runs at -O0/-O2/-O3 all exit 0, so that crash is
unexplained and may belong to another program in the same shard — worth a
glance, but do not assume it is this bug.

---
summary: "-O3 silently returns the wrong value: the non-leaf inline slice treats a GLOBAL read as re-readable and can evaluate it on the wrong side of the retained body's inner call, which writes it. localtime loses its timezone offset"
type: bug
track: A
prio: 80
status: done
owner: claude-AN-night
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


## Resolved 2026-08-02 — the ROOT CAUSE ABOVE IS WRONG. It was never the global.

Kept the slug (it is what the bisect pointed at), but the mechanism section is a
plausible story that was never diffed against anything, so: **no global read is
involved, and `time.c` was never the miscompiled code.** `pxx_tz_offset` is C,
and the C frontend does no inline retention at all — `TryRetainInlineBody` is
called from one place, the Pascal routine-body parser. The theory could not have
been true for a C program.

### What it actually was

A **string LITERAL argument to a Pointer parameter loses its +8 skip** over the
frozen string's length prefix when the -O3 inline splice TEMP-CAPTURES it.

Every ordinary position applies that decay — the call-argument path
(`ir.inc`, the AN_CALL arm's `IRTk[value] = tyString` + pointer-param test), the
assignment path, the binop path, the return path — four ad-hoc copies. The
splice's own argument capture in `IRInlineExpand` was a fifth site that did not,
so the raw `IR_CONST_STR` landed in the pointer slot and the callee got a
pointer at the length byte instead of at char 0.

Reachable only at -O3 because only a **call-bearing** retained body forces every
argument to be temp-captured (`InlineBodyHasCall` -> `anyImpure`); with direct
substitution the literal reaches the body's own argument position and decays
correctly. `__pxx_open` is exactly that shape (`Result := PalOpen(...)`), which
is why `lib/crtl`'s `pxx_tz_load` could not open `/etc/localtime`, `pxx_tz_len`
stayed 0, and the offset came out 0 — the observed symptom, reached by a
completely different route than the one this ticket described.

Same family as the recorded landmine "hand-built IR_ARG skips IRLowerCallArg".

### The 11-line repro

```c
extern int __pxx_open(const char *p, int flags, int mode);
const char *p = "/etc/localtime";
int a = __pxx_open("/etc/localtime", 0, 0);   /* -O2: 3   -O3: -2 */
int b = __pxx_open(p, 0, 0);                  /* -O2: 3   -O3:  3 */
```

The literal-vs-variable pair is the whole diagnosis: through a variable the
ASSIGNMENT already applied the decay, which is why this survived so long.

### What cracked it — a new probe, now permanent

`PXXDBG=a.inline` (added here, documented in `devdocs/dev/debug-switches.md`)
lists every routine whose body is retained for inlining, with its shape, param
count, and whether it contains a call or reads a global. Flipping `OptLevel < 3`
gates tells you which SLICE; it never tells you which ROUTINE, and that is where
an -O3 hunt stalls. The retained list showed 120 bodies, the `hasCall` ones were
all `__pxx_*` PAL shims, and the C program under test calls one with a string
literal — repro in minutes.

### The global-read hazard: MEASURED, and it does not exist

The suggested fix direction was implemented first (refuse a `skGlobal` read in a
call-bearing retained body) and it changed nothing — the probe showed no
retained body in this program reads a global at all. Then it was tested
directly, with the guard disabled:

```pascal
function Load: Integer; begin g := 7; Result := 1; end;
function F: Integer; begin Result := Load + g; end;   { F=8 at -O0/-O2/-O3 }
function H: Integer; begin Result := g + Load; end;   { H=1 at -O0/-O2/-O3 }
```

Both retained with `hasCall readsGlobal`, both identical at every -O level. The
reason is structural: **arguments are placeholders SUBSTITUTED at each use;
a body's own global read is cloned in place and lowered in the body's order**,
so nothing can move it across the body's inner call. The guard was removed
rather than kept as insurance — speculative refusal of inlining, justified by a
hazard that measurement says is not there. The `readsGlobal` flag survives as
probe output only, because it is the first thing anyone will suspect next time.

### Verified

- `test/c_inline_strlit_arg.c` (new, wired into `make test-opt`) — the literal
  and variable forms agree at -O0/-O2/-O3.
- `test/ctime_localtime.c` byte-identical output at -O0/-O2/-O3.
- self-host fixedpoint byte-identical; `gate.sh quick` GREEN; FPC seed build
  clean.

### Note on the adjacent segfault

Not investigated — direct runs at every -O level exit 0 here too, so the
ticket's own guess that it belongs to another program in the shard still stands.
`optdiff` shard 8/12 re-running against this SHA is the check.

## Log
- 2026-08-02 — resolved.
- 2026-08-02 — resolved, commit HEAD.

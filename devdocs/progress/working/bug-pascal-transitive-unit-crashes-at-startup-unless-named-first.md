---
summary: "Pascal: `uses blcksock;` segfaults before main() in the string-release helper — naming a transitively-used unit FIRST fixes it"
type: bug
track: A
prio: 60
---

# A unit reached only TRANSITIVELY crashes the program at startup

- **Type:** bug (compiler core — unit emission / initialization order — **Track A**)
- **Status:** working
- **Owner:** claude-A2
- **Opened:** 2026-07-31 by Track B, wiring the Synapse SSL end-to-end for
  [[feature-real-dynlib-loader]]. Filed, not fixed: this is `compiler/**`.

## Repro — three lines, no network, no SSL

```pascal
program t;
uses blcksock;
begin WriteLn('ok'); end.
```

```
$ pxx --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix t.pas t
ok: ...
$ ./t
Segmentation fault
```

`ok` is never printed — it dies before the main body runs.

## The fix that shouldn't be one

Naming a unit that `blcksock` already uses, BEFORE it, makes the crash go away:

| uses clause | result |
| --- | --- |
| `blcksock` | **segfault** |
| `blcksock, sysutils` | **segfault** |
| `sysutils, blcksock` | **segfault** |
| `classes, blcksock` | **segfault** |
| `synacode, blcksock` | **segfault** |
| `synsock, blcksock` | **segfault** |
| `synafpc, blcksock` | **segfault** |
| `synaip, blcksock` | **ok** |
| `synautil, blcksock` | **ok** (synautil is the one that drags in synaip) |
| `httpsend` | **segfault** |
| `smtpsend` | **segfault** |

So it is specifically **synaip** that has to be linked earlier, and mentioning
it in the program's own uses clause is the whole difference. `synaip` has NO
initialization section — a plain `end.` — so this is not an
initialization-ordering semantic; something about the ORDER units are emitted
in changes whether the program survives startup.

This also explains why `test/lib_synapse.pas` is green and has been all along:
it happens to write `uses synacode, synautil, blcksock, sysutils` — `synautil`
is in front, so it takes the working path by accident.

## Where it dies

```
Program received signal SIGSEGV
0x00000000004000bd in ?? ()
=> 0x4000bd:  decq   -0x10(%rax)      <- the managed-string RELEASE helper
   0x4000c1:  jne    0x4000e7
```

It is inside the refcount-decrement helper with a bad `%rax`, i.e. something is
releasing a managed string through a pointer that was never a string. The
apparent return address (`0x4946c8`) disassembles as data, so the frame is not a
real call chain — the helper is being entered with a stack that is not a caller's.

Note the failure is at STARTUP with an empty program body, so the offending
release is in unit init/finalization emission, not in user code.

## Why it matters beyond Synapse

`uses <one unit>` is the most ordinary line in Pascal. Whether a program starts
currently depends on whether its author happened to name a transitive dependency
first — which is not something a user can be expected to discover, and which
makes any green test using that library only accidentally green. It blocks the
Synapse SSL end-to-end (`httpsend` + `ssl_openssl3` crash the same way), which
is the last open item of [[feature-real-dynlib-loader]].

Requires `--mimic-fpc` only because Synapse needs it to compile at all; the flag
is not otherwise implicated.

## Related

[[bug-pascal-uses-is-transitive]] is about transitive VISIBILITY of names; this
is about a transitively-reached unit being emitted in an order that breaks
startup. They may share a cause — worth checking together.

## Gate

`make test` + self-host byte-identical, plus a regression that compiles
`program t; uses blcksock; begin WriteLn('ok') end.` and asserts it prints `ok`
— the three-line form above, with no unit named ahead of it.

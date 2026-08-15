---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`-g` on two classes that reference each other through a forward declaration (`TB = class;` … `TA` holds a `TB`, `TB` holds a `TA`) exhausts the stack and SIGSEGVs the COMPILER. Eleven lines, no library. Without `-g` the same source compiles fine. Blocks debugging any program touching Synapse's blcksock, where TTCPBlockSocket <-> TCustomSSL are exactly this shape."
status: done
owner: claude-AN
---

# `-g`: DWARF emission recurses forever on mutually-referencing classes

- **Type:** bug (compiler crash) — **Track A** (DWARF emission in
  `compiler/**`). Filed by Track B on 2026-08-15; not fixed here per the
  shared-internals rule.
- Found while trying to `-g` a Synapse client for
  [[feature-real-dynlib-loader]] item (d). The debugger is the tool that
  investigation needs, and it is the tool this bug takes away.

## Repro — 11 lines, no library, no flags but `-g`

```pascal
unit mutu;
interface
type
  TB = class;          { forward }
  TA = class
    b: TB;
  end;
  TB = class
    a: TA;
  end;
implementation
end.
```

```pascal
program mutuprog;
uses mutu;
var x: TA;
begin
  x := nil;
end.
```

```
$ pxx -g -Fu. mutuprog.pas /tmp/mutuprog
Segmentation fault (core dumped)
$ pxx    -Fu. mutuprog.pas /tmp/mutuprog     # same source, no -g
ok
```

The variable is never even used — declaring it is enough, because the type is
what gets described.

## It is stack exhaustion, not a null dereference

Under gdb the fault address is just past the stack guard and the backtrace
cannot be walked:

```
Program received signal SIGSEGV
Backtrace stopped: Cannot access memory at address 0x7fffff7fefb0
```

i.e. the type walker follows `TA -> TB -> TA -> …` with nothing memoising the
types it has already emitted, so a **cycle** — which is legal and common in
Pascal, and is what the `TB = class;` forward declaration exists to allow —
never terminates.

## Why it matters beyond the toy

`external/synapse/blcksock.pas` has exactly this shape:
`TCustomSSL = class;` forward at line 282, `TTCPBlockSocket` holding
`FSSL: TCustomSSL` at 969, `TCustomSSL` proper at 1237 holding its socket back.
So:

```
pxx -g ... anything with a TTCPBlockSocket variable   -> compiler SIGSEGV
```

`TBlockSocket` and `TSocksBlockSocket` compile fine under `-g`; `TTCPBlockSocket`
and `TUDPBlockSocket` (whose `FSocksControlSock` is a `TTCPBlockSocket`) do not.
That is the cycle, isolated by bisection over the hierarchy.

The practical cost is that **no Synapse program can be built with debug info**,
so the one investigation that most needs a debugger — the SSL handshake crash
in [[feature-real-dynlib-loader]] item (d) — has to be done without one.

## Expected

Emit the DWARF for a type once and refer to it by offset afterwards, which is
what a cyclic type graph requires and what every DWARF producer does. A visited
set keyed on the type id is the whole fix; the cycle itself is not an error and
must not be diagnosed as one.

## Sweep before closing

Records with mutually-referencing pointer fields, a class holding a pointer to
its own type, an interface pair, and a generic instantiated on a type that
refers back to it — the cycle is a property of the type GRAPH, not of classes.
Also check `-g -O2` and the other targets: DWARF emission is shared, so a fix
should cover all of them at once, but the crash should be confirmed gone on at
least one cross target.

## Gate

The 11-line repro compiles with `-g` and the emitted DWARF describes both types
(`readelf --debug-dump=info` shows `TA` and `TB` once each, mutually referring),
gdb can print a variable of each type, `make test` + self-host fixedpoint.

## Resolution (2026-08-15)

Root cause confirmed by reading, not by guessing at the backtrace: in
`DbgEnsureScalar` (`compiler/elfwriter.inc`) a class/record DIE was entered in
`DbgTypeRegister` only **after** its field types had been walked, so the walk of
`TA` reached `TB`, whose walk reached `TA`, whose lookup still missed. Nothing
memoised the in-progress type; the recursion had no floor.

Two cuts, at the two places a cycle can close:

1. **The class pointer (`tkOrd = 6`) — the real fix.** A class variable holds a
   pointer to the struct, so the pointer DIE is now emitted and registered
   FIRST, with its `DW_AT_type` ref4 left blank and patched (`DbgPatchU32`) once
   the body exists. The pointer is where a Pascal type cycle is legal, so it is
   where it is cut, and the emitted DWARF is the correct mutually-referring
   graph rather than a truncation.
2. **A struct body re-entered while it is still being emitted** — a shape no
   pointer breaks. Marked with an in-progress registry entry (cat 9500); the
   inner reference degrades to the named void* cheat instead of recursing. A
   DIE cannot nest inside itself, so this is the only honest answer.

Verified: the 11-line repro compiles, `readelf --debug-dump=info` shows `TA` and
`TB` once each with `TA.b -> ptr -> TB` and `TB.a -> ptr -> TA`, and gdb reads
`x.b.w` **through** the cycle. Sweep from the ticket all green — a record with a
pointer to itself, a class holding its own type, an interface pair, a class with
an array of a cyclic type, and `-g -O2`; cross `-g` builds pass on aarch64 /
i386 / arm32. The motivating case is fixed:

```
pxx --mimic-fpc -g -Fuexternal/synapse ... (a TTCPBlockSocket variable)   -> ok
```

Regression test added to `tools/dwarf_smoke.sh` (`make test-debug-g`): the
cyclic pair must compile under `-g`, each type must be described exactly once,
and gdb must read through the cycle.

Gate: `gate.sh quick` GREEN + self-host fixedpoint; `dwarf_smoke.sh` OK. No pin
(nothing under `compiler/builtin/**` changed).

## Log
- 2026-08-15 — resolved, commit dd193ae6f.

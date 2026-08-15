---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`-g` on two classes that reference each other through a forward declaration (`TB = class;` … `TA` holds a `TB`, `TB` holds a `TA`) exhausts the stack and SIGSEGVs the COMPILER. Eleven lines, no library. Without `-g` the same source compiles fine. Blocks debugging any program touching Synapse's blcksock, where TTCPBlockSocket <-> TCustomSSL are exactly this shape."
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

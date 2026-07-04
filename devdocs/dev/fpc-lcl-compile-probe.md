# FPC / LCL compile probe — where pxx walls today (2026-07-04)

A quick "throw real FPC 3.2.2 + Lazarus 3.0 LCL source at pxx and see where it
breaks" pass, as a coverage/progress indicator. **Not** an attempt to actually
compile them — a first-wall survey.

## Method

pxx needs a `program` (it rejects a bare `unit` at token 1) and resolves `uses`
by parsing the unit file, `.pas` then `.pp`, searching `-Fu` roots. So each unit
was probed as:

```
program p; uses <unit>; begin end.        # pxx [--mimic-fpc] -Fu<dir> probe.pas out
```

Two caveats that shaped the results:

- **pxx shadows** common unit names with its own RTL (it ships its own
  `classes`, `sysutils`, `math`, `graphics`, `controls`, `forms`, `gtk3`, …), so
  those names resolve to pxx's versions, not FPC's. Only units pxx does **not**
  have exercise real FPC source.
- **External FPC/LCL code must be compiled with `--mimic-fpc`.** That mode sets
  `FPC_FULLVERSION := 30202` (+ `FPC`, `UNIX`, `VER3_2_2`, …), which real FPC
  headers gate on (`{$if FPC_FULLVERSION >= 30203}`). Without it those directives
  hit "comparison requires integer operands" at the first `{$if}` (the version
  macro is undefined). This is **not a bug** — `--mimic-fpc` is exactly the "act
  like FPC for external code" switch. (It must NOT be used for the self-build:
  `FPC` defined → `{$ifdef FPC} uses SysUtils` → broken bootstrap.)

Sources: `/usr/share/fpcsrc/3.2.2`, `/usr/lib/lazarus/3.0/lcl`.

## Results (with `--mimic-fpc`)

| unit | source | first wall |
|------|--------|-----------|
| `rtlconsts` | FPC rtl/objpas | **compiles OK** (pure resourcestring/const unit) |
| `custapp` | FPC fcl-base | `:33 base type not found: TComponent` — **RTL surface** |
| `eventlog` | FPC fcl-base | `:31 base type not found: TComponent` — **RTL surface** |
| `contnrs` | FPC fcl-base | `:46 cannot override: no virtual method found in parent chain: Destroy` — **RTL surface** |
| `inifiles` | FPC fcl-base | `:46` same `Destroy` mismatch |
| `fgl` | FPC rtl/objpas | `:136 expected name` — generic class with nested `type`/`var` sections (see below) |
| `lcltype` | LCL | `:92 expected name` — advanced past all the version `{$if}`s; a deeper in-context parse desync |
| `lclproc` | LCL | reaches the same class of deeper wall once `--mimic-fpc` clears the directives |

## What is NOT the wall

Every core construct these units use parses **fine in isolation** under pxx:
default parameter values (incl. `= true`), a `generic … = class` with a
`T`-returning method, `procedure(…) of object` method-pointer type aliases,
plain procedural-type aliases, virtual/override, resourcestrings. So pxx's core
Pascal dialect is solid; the unit-level failures are NOT "pxx can't parse
Pascal."

## The real blockers (ranked)

1. **RTL API-surface mismatch — the dominant blocker, and `--mimic-fpc` does
   NOT fix it.** pxx's own `classes` is not FPC's: no `TComponent`, and
   `TObject.Destroy` has a different virtual shape. Any FCL/LCL unit built on
   `TComponent`/`TObject` fails at its class header (`custapp`, `eventlog`,
   `contnrs`, `inifiles`, and everything above them). `--mimic-fpc` only sets
   defines — it does not swap FPC's RTL in, and pxx's own `classes` shadows it
   anyway. Two routes: (a) grow pxx's `classes`/`sysutils` toward FPC's API
   (`TComponent`, streaming/`TPersistent`, the exact virtual `Destroy`), or
   (b) let pxx consume FPC's own RTL units (hard — they lean on compiler
   intrinsics pxx lacks). Route (a) is the tractable, highest-leverage step
   toward real-world FPC-source compatibility.

2. **Deep, cascade-sensitive parse gaps in complex units.** `fgl`'s
   `generic TFPGList<T> = class(TFPSList)` with `private type` (nested
   `TCompareFunc`/`PT = ^T`) + `{$ifndef OldSyntax}protected var{$else}…` and
   `lcltype` ~92 both give `expected name`, but the isolated features all parse —
   so these are specific *combinations* (nested type/var sections inside a
   generic class; something ~lcltype:92) that desync the parser. Each needs its
   own investigation; they are narrower than #1.

## Takeaway (the progress signal)

pxx is **not** blocked on core Pascal syntax for real FPC code. With
`--mimic-fpc` the preprocessor/version gating works and pure units
(`rtlconsts`) compile clean. The wall is the **RTL surface**: pxx reimplements
`classes` with a smaller API than FPC's (no `TComponent`, different `Destroy`),
so FCL/LCL units fail at their class headers. LCL is doubly a special case — pxx
ships its **own** LCL-like stack (`controls`/`graphics`/`forms`/`gtk3`), so
"compile Lazarus's LCL" conflicts with pxx's reimplementation rather than
extending it.

The single highest-leverage move toward compiling real FPC code is growing
pxx's `classes` toward the `TComponent`/`TPersistent`/virtual-`Destroy` surface.
Secondary: chase the cascade-sensitive parse desyncs in `fgl`/`lcltype`.

## Reproduce

```
# pure unit — OK
printf 'program p; uses rtlconsts; begin end.\n' > /tmp/p.pas
./compiler/pascal26 --mimic-fpc -Fu/usr/share/fpcsrc/3.2.2/rtl/objpas /tmp/p.pas /tmp/p

# RTL-surface wall
printf 'program p; uses custapp; begin end.\n' > /tmp/p.pas
./compiler/pascal26 --mimic-fpc -Fu/usr/share/fpcsrc/3.2.2/packages/fcl-base/src \
  -Fu/usr/share/fpcsrc/3.2.2/rtl/objpas /tmp/p.pas /tmp/p   # -> base type not found: TComponent
```

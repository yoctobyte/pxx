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

## The real blockers (ranked) — split by compiler vs library

Two of the three walls turn out to be **library**, not compiler, once you look:

1. **[COMPILER] ~~Built-in `TObject` has no virtual `Destroy`/`Create` to
   `override`.~~ FIXED 2026-07-04** ([[bug-tobject-destroy-not-virtual-override]]).
   `destructor Destroy; override;` / `constructor Create; override;` now compile
   on a root-derived class and dispatch/chain correctly; `inherited Destroy`/
   `Create` at the root boundary is a no-op. Re-probing `contnrs` advanced from
   this wall (`:46`) to `:79` — a **library** gap (pxx's `classes.TList` lacks a
   virtual `Notify`), Track B. So the FPC-compat *compiler* showstopper here is
   resolved; what remains at this layer is library surface.

2. **[LIBRARY] `TComponent` is in the wrong unit + a reduced surface — pxx
   already HAS it.** `TComponent` (with owner/child ownership) lives in
   `lib/rtl/classes_lite.pas`, and `TControl(TComponent)` in
   `lib/pcl/controls.pas` — so pxx is *not* missing the component model. But
   FPC's `uses Classes` resolves to pxx's `lib/rtl/classes.pas`, which
   deliberately excludes it ("the streaming runtime (TComponent, TReader) is in
   classes_lite"). So `custapp`/`eventlog` get `base type not found: TComponent`
   purely because it is not in the unit FPC expects. Also, `classes_lite`'s
   `TComponent` is a trimmed API (has `Owner`/`Name`/`AddChild`; lacks FPC's
   `Components[]`/`ComponentCount`/`InsertComponent`/`Tag`/`Notification`). Fix =
   **library**: put `TComponent`/`TPersistent` in `classes` (where FPC has them)
   and grow to the full surface. Track B, `lib/rtl/classes*.pas` — no compiler
   change.

3. **[COMPILER] `fgl` wall is NOT generics — it's two mundane dialect gaps.**
   Bisected 2026-07-04: every generic construct `fgl` uses parses fine in pxx
   (generic class, `<T>` fields, nested `type` incl. `PT = ^T` and fn-ptr-over-T,
   `protected var`, override-in-generic, generic-from-non-generic base). The
   `:136 expected name` was a parser **desync** from two earlier non-generic
   constructs; patching a local `fgl.pp` past them advanced it to `:29`
   (`uses types`, a unit dependency), with generics never the blocker. The two
   real gaps (both Track A, both pervasive in FPC RTL, both ticketed):
   - **hint directives** `deprecated`/`platform`/`experimental` on const/type/proc
     → `unexpected token` ([[feature-hint-directives-deprecated-platform]]).
     `fgl`'s `MaxGListSize = MaxInt div 1024 deprecated;` desyncs here.
   - **`SizeOf(...)` as a const/default-param value** → `not a constant`
     ([[feature-sizeof-const-intrinsic-in-const-eval]]). `fgl`'s
     `Create(AItemSize: Integer = sizeof(Pointer))`.

   A genuine generics gap does exist but is narrower — generic method *bodies in
   a program* ([[bug-generic-class-methods-in-program]]); generic bodies in a
   *unit* (the normal case, incl. `fgl`) work. `lcltype:92` is a separate
   cascade-sensitive desync — LCL-side, lower priority.

   **`fgl` is a deeper stack of small non-generic gaps, not two** (fuller bisect
   2026-07-04). Fixed so far: hint directives + `SizeOf` in const eval (both
   DONE). Still needed by `fgl`: **default parameter values on methods**
   ([[feature-default-params-on-methods]] — method param lists accept NO default,
   not just sizeof; `TFPSList.Create(AItemSize: Integer = sizeof(Pointer))`),
   and **overridable `MaxInt`/`MaxLongInt`** (`MaxGListSize = MaxInt div 1024`).
   LESSON on `MaxInt`: adding it as a hard compiler `AddConst` **broke** an
   existing test (`test_generic_func` does `specialize Max<Integer> as MaxInt` —
   the const shadowed the user identifier → miscompile → segfault). FPC's
   `MaxInt` is an *overridable* System-unit const; it must live in `lib/rtl`
   (Track B) or a soft-predefined mechanism a user decl can shadow, NOT a
   builtin `AddConst`. Reverted; not yet re-homed.

## Takeaway (the progress signal)

pxx is **not** blocked on core Pascal syntax for real FPC code — with
`--mimic-fpc`, version gating works and pure units (`rtlconsts`) compile clean.
For **FPC itself** (the interesting target, vs LCL), the compiler showstoppers
are narrow, and **generics is NOT among them for `fgl`** (bisected — see #3):

- **virtual `TObject.Destroy`/`Create` override** (blocker #1) — FIXED
  2026-07-04; and
- two mundane dialect gaps behind `fgl`'s apparent "generics" wall: **hint
  directives** and **`SizeOf` in const eval** (blocker #3, both ticketed). The
  only genuine generics gap is method bodies in a *program*
  ([[bug-generic-class-methods-in-program]]), not units.

Everything else observed was **library**: `TComponent` is already implemented,
just in `classes_lite` instead of `classes`, and at a reduced surface. LCL is a
special case regardless — pxx ships its own `controls`/`graphics`/`forms`/`gtk3`
stack, so "compile Lazarus's LCL" conflicts with pxx's reimplementation rather
than extending it; **compiling FPC's own RTL/FCL is the meaningful target.**

Highest-leverage move: fix virtual `TObject.Destroy` override (#1). Then advanced
generics (#3). The `TComponent`-in-`classes` move is independent library work.

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

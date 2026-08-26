---
track: P
prio: 55
type: bug
blocked-by: []
summary: "`inherited Create;` where the parent's constructor/method declares a defaulted parameter is rejected with `inherited call argument count mismatch`, while the identical *direct* call `TBase.Create` applies the default and compiles. Blocks `TFPGObjectList` in real FPC `fgl.pp` (Pascal corpus rung 2)."
status: backlog
owner: —
---

# `inherited` ignores the parent's default parameter values

- **Type:** bug (Pascal frontend — call lowering)
- **Track:** P — tag: compat
- **Found:** 2026-08-25, bringing up the fgl rung of the Pascal real-world
  corpus ladder ([[feature-pascal-corpus-fgl]]).

## Measured (pxx `stable_linux_amd64/default/pinned`, VERSION 374; oracle FPC 3.2.2)

```pascal
program t;
type
  TBase = class
    n: Integer;
    constructor Create(AN: Integer = 8);
  end;
  TDer = class(TBase)
    constructor Create(b: Boolean);
  end;
constructor TBase.Create(AN: Integer = 8); begin n := AN; end;
constructor TDer.Create(b: Boolean); begin inherited Create; end;   { <-- }
var d: TDer;
begin d := TDer.Create(True); writeln('n=', d.n); d.Free; end.
```

| form | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `b := TBase.Create;` (direct, default omitted) | `n=8` | **`n=8`** — works |
| `inherited Create;` from a descendant ctor | `n=8` | **`error: inherited call argument count mismatch`** |
| `inherited Foo;` — plain virtual method, same shape | runs | **same error** |

So the capability (apply a declared default when the argument is omitted) is
already implemented on the ordinary call path and is simply not reached from the
`inherited` path. This is the exact double-case shape
`devdocs/dev/normalise-dont-special-case.md` describes: **normalise the two call
paths onto one argument-filling step rather than teaching `inherited` about
defaults as a second mechanism.** Grep for the sibling before closing — the
`inherited` arity check appears to run before defaults are filled in, so
`inherited` with *any* omitted trailing default is affected, constructors and
methods alike.

## Why it matters (the real-world hit)

FPC's own `fgl.pp` — the RTL's generic-container unit, the flagship
`--mimic-fpc` compile target — cannot be used for `TFPGObjectList` because of
exactly this, at `rtl/objpas/fgl.pp:1061`:

```pascal
constructor TFPGObjectList.Create(FreeObjects: Boolean);
begin
  inherited Create;                 { TFPSList.Create(AItemSize: Integer = sizeof(Pointer)) }
  FFreeObjects := FreeObjects;
end;
```

`inherited Create` + a defaulted parent parameter is the single most common
constructor idiom in Object Pascal class libraries, so this one gap is worth
more than its size suggests.

## Repro / gate

`test/fgl/objectlist.pas` is the corpus driver, currently skip-listed against
this ticket in `test/fgl/pxx.skip`. Fixing this should let it run — remove the
skip line and `tools/run_fgl_corpus.sh` then enforces the pass against the
recorded FPC 3.2.2 oracle output.

Gate = `make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`.

## Links
Rung: [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]] · method note
[[devdocs/dev/normalise-dont-special-case.md]]

---
track: P
prio: 50
type: bug
blocked-by: []
summary: "`TObject(p^) := o` compiles, but `Pointer(p^) := q` is `error: undefined variable (Pointer)` — the cast-as-lvalue path resolves a class/user type name but not a builtin one, so in lvalue position `Pointer` is parsed as a variable. Blocks `TFPGInterfacedObjectList` in real FPC `fgl.pp`."
status: backlog
owner: —
---

# A cast-as-lvalue accepts a class type name but not a builtin type name

- **Type:** bug (Pascal frontend — lvalue typecast name resolution)
- **Track:** P — tag: compat
- **Found:** 2026-08-25, bringing up the fgl rung of the Pascal real-world
  corpus ladder ([[feature-pascal-corpus-fgl]]).

## Measured (pxx `stable_linux_amd64/default/pinned`, VERSION 374; oracle FPC 3.2.2)

| statement | FPC 3.2.2 | pxx |
| --- | --- | --- |
| `TObject(p^) := o;` | compiles, runs | compiles, runs |
| **`Pointer(p^) := q;`** | compiles, runs | **`error: undefined variable (Pointer)`** |
| `Integer(x) := 3;` (no deref) | compiles | `error: cast-as-lvalue statement requires a pointer deref inside the cast` — a *different*, deliberate diagnostic |
| `a := Pointer(b);` (same cast, rvalue) | compiles | compiles |

```pascal
program t;
var a, b: Pointer; p: Pointer; i: Integer;
begin
  i := 5; b := @i; a := nil; p := @a;
  Pointer(p^) := b;                { pxx: undefined variable (Pointer) }
  writeln(Assigned(a));
end.
```

## Root shape

pxx *has* a cast-as-lvalue feature — `TObject(p^) := o` works and there is a
dedicated diagnostic for the no-deref form, so the statement shape is
recognised. What fails is **name resolution in lvalue position**: a builtin type
name is looked up as a variable, not as a type, and the same name resolves
correctly one line up in rvalue position. One concept, two lookup paths, one of
them broken — `devdocs/dev/normalise-dont-special-case.md`. Grep for the
sibling: every builtin type name (`Integer`, `PtrUInt`, `Byte`, `Char`,
`Pointer`, `Boolean`) is likely affected in this position, not just `Pointer`.

## Why it matters (the real-world hit)

`rtl/objpas/fgl.pp:1189`, `TFPGInterfacedObjectList.CopyItem` — the refcounted
interface container's whole item-copy path:

```pascal
procedure TFPGInterfacedObjectList.CopyItem(Src, Dest: Pointer);
begin
  if Assigned(Pointer(Dest^)) then
    T(Dest^)._Release;
  Pointer(Dest^) := Pointer(Src^);      { <-- rejected }
  ...
```
Casting a pointer through an lvalue is standard practice in low-level container
and RTL code, so this is not an fgl quirk.

## Repro / gate

`test/fgl/ifclist.pas` is the corpus driver, currently skip-listed against this
ticket in `test/fgl/pxx.skip`. Remove the skip line when fixed and
`tools/run_fgl_corpus.sh` enforces the pass against the recorded FPC 3.2.2
oracle output.

Gate = `make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`.

## Links
Rung: [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]]

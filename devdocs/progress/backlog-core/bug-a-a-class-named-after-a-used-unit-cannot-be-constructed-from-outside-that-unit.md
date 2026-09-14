---
slug: bug-a-a-class-named-after-a-used-unit-cannot-be-constructed-from-outside-that-unit
title: "A class whose name equals a used unit's name: `C.Create(...)` from another unit is `undefined variable (Create)`"
track: A
prio: 45
type: bug
blocked-by: []
status: new
created: 2026-09-14
found: 2026-09-14
found-by: frankb-56, while building lib/rtl/pil.pas
owner: ""
summary: "MEASURED 2026-09-14, reduced to two 20-line units. A class declared in unit X whose NAME equals the name of a unit X uses cannot be constructed from any other unit: `Widget.Create(7)` answers `undefined variable (Create)`, because the unit qualifier wins over the locally-declared type. FPC resolves this the other way -- a type declared in the current unit shadows a used unit's NAME -- and the dialect is the target, so this is a real divergence rather than a style question. THE COLLISION IS NOT HYPOTHETICAL AND CANNOT ALWAYS BE DESIGNED AWAY: lib/rtl/pil.pas has to declare a class called `Image` because Python writes `from PIL import Image` and `Image.new(...)`, and it has to use lib/rtl/image.pas because that is where TImage lives. Both names are forced by something outside our control. IT IS LOUD FROM OUTSIDE AND THAT IS THE GOOD CASE -- a caller gets a refusal naming `Create`. Inside the declaring unit the same spelling compiles and does something else, which is filed separately and is the dangerous half; the two were originally diagnosed as one bug and are not (see bug-a-a-class-var-declared-before-an-instance-field-corrupts-the-instance-layout, which turned out to be the actual cause of the misbehaviour inside the unit). WORKAROUND IN USE: declare the class under an internal name and expose the Python-facing name as a type alias (`TPILImage = class ... end; Image = TPILImage;`), which works and through which NilPy still resolves the class correctly. Registered in devdocs/dev/track-b-workarounds.md. PRIO 45 rather than higher because it refuses instead of miscompiling, the workaround is one line, and the collision needs a deliberate name clash to hit."
---

# A class named after a used unit is unreachable from outside

## Repro

```pascal
unit widget;
{$MODE PXX}
interface
type TThing = record v: Integer; end;
implementation
end.
```

```pascal
unit collide;
{$MODE PXX}
interface
uses widget;          { a UNIT called widget ... }
type
  Widget = class      { ... and a CLASS called Widget. PXX is case-insensitive. }
  public
    n: Integer;
    constructor Create(v: Integer);
  end;
implementation
constructor Widget.Create(v: Integer);
begin n := v; end;
end.
```

```pascal
program r;
{$MODE PXX}
uses collide;
var a: Widget;
begin
  a := Widget.Create(7);
end.
```

    pascal26:6: error: undefined variable (Create)
      near: begin a := Widget . Create >>> ( 7 )

Remove `uses widget` from `collide.pas` and the identical program compiles and
runs correctly. That is the whole discrimination: the class is fine, the class
name is fine, and the collision with a used unit's name is what breaks it.

## Why it matters beyond tidiness

Python module names and our unit names are two namespaces we do not control the
intersection of. `lib/rtl/pil.pas` must expose `Image` (Pillow's own spelling)
and must use `image` (ours). `zlib`, `json`, `math`, `random`, `re` and `io` are
all both Python module names and plausible unit names; any of them growing a
same-named class hits this.

## The workaround, and why it is acceptable here

```pascal
type
  TPILImage = class ... end;
  Image = TPILImage;      { the name callers write }
```

Verified: construction works, and NilPy still reaches the class through the
alias (`m.Widget(7)` binds, methods dispatch, fields read back). It costs one
line and a comment. Registered in `devdocs/dev/track-b-workarounds.md` so it is
deleted when this is fixed rather than becoming folklore.

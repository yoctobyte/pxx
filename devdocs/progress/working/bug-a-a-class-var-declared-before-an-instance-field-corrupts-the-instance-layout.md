---
slug: bug-a-a-class-var-declared-before-an-instance-field-corrupts-the-instance-layout
title: "A `class var` declared before an instance field is counted into the INSTANCE layout, so two objects overlap"
track: A
prio: 80
type: bug
blocked-by: []
status: working
created: 2026-09-14
found: 2026-09-14
found-by: frankb-56, while building lib/rtl/pil.pas
owner: frankD
summary: "SILENT MEMORY CORRUPTION WITH A ONE-LINE TRIGGER. A `class var` declared BEFORE an instance field in the same class is counted into the INSTANCE layout, so every instance field after it lands at the wrong offset and two live instances OVERLAP -- constructing a second object reinitialises the FIRST one's fields through the alias. No diagnostic, and the first crash is somewhere else entirely. MEASURED AND REDUCED TO FOUR ROWS 2026-09-14, with a 20-line unit and no library involved: `class var` FIRST is wrong, `class var` LAST (after the instance fields) is right, and NO class var is right -- so the trigger is the DECLARATION ORDER and not the class var itself. The type does not matter (Integer reproduces it, so pylib is not involved) and one class var is enough. THE SHAPE THAT FOUND IT: a class holding a record with a dynamic array, whose instance method constructs a second instance -- `im.resize(...)` in lib/rtl/pil.pas printed Self.bmp=64x64 before `TPILImage.Create(0, 0, ...)` and Self.bmp=0x0 AFTER it, with Result.bmp also 0x0, then segfaulted reading the source it had just emptied. Two Image objects 216 bytes apart shared a field. WHY THIS IS RANKED AT 80 RATHER THAN AS A CURIOSITY: it needs no unusual code, it produces a wrong ANSWER rather than a refusal, and the corruption happens at a distance -- the damaged object is the one you are NOT looking at. Three reductions that do NOT reproduce it are recorded below, because they are what a fixer will try first: a dynamic array of Integers, a dynamic array of records, and a string field beside the record all behave correctly on their own."
---

# A `class var` before an instance field corrupts the instance layout

## The repro, whole

```pascal
unit u;
{$MODE PXX}
interface
type
  TElem = record R, G, B, A: Byte; end;
  TRec  = record W, H: Integer; Data: array of TElem; end;
  TBox = class
  public
    class var LIMIT: Integer;     { <-- move this below `r` and the bug goes }
    r: TRec;
    constructor Create(w, h: Integer);
    function shrink: TBox;
  end;
implementation
constructor TBox.Create(w, h: Integer);
begin r.W := w; r.H := h; SetLength(r.Data, w * h); end;
function TBox.shrink: TBox;
begin Result := TBox.Create(0, 0); end;
end.
```

```pascal
program r;
{$MODE PXX}
uses u;
var a, b: TBox;
begin
  a := TBox.Create(64, 64);
  b := a.shrink;
  WriteLn('a = ', a.r.W, 'x', a.r.H, '  (want 64x64)');
end.
```

    a = 0x0  (want 64x64)

## The four rows that locate it

Same unit, same program, only the class body changed:

| class body | result |
| --- | --- |
| `class var LIMIT: Integer;` then `r: TRec;` | **`a = 0x0`** — wrong |
| `r: TRec;` then `class var LIMIT: Integer;` | `a = 64x64` — correct |
| two class vars, both before `r` | **`a = 0x0`** — wrong |
| no class var at all | `a = 64x64` — correct |

So it is the **order**, not the presence. A `class var` is storage that belongs
to the CLASS and must not occupy an offset in the instance; it is evidently
being allocated one, and the instance fields after it are displaced by exactly
that much.

## Three reductions that do NOT reproduce it

Worth having, because they are the first things to try and each cost a cycle:

- a record holding `array of Integer` (not of records) as a class field, two
  instances constructed at program level — correct;
- the same with `array of TElem` — correct;
- an `AnsiString` field beside the record, no class var — correct.

The dynamic array is not the trigger. It is what makes the damage VISIBLE and
fatal: `SetLength(..., 0)` on the aliased field frees the first object's buffer,
so the next read is of freed memory rather than of a stale but mapped value.

## How it presented, before it was reduced

`lib/rtl/pil.pas` (`from PIL import Image`). `Image.resize` constructs its
result and then resamples into it:

    DBG resize self=...677952 bmp=64x64
    DBG ctor   self=...678168 want 0x0   bmp now 64x64     <- the NEW object already sees the OLD one's record
    DBG ctor   done self=...678168 bmp=0x0
    DBG resize after: self=...677952 bmp=0x0                <- the OLD object has been emptied

The constructor is correct, the call site is correct, and the receiver is
destroyed anyway. Two earlier hypotheses — that the class-qualified constructor
call was degrading to a `Self` call, and that a record-with-dynamic-array class
field was aliasing in general — both fit the evidence and are both wrong; the
four-row table above is what separated them.

## Note for whoever fixes it

There is a SECOND, unrelated and much more benign ordering rule in the same
area, found while reducing this one: a `const` section inside a class does not
end at a plain field declaration, so `const X = 5;` followed by `f: TSomething;`
is refused with *"expected '=' before ';'"*. That one is loud and is only
mentioned so it is not mistaken for this.

`lib/rtl/pil.pas` currently orders its declarations around this bug and says so
at the declaration; it is registered in `devdocs/dev/track-b-workarounds.md`.

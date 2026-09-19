---
slug: bug-a-a-class-var-declared-before-an-instance-field-corrupts-the-instance-layout
title: "A `class var` declared before an instance field is counted into the INSTANCE layout, so two objects overlap -- WRONG, it is absorbed into the class var SECTION"
track: A
prio: 80
type: bug
blocked-by: []
status: rejected
resolved: PENDING-COMMIT
created: 2026-09-14
found: 2026-09-14
found-by: frankb-56, while building lib/rtl/pil.pas
owner: frankD
summary: "REJECTED, FALSE PREMISE -- and the tree was contorted around it for five days, so the retraction is worth more than the ticket. A `const` or `class var` in a class body opens a SECTION, and a plain field declaration after one is ABSORBED into that section rather than ending it; `var` is what closes it and returns to per-instance storage. Nothing is counted into the instance layout and no field is displaced: `PXXDBG=a.reclayout` shows the class with NO instance fields at all, one lower on both `with-fields` and `fields`, because the field became a CLASS var. That is why two objects appear to overlap -- they read one shared global -- and `TBox.r` with no instance ever constructed compiles and answers, which is the discriminator that separates absorption from a wrong offset. ORACLE, measured 2026-09-19: fpc 3.2.2 on this box prints `a = 0x0` from the ticket's EXACT repro, identical to pxx and equally silent, and refuses the const-section half with the same message pxx gives. The four-row table in the body is correct DATA and was read as the wrong MECHANISM; the symptom genuinely looks like aliasing, which is how it survived reduction. FIXED IN THE TREE, not in the compiler: lib/rtl/pil.pas now uses the natural order with `var` (PIL differential 32 rows byte-identical to Pillow 12.1.1, and it REDDENS on row 1 without the `var` -- positive control run), its workaround row is gone from track-b-workarounds.md, and test_a_class_var_section_absorbs_a_plain_field_until_var_closes_it.pas pins the rule as parity -- the same file under fpc 3.2.2 prints the same four rows. The pin takes the `var` spelling too, which lib/rtl needs. NO WARNING IS PROPOSED: a plain declaration after a class var is the legitimate spelling of a multi-entry section, so a diagnostic would fire on correct code, and that is why the language has `var` instead."
---

# A `class var` before an instance field corrupts the instance layout — WRONG

## The retraction, and it is the only part worth reading

`const` and `class var` in a class body open a **section**. A plain field
declaration after one does not end it — it is **absorbed into it**. `var` is the
keyword that closes the section and goes back to per-instance storage:

```pascal
TBox = class
  class var LIMIT: Integer;
  r: TRec;        { <- a CLASS var. One `r` for the whole class. }
end;

TBox = class
  class var LIMIT: Integer;
  var
    r: TRec;      { <- an instance field, which is what was meant }
end;
```

**Nothing is displaced and no offset is wrong.** `PXXDBG=a.reclayout` on the
failing source prints no `TBox` line at all — `with-fields=13 fields=72` against
`with-fields=14 fields=73` for the working order, one aggregate and one field
fewer. The field never becomes an instance field, so every object reads one
shared global; that is the whole of the "two instances overlap" symptom.

**The discriminator that separates absorption from a wrong offset** — and it is
one line, so it was cheap to have had first: name the field through the CLASS,
with no instance ever constructed.

```pascal
TBox.r.W := 7;  TBox.r.H := 9;  WriteLn(TBox.r.W, 'x', TBox.r.H);   { prints 7x9 }
```

A field at a wrong instance offset cannot answer that. A field in the ClassVar
registry answers it exactly.

### The oracle

fpc 3.2.2 on this box, **the repro from this ticket, unmodified** except for the
mode line:

| | class var then `r: TRec;` | class var then `var r: TRec;` |
| --- | --- | --- |
| pxx (HEAD) | `a = 0x0` | `a = 64x64` |
| pxx (pin) | — | `a = 64x64` |
| **fpc 3.2.2** | **`a = 0x0`** | `a = 64x64` |

No warning from either compiler. The const-section half is refused by fpc with
`Syntax error, "=" expected but ";" found` — pxx says `expected '=' before ';'`,
the same refusal. **Both halves of this ticket are parity with the reference
compiler**, which is why this is rejected rather than fixed.

### Why it survived reduction

The four-row table below is correct data. It was read as the wrong mechanism,
and the reading is a reasonable one: a shared field and a displaced field
produce the same alarming symptom — a second construction emptying the first
object — and the dynamic array turns both into a segfault. What separates them
is not visible from the program's output at all. The reduction was sound work;
only the sentence explaining it was wrong.

### What changed in the tree

- `lib/rtl/pil.pas` declared its instance fields first for this reason and said
  so in a comment. It now uses the natural order with `var`. Re-verified **by
  behaviour**: the PIL differential is 32 rows byte-identical to Pillow 12.1.1
  with the `var`, and reddens on its first row without it (control run, not
  assumed).
- The `lib/rtl/pil.pas` (class declaration order) row is gone from
  `devdocs/dev/track-b-workarounds.md`. **A workaround can outlive its bug by
  being wrong about what the bug was.**
- `test/test_a_class_var_section_absorbs_a_plain_field_until_var_closes_it.pas`
  pins the rule as parity. It is `{$mode objfpc}` and prints the same four rows
  under fpc 3.2.2, so the parity claim is re-checkable with a diff rather than
  believed.

### Not proposed: a warning

`class var A: Integer; B: Integer;` is the legitimate spelling of a two-entry
class var section. Nothing distinguishes it from a mistyped instance field, so a
diagnostic would fire on correct code. That is why the language has `var` rather
than a warning, and it is the argument against adding one here.

---

## The original report follows, unedited

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

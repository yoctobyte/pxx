# Assigning a managed string (tyAnsiString) into a frozen `string` (tyString) miscompiles → segfault

- **Type:** bug (compiler / codegen)
- **Status:** backlog
- **Owner:** Track A
- **Opened:** 2026-06-20
- **Relation:** the concrete crash the string-model overhaul is meant to end —
  [[feature-string-model-tyfixedstring]]. Surfaced from PCL `TListBox`/`TComboBox`
  item access under `-dPXX_MANAGED_STRING`; worked around in the library only.

## Problem

Under `PXX_MANAGED_STRING` mode the two `string`-ish kinds disagree on layout but
the compiler will silently assign one to the other and emit wrong code:

- `array of string` elements resolve to the **managed** type `tyAnsiString`
  (8-byte handle / pointer to a refcounted, length-prefixed heap buffer).
- A scalar `string` local or function-return resolves to the **frozen** inline
  type `tyString` (inline length word at offset 0, chars at +8).

When the source is `tyAnsiString` and the destination is `tyString` — e.g.

```pascal
function TListBox.Item(AIndex: Integer): string;   { return = frozen tyString }
begin
  Result := FItems[AIndex];   { FItems: array of string -> element = managed tyAnsiString }
end;
```

the codegen lowers the assignment as a **frozen→frozen inline copy**: it reads a
"length" from offset 0 of the *managed handle* (which is actually the first 8
characters of the heap string), then `rep movsb` of that bogus, often huge,
length. Result: segfault (exit code 139).

## Root cause

The frozen-string store path assumes the source is also a frozen inline string.
A `tyAnsiString` source is a pointer to the managed buffer, not an inline struct,
so reading its "length" at +0 and doing an inline byte copy is invalid. The
assignment should either:

1. be **rejected at compile time** (kind mismatch), or
2. be **coerced** — materialise the managed string's chars into the frozen
   destination's inline buffer (the dual of the frozen→managed assign that
   already works, e.g. `Str`'s frozen result into an `AnsiString`).

Today it does neither; it blindly reuses the inline-copy lowering.

## Reproduction (shape)

```pascal
{$define PXX_MANAGED_STRING}
program repro;
var a: array of string; s: string;
begin
  SetLength(a, 1);
  a[0] := 'hello world this is long enough to matter';
  s := a[0];          { managed tyAnsiString -> frozen tyString : miscompiles }
  writeln(s);
end.
```

Build with the managed-mode flag the PCL GUI suite uses. Expect a segfault /
garbage length rather than `hello world...`.

## Workaround (already applied, library side)

`lib/pcl/stdctrls.pas` was changed so `TListBox`/`TComboBox` item + text
read/write methods, locals, and properties use `AnsiString` explicitly (e.g.
`property Text: AnsiString`), keeping both sides `tyAnsiString` so no cross-kind
assign happens. GUI suite green under default and managed modes. This masks the
symptom; the compiler bug remains.

## Fix direction

Part of the string-model arc. Two viable end states:

- **Short term / safety:** emit a hard error on `tyAnsiString -> tyString`
  (and `tyAnsiString -> tyFixedString`/`tyShortString`) assignment, so the
  silent miscompile becomes a diagnostic. Cheap, stops the footgun.
- **Right answer:** the planned managed-default flip (slice 4p2 of
  [[feature-string-model-tyfixedstring]]) makes scalar `string` resolve to
  `tyAnsiString` too, so `array of string` and `s: string` agree and the
  cross-kind assign disappears for normal code. For the genuinely-mixed cases
  (frozen `string[N]` dest from a managed source) add a real coercion in the
  store path — materialise managed chars into the inline buffer, the dual of the
  existing frozen→managed direction.

## Acceptance

- The repro above prints the string (or errors at compile time), never segfaults.
- A regression test covers managed→frozen and frozen→managed both ways.
- PCL `stdctrls.pas` can drop the explicit-`AnsiString` workaround once scalar
  `string` is managed by default (track the revert with the 4p2 flip).

## Log
- 2026-06-20 — Filed (Track A) from the GTK/PCL agent's TListBox crash
  investigation. Library symptom already worked around in `stdctrls.pas`
  (commit 6355d7d); the underlying `tyAnsiString -> tyString` codegen bug was
  left unfiled — this ticket records it. Tied to the managed-default flip
  (4p2 HELD) and the cross-kind-assign coercion in the string-model arc.

## RESOLVED 2026-06-20 (string-model slice 4p2, commits ca85010/1786e36, pinned v26)

The managed-default flip makes scalar `string` resolve to `tyAnsiString`, so
`array of string` and `s: string` agree and the silent cross-kind assign is
gone for normal code. For the genuinely-mixed case a real coercion was added:
managed source -> frozen `string[N]` store materialises the handle's chars into
the inline buffer (ir_codegen.inc IR_STORE_SYM frozen path), and the dual
frozen->managed (incl. via pointer deref `m := p^`) materialises a managed
handle. Regression test/test_managed_string_flip.pas covers both directions +
the original repro; wired into `make test`. PCL stdctrls.pas can now drop the
explicit-AnsiString workaround (6355d7d) — handed to Track B with the v26 re-pin.

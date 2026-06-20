# bug-subclass-field-offset-calculation (Track A)

- **Type:** bug
- **Status:** DONE 2026-06-20
- **Owner:** —
- **Opened:** 2026-06-20

## Description

The compiler miscalculates the field offset of subclass fields under class casting or type resolving when the subclass inherits from a base class with fields (like `TControl` inheriting from `TComponent`). 

Specifically, in `lib/pcl/gtk3widgets.pas`, when querying the `Handle` field of `TControl` via:
```pascal
h := TControl(AControl).Handle;
```
where `AControl` is typed as `TComponent`, the returned value is incorrect (e.g. `4273562` instead of the actual `166408768` written to the `FHandle` field during `TForm.CreateHandle`).

It appears the compiler resolves the field offset of `FHandle` relative to `0` instead of relative to `sizeof(TComponent)` when compiling the subclass access, or the class-to-class typecasting miscalculates the base offset.

## Reproduction / Evidence

In `test/gui/test_pcl_window.pas`, compiling and running prints:
```
TGtk3WidgetSet.CreateForm: win=166408768
TForm.CreateHandle: Handle=166408768
created form
TGtk3WidgetSet.SetText: AControl=139436287328344
TGtk3WidgetSet.SetText: h=4273562
```

## Done Criteria

`TControl(AControl).Handle` retrieves the correct `FHandle` value, and all GUI tests using widgetset handle access run without GTK assertion failures.

## Log
- 2026-06-20 — Opened during Track B GUI abstraction implementation.

## DONE 2026-06-20 (commit f9e0069)

Root cause: a class typecast as an EXPRESSION (`TClass(expr)`) had no handler —
it fell through to the pointer-type-alias cast path, whose `AN_PTR_CAST` node
`ResolveNodeRec` cannot map to a class record, so every trailing `.field`
resolved at offset ~0 (reading the VMT pointer). Affected ALL class casts, not
just inherited fields (even `TBase(d).a` on the first field broke).

Fix: new `AN_CLASS_CAST` AST node (hard reinterpret, no runtime check unlike
`as`). The instance pointer passes through unchanged; `ResolveNodeRec` maps it to
`REC_UCLASS_BASE+ci`, so `.field`/`[i]` resolve offsets against `TClass` (incl.
inherited base size). Wired into the expression parser (reads) and the statement
lvalue parser (writes), reusing `ParseClassRecordSelectors`. Files: defs.inc,
symtab.inc (ResolveNodeRec), ir.inc (passthrough lowering), parser.inc (both
parse sites). Validated x86-64 + i386; `test/test_class_cast_field.pas` in
test-core; self-host byte-identical.

Known remaining gap (separate, low pri): a METHOD call on a hard cast —
`TClass(x).Method(args)` — isn't handled by the field/index selector walker
(`as` covers checked method dispatch). File a follow-up if needed.

# bug-subclass-field-offset-calculation (Track A)

- **Type:** bug
- **Status:** backlog
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

# bug: a method miscompiles (segfault) depending on surrounding class context

- **Type:** bug
- **Status:** urgent
- **Track:** A
- **Opened:** 2026-06-24
- **Blocks:** hide-based `TPaned.Collapse` (feature-eliah-perspectives full collapse)

## Summary

Two methods with **byte-identical bodies**, same signature, same caller —
one segfaults at runtime, the other works. The miscompile is tied to the method
within its class context (name / declaration position / neighbouring methods),
not to the source of the body. Found building a hide-based `TPaned.Collapse`.

## Evidence (lib/pcl/extctrls.pas, TPaned)

A debug method `DbgHide(a, b: Integer)` and the real `Collapse(APane, AStrip:
Integer)` were given the **same body**:

```pascal
if Self.Handle = nil then Exit;
if FCollapsedPane = 0 then FRestorePos := gtk_paned_get_position(Self.Handle);
child := gtk_paned_get_child1(Self.Handle);
if a = 2 then child := gtk_paned_get_child2(Self.Handle);
if child <> nil then gtk_widget_hide(child);
FCollapsedPane := a;
```

Calling `HP.DbgHide(1, 0)` → prints each step, completes cleanly.
Calling `HP.Collapse(1, 0)` → **segfaults** inside the method (the first gtk
access after entry crashes — `Self`/args appear corrupt). Swapping the call in the
test from `Collapse` to `DbgHide` (nothing else changed) makes the crash vanish.

Each individual op works in isolation: `gtk_paned_get_child1` + `gtk_widget_hide`
on a paned child run fine from `main` AND from a *different* method (`DbgHide`).
A minimal standalone class with a method named `Collapse` does **not** reproduce —
the trigger needs the full TPaned class context (many methods, gtk FFI, fields).

Smells like the same family as `urgent/bug-widgetset-virtual-arg-corruption`
(method receives a corrupt `Self`/argument in a specific class layout) but here
the method is **non-virtual**.

## Related second defect (same session)

A specific statement nesting **hangs the compiler** (infinite loop, never
terminates) — see `bug-compiler-hang-on-nested-if-in-begin`. Hit while iterating
on the same `Restore`/`Collapse` code. Likely adjacent in the codegen path.

## Impact

`TPaned.Collapse` cannot use the robust `gtk_widget_hide` full-collapse. The
shipped `Collapse` falls back to a position-only collapse (move the handle to an
edge), which works for Eliah's Code/Design perspectives but cannot hide a pane
whose sibling resists shrinking. Eliah is GREEN on this fallback; full hide-based
collapse waits on this fix.

## Acceptance

`HP.Collapse(1, 0)` (hide a pane's child) behaves identically to the same body
under any other method name; a minimal-ish repro is isolated; self-host holds.

## Log
- 2026-06-24 — filed from Track B (TPaned hide-collapse / Eliah perspectives).
  Worked around with position-only collapse; grep `bug-method-miscompiled-by-context`.

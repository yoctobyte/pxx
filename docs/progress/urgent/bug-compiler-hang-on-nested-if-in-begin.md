# bug: compiler hangs (infinite loop) on a method with a nested if/else inside a begin block

- **Type:** bug
- **Status:** urgent
- **Track:** A
- **Opened:** 2026-06-24

## Summary

Compiling a particular method body sends the compiler into a **non-terminating
loop** — `pinned` pegs a CPU at ~90% indefinitely (observed 8+ minutes, killed).
No diagnostic, no progress. Hit while editing `TPaned.Restore` in
`lib/pcl/extctrls.pas`.

## The shape that hung

```pascal
procedure TPaned.Restore;
var child: Pointer;
begin
  if FCollapsedPane = 0 then Exit;
  if Self.Handle <> nil then
  begin
    if FCollapsedPane = 1 then child := gtk_paned_get_child1(Self.Handle)
    else child := gtk_paned_get_child2(Self.Handle);
    if child <> nil then gtk_widget_show(child);
  end;
  SetPosition(FRestorePos);
  FCollapsedPane := 0;
end;
```

Rewriting the same logic *without* the `if … then begin if/else …; if …; end`
nesting (flat statements, or a helper call) compiled in <1s. So the trigger is the
**nested if/else followed by another if, all inside an `if … then begin … end`**.

Like the companion `bug-method-miscompiled-by-context`, a tiny standalone class
did not reproduce — the loop needs the full `TPaned` class context (the method
sits among many others that call gtk FFI). The hang is 100% reproducible on the
extctrls TPaned at that edit (see this session's history).

## Severity

A compiler that hangs (vs. errors) on valid source is worse than a miscompile: it
wedges builds with no signal and spawns runaway processes. Even if the exact
trigger is narrow, the codegen/parse loop that can fail to terminate should be
found and bounded.

## Acceptance

The repro shape compiles (terminates) in bounded time; ideally a watchdog / pass
iteration bound exists so no input can wedge the compiler indefinitely. Self-host
holds.

## Log
- 2026-06-24 — filed from Track B. Avoided by flattening the statement nesting;
  related to `bug-method-miscompiled-by-context` (adjacent codegen path).

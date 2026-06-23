# feature: define Eliah's own layout in a streamed .lfm (dogfooding)

- **Type:** feature (app + RTTI streaming hardening)
- **Status:** backlog (partially landed — 3 of 4 streaming blockers fixed)
- **Track:** B
- **Parent:** feature-eliah-ide
- **Opened:** 2026-06-23

## Goal

Eliah builds its window imperatively while the project ships a working .lfm
streaming loader. Define Eliah's static layout (toolbar buttons, tree, editor,
output, error list, designer paint-box, inspector, value edit — bounds + event
bindings) in `apps/ide/eliah/eliah.lfm` and stream it via `InitInheritedComponent`
(`THandler` becomes a `TEliahForm(TForm)` with published handlers; `FindChild`
binds typed fields). Keep behaviour (menu, palette, designer paint, undo, reflow)
in code. One-time work, beneficial forever.

`apps/ide/eliah/eliah.lfm` is committed as the starting artifact (the form +
16 child widgets with bounds + event names).

## Streaming bugs surfaced (and the 3 already fixed)

The loader had only ever been exercised with a single TButton (Caption + OnClick).
A real multi-widget form exposed:

1. **Method-backed properties never applied** — `SetOrdProp`/`SetStrProp` only
   wrote direct-field props (`SetKind=0`); Caption/Left/Top/Width/Height use
   setter methods (`SetKind=1`) and were silently skipped. FIXED (typinfo invokes
   the setter). `test_pcl_lfm` now asserts the streamed captions.
2. **CreateInstance didn't zero the instance** — reused heap left `FHandle`
   garbage; a pre-Realize `FHandle<>nil` check dereferenced junk. FIXED.
3. **Widgets relying on constructor-allocated arrays** — `TListBox`/`TComboBox`
   SetLength `FItems`/`FRows` in their constructor, which streaming
   (CreateInstance) skips, leaving them nil → `FItems[0]` crash. FIXED (AddItem
   grows on demand; also drops the 256 cap).

## Remaining blocker (4th)

A streamed `TEliahForm` passes `--smoke` (which Realizes once, no `gtk_main`) but
**segfaults inside `Application.Run`** — before the first paint fires (the
`OnDesignPaint` marker never prints), so the crash is in the second Realize /
ConnectAppQuit / `ShowWidget` (`gtk_widget_show_all`) path for a streamed form.
No streamed form had previously been `show_all`'d + `gtk_main`'d (test_pcl_lfm
clicks synchronously without a main loop), so this is untested territory.

Repro: the `eliah.lfm` + the `TEliahForm` conversion (reverted from
`apps/ide/eliah/main.pas` to keep the app working) — or minimally, stream any
form with a child widget and call `Application.Run`.

## Next steps

1. Find the `Application.Run` crash for streamed forms (likely a streamed child's
   Realize/parenting: streamed children may not have `FParent` set the way
   `widget.Parent := form` sets it, so the Realize/show path differs). Add a
   minimal `stream + Application.Run` gate to lock it once fixed.
2. Re-apply the `TEliahForm` conversion (the reverted main.pas rewrite) and
   verify with an ffmpeg screenshot that the streamed layout renders + is
   interactive.

## Note

The 3 fixed streaming bugs benefit ALL RTTI streaming (and fixed the silently-
empty captions in `test_pcl_lfm`), independent of Eliah.

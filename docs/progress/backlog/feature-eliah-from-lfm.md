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

## 4th blocker — FIXED 2026-06-23

A streamed `TPaintBox` had `Canvas = nil` (TPaintBox.Create makes FCanvas, which
CreateInstance skips). `ControlDrawTramp` does `paintBox.Canvas.Handle := cr` on
every expose → nil deref → segfault (an adjacent event-wired widget just shifted
layout timing enough to trigger the draw). Fixed: TPaintBox.CreateHandle creates
FCanvas if nil. Root-caused as **Track B / lib**, NOT resource inclusion (props
streamed fine) and NOT the compiler (`GetMethodAddr` returns correct addresses).

## Constructor-skip audit (2026-06-23)

All four blockers were the same theme: the streamer (`CreateInstance`) does NOT
run constructors, and the loader had only ever been tested with a single TButton.
Audited every PCL constructor:

- Crash-risk (allocate sub-objects/arrays in the constructor): **TPaintBox**
  (Canvas), **TListBox**/**TComboBox** (FItems/FRows). ALL FIXED.
- Safe (only `HandleNeeded`; zeroing covers their fields): TButton, TLabel,
  TEdit, TCheckBox, TMemo, TPanel, TGLArea, TForm.
- Non-widget / unlikely-in-lfm, would get default-zero fields if streamed but NOT
  crash: TTimer (FInterval/FEnabled/UpdateTimer), TMenu (FRootMenuItem).

The contract is now documented at `lib/rtl/typinfo.pas:CreateInstance`.

## Remaining work

All streaming blockers are fixed. Only the re-application of the conversion is
left: re-create the `TEliahForm` main.pas (the version that already passed
`--smoke`; it only died on the now-fixed Canvas crash) and verify with an ffmpeg
screenshot that the streamed layout renders + is interactive. `eliah.lfm` is
committed and ready.

## Note

The 4 streaming fixes benefit ALL RTTI streaming (and fixed the silently-empty
captions in `test_pcl_lfm`), independent of Eliah.

# bug: RTTI .lfm streaming skips constructors → widgets with constructor state broke

- **Type:** bug (Track B — lib/rtl streaming + lib/pcl widgets)
- **Status:** done
- **Found:** 2026-06-23, moving the Eliah IDE layout into a streamed .lfm
- **Closed:** 2026-06-23
- **Severity:** high — silent data loss (empty captions/zero bounds) and hard
  segfaults; affected ALL RTTI-streamed UI, not just Eliah.

## Summary

The `.lfm` streaming path (`InitInheritedComponent` → `TReader.ReadRootComponent`
→ `CreateInstance` + property application) had only ever been exercised with a
single `TButton` (Caption + OnClick — `test_pcl_lfm`). A real multi-widget form
exposed four distinct defects, all rooted in the same theme: **`CreateInstance`
allocates an instance from RTTI but does NOT run its constructor**, and several
code paths assumed constructor-run setup.

Not the compiler. Not resource inclusion (`{$R}` embeds + `FindResource` reads
the resource fine; properties that did stream proved the bytes were intact).
`GetMethodAddr` returns correct, distinct method addresses. All four were lib.

## The four defects (all fixed)

1. **Method-backed properties never applied.** `SetOrdProp`/`SetStrProp` only
   wrote properties whose write is a direct field (`SetKind=0`). `Caption`,
   `Left`, `Top`, `Width`, `Height` write through setter methods (`SetKind=1`)
   and were silently skipped — so streaming set NONE of them. Only events worked
   (`OnClick` writes the `FOnClick` field directly). `test_pcl_lfm` passed only
   because it asserted the click handler, never the (empty) caption.
   Fix: when `SetKind=1`, invoke the setter via its code pointer (Self in rdi,
   value in rsi). `typinfo.pas`. (commit 5735b30)

2. **CreateInstance didn't zero the instance.** It assumed `GetMem` returns
   kernel-zeroed memory, but reused heap blocks are not zeroed → `FHandle` (and
   other fields) held garbage, and a pre-Realize `if FHandle <> nil` check
   dereferenced junk. Fix: explicitly zero the instance. `typinfo.pas`.
   (commit 8da7b86)

3. **Widgets relying on constructor-allocated arrays.** `TListBox`/`TComboBox`
   `SetLength` their `FItems`/`FRows` in the constructor; streaming skips it, so
   the dynamic arrays were nil and `FItems[0] := s` crashed. Fix: `AddItem` grows
   the arrays on demand (also drops the old 256-item cap). `stdctrls.pas`.
   (commit 8da7b86)

4. **Streamed TPaintBox had no Canvas.** `TPaintBox.Create` makes `FCanvas`;
   streaming skips it, so `Canvas = nil`. `ControlDrawTramp` does
   `paintBox.Canvas.Handle := cr` on every expose → nil deref → segfault under
   `gtk_main` (a neighbouring event-wired widget shifted layout timing enough to
   make the area get an expose, which is why it looked combination-specific).
   Fix: create `FCanvas` in `CreateHandle` (runs at Realize for streamed + normal
   instances). `extctrls.pas`. (commit aa4c380)

## Constructor-skip audit

Audited every PCL constructor for state `CreateInstance` would miss:

- Crash-risk (allocate sub-objects/arrays): TPaintBox, TListBox, TComboBox — all
  fixed above.
- Safe (only `HandleNeeded`; zeroing covers their fields): TButton, TLabel,
  TEdit, TCheckBox, TMemo, TPanel, TGLArea, TForm.
- Non-widget / unlikely-in-lfm: TTimer (FInterval/FEnabled/UpdateTimer), TMenu
  (FRootMenuItem) init in their constructor → would stream as default-zero, NOT
  crash.

## Contract (STOPGAP guardrail)

Documented at `lib/rtl/typinfo.pas:CreateInstance`: a streamable class must NOT
rely on its constructor for required state — move such setup to a path that also
runs for streamed instances (e.g. `CreateHandle`) or make it lazy/guarded.

This inverts the natural rule (a class *should* rely on its constructor) and is a
**stopgap, not the design**. The proper fix — construct via a metaclass so the
real constructor runs — is ticketed: `urgent/feature-metaclass-construct-dispatch`
(make `metaclassVar.Create` dispatch correctly; the one probed gap) +
`backlog/feature-pcl-component-ctor-owner` (PCL adopts `Create(AOwner)`). A
parameterless `CtorPtr` shortcut was considered and **rejected** (dead-end vs
FPC/LCL compatibility). Once both land, these stopgaps revert to idiomatic
constructors. Full design + the FPC comparison + the OO-compatibility analysis:
`docs/developer/lfm-streaming-and-constructors.md`.

## Verification

`test_pcl_lfm` strengthened to assert the streamed captions (commit 5735b30). A
streamed multi-widget form (incl. an OnClick button + a painting TPaintBox) now
streams its bounds/captions and runs under `gtk_main`. Full `gui_suite` + garin
gate + `eliah --smoke` green throughout.

## Follow-up (separate)

Re-applying the `TEliahForm` layout-from-lfm conversion is tracked in
`backlog/feature-eliah-from-lfm` — unblocked by these fixes.

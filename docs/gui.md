# GUI (GTK3 widgetset + LFM streaming)

PXX has an LCL-compatible GUI layer built on GTK3. Source and event wiring can
come from an `.lfm` form resource, mirroring the Lazarus model. Everything is
pure library work on top of the language; the only compiler features it needs
(shared-library FFI, procedure/method pointers, RTTI, form streaming) are
general and documented in [Pascal Dialect](pascal-dialect.md) and
[C Interoperability](../C_INTEROP.md).

This is an early vertical slice, not a full LCL. It runs on Linux/X11 with
`libgtk-3.so.0` installed (no GTK `-dev` headers required — the binding is a
hand-written Pascal `external` unit, not a header import).

> The hand-written binding is a **stopgap**, not the goal. It hardcodes the
> soname and every prototype, which means manual versioning and drift against
> the installed library. The intended end state is to import the real C headers
> (no hand-redefining of externals) — blocked today by GTK/glib's macro-heavy
> headers. Tracked in [Project TODO](todo.md) §2c.

## Layers

```
LCL units (controls / stdctrls / forms)   LCL-named API: TControl/TButton/TForm/TApplication
        |
gtk3 binding unit                          thin Pascal `external` decls into libgtk-3 / libgobject / libglib
        |
Pascal FFI + @proc + method pointers       general language features (see pascal-dialect.md)
```

The units live in `test/gui/` alongside the demos:

- `gtk3.pas` — external declarations for the GTK/GLib/GObject symbols used, a
  `PC()` helper (Pascal string → NUL-terminated C string), and `SignalConnect`.
- `controls.pas` — `TControl`/`TWinControl`: GTK handle, geometry, `Caption`,
  `OnClick` (a published `TMethod` event), lazy handle creation, and a
  `Realize` pass.
- `stdctrls.pas` — `TButton`.
- `forms.pas` — `TForm` and `TApplication` (`Initialize`, `Run`).

## Widget lifecycle

Widget creation is decoupled from constructors so a streamed component (which
`CreateInstance` allocates without running a constructor) can still get a GTK
widget:

- `CreateHandle` is a virtual hook (a form builds a window, a button builds a
  button and connects its `clicked` signal).
- `HandleNeeded` builds the handle lazily; constructors just call it.
- `Realize` walks a control and its children: build handles, push captions into
  the widgets (`ApplyCaption`), and parent each child. `TApplication.Run`
  realizes the main form, then enters the GTK main loop.

## Events

`OnClick` is an `of object` event stored as a `TMethod` (code + instance). A
single static C trampoline is registered for the GTK `clicked` signal with the
control as user-data; it reads the control's `OnClick` and dispatches it with
`Self` = the handler's instance and `Sender` = the control. Handlers can be
assigned three ways:

```pascal
Button.OnClick := @Form.ButtonClick;          { @obj.method }
```

```pascal
{ via RTTI — the same calls the form streamer makes }
SetMethodProp(Button, GetPropInfo(cls, 'OnClick'), m);
```

```text
{ via an .lfm line }   OnClick = ButtonClick
```

## Form streaming (.lfm)

A form's constructor streams an embedded `.lfm` with `InitInheritedComponent`,
which finds the form's RTTI and resource by class name, converts the `.lfm`
text to a binary form stream, and walks it with a `TReader`: setting published
properties, instantiating child components by class name, and resolving event
identifiers to `TMethod` values against the root form.

```pascal
{$R TMainForm test_lcl_lfm.lfm}

type
  TMainForm = class(TForm)
    count: Integer;
    constructor Create;
  published
    procedure Btn1Click(Sender: TObject);
  end;

constructor TMainForm.Create;
begin
  Self.HandleNeeded;                          { build the window }
  InitInheritedComponent(Self, 'TMainForm');  { stream Caption + child + event }
end;
```

With the form text:

```text
object MainForm: TMainForm
  Caption = 'LFM Streamed'
  object Btn1: TButton
    Caption = 'Click me'
    OnClick = Btn1Click
  end
end
```

The form caption, the child `TButton` (created by class name), its caption, and
the `OnClick` wiring all come from the `.lfm`. `Realize` then builds the GTK
widgets and a click runs `Btn1Click`.

## Demos (in `test/gui/`)

| File | Shows |
| --- | --- |
| `test_gtk_ffi.pas` | FFI smoke test — links `libgtk-3.so.0`, prints the version. |
| `test_gtk_window.pas` | A real window + button via the raw binding. |
| `test_gtk_signals.pas` | GTK signal callbacks (destroy / clicked / timeout) via `@proc`. |
| `test_lcl_window.pas` | Form + button via the LCL-style API. |
| `test_lcl_click.pas` | `OnClick` assigned with `@obj.method`. |
| `test_lcl_event_rtti.pas` | `OnClick` wired through the RTTI reflection path. |
| `test_lcl_lfm.pas` | Full `.lfm` streaming — tree + events from the form text. |

The demos that need no input fire `gtk_button_clicked` synchronously so they
terminate without a windowing robot; the windowed ones quit on a short timeout.

## Final mile — stock `helloworld` compiles unmodified (done 2026-05-31)

The dropped `test/gui/helloworld` (a stock Lazarus project) now compiles and
runs **unmodified**: a GTK window with a button whose click pops a Hello World
message box. Four features closed the gap, each with a `make test` regression:

- **Metaclass / class-reference values.** A class identifier used as a value
  (`Application.CreateForm(TForm1, Form1)`) yields its `PClassRTTI`. Lowered as
  `AN_CLASSREF` → `IR_CLASSREF` → `mov rax, <RTTI-blob address>` through a
  per-class data-ref sentinel `-(CLASSREF_DATAREF_BASE + ci)` patched after
  `EmitRTTI` (the same trick as the `-100`/`-101` registry/resource sentinels).
- **`initialization` sections execute.** They were parsed and dropped; now each
  unit's section is compiled into a synthesised `__init_<unit>` proc collected
  in `InitProcs[]` and called at program entry, in dependency order, before the
  main body. This is how the `forms` unit creates `Application`. `finalization`
  is parsed and skipped.
- **`{$R *.lfm}` wildcard + `{$R *.res}` no-op.** A leading `*` resolves to the
  current unit's base name (tracked at lex time); a `.res` file is ignored; when
  the directive's name field is empty the resource name is derived from the
  `.lfm` root object's class, so `InitInheritedComponent(Self, ClassName)` finds
  it.
- **`Dialogs.ShowMessage` + LCL glue.** `ShowMessage` wraps the variadic
  `gtk_message_dialog_new` (the external-call path now zeroes `al`, as the SysV
  ABI requires for variadic callees). `TApplication.CreateForm` instantiates the
  metaclass with `CreateInstance`, streams it by runtime `ClassName`, and keeps
  it as the main form; no-arg `Run` realises it and enters `gtk_main`. A class's
  implicit first section now defaults to `published` (Delphi `$M+`), so a stock
  `TForm`'s fields and event handlers are streamable without an explicit
  `published`.

A compiler bug surfaced and was fixed along the way: a property/field reached
through a **class-typed field** base (`host.field.prop`) did not dereference the
field's pointer before applying the next offset (`test_field_chain`).

Library units moved out of `compiler/` into `lib/rtl` (RTL) and `lib/lcl`
(widgetset); the unit resolver searches both after `compiler/`. Two more GUI
demos: `test_lcl_showmessage.pas` (a message dialog) and
`test_lcl_helloworld.pas` (the full mile, mirroring `helloworld` but
self-terminating: synthetic click → `ShowMessage` → dismiss → quit).

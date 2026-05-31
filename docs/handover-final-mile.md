# Handover: GUI final mile — compile the dropped `helloworld` unmodified

> **STATUS: DONE (2026-05-31).** The stock `test/gui/helloworld` now compiles
> and runs **unmodified**. This document is kept as historical context for how
> the four remaining features were scoped; the actual implementation and the
> compiler bug found en route are summarised in [gui.md](gui.md) ("Final mile")
> and the per-feature commits. Library units moved to `lib/rtl` + `lib/lcl`.
> Features landed: metaclass/class-reference values, executing `initialization`
> sections, `{$R *.lfm}` wildcard + `{$R *.res}` no-op, `Dialogs.ShowMessage`,
> `TApplication.CreateForm`/no-arg `Run`, and default-`published` implicit class
> sections. Regressions: `test_classref`, `test_initsec`, `test_wildcard_lfm`,
> `test_field_chain` (in `make test`), plus the GUI harness
> `test/gui/test_lcl_helloworld`.

**Audience:** a fresh session with no prior context. Read this top to bottom;
it is self-contained. Treat the source and regression tests as authoritative.

## The goal

Make the stock Lazarus project at `test/gui/helloworld/` compile and run
**unmodified** with PXX: a GTK window with a button whose click pops a
"Hello World" message box. The project is real Lazarus output — do not edit it
(editing it is allowed only as a last-resort fallback, and should be called out
if done).

The widgetset + form-streaming + event engine underneath is already built and
proven. What remains is a small set of LCL-compatibility features so the exact
Lazarus-generated source shape compiles. This is the last mile of the GUI arc.

## Where things stand (already working — build on it)

The full arc is documented in **[gui.md](gui.md)**. Read it first. Summary of
what already works end to end:

- Native x86-64 ELF, IR backend is default, self-hosting. Build with
  `make bootstrap` (FPC seed → two self-built generations, bit-identical).
  Run a program: `./compiler/pascal26 src.pas /tmp/out && /tmp/out`.
  `make test` runs the regression suite to a fixedpoint check (exit 0).
- A GTK3 widgetset in `test/gui/`: `gtk3.pas` (hand-written `external` binding),
  `controls.pas` (`TControl`/`TWinControl`), `stdctrls.pas` (`TButton`),
  `forms.pas` (`TForm`, `TApplication`).
- `of object` events: `OnClick` is a published `TMethod`; a static GTK
  trampoline dispatches it. Assignable via `@obj.method`, via RTTI
  `SetMethodProp`, or from an `.lfm` `OnClick = Handler` line.
- Full `.lfm` streaming: `test/gui/test_lcl_lfm.pas` is the **template to
  follow** — a form whose constructor calls `InitInheritedComponent(Self,
  'TMainForm')` and gets its caption, child button, and `OnClick` wiring from
  an embedded `.lfm`. It works (window shows, click fires the handler).
- Display: this box has X at `:0`. GUI demos that need no input fire
  `gtk_button_clicked` synchronously so they terminate; windowed ones quit on a
  short timeout. Use the same patterns for any new test.

Verify the baseline before starting: `make bootstrap` then run
`./compiler/pascal26 test/gui/test_lcl_lfm.pas /tmp/t && /tmp/t` — expect
`lfm click! count=1/2`.

## What `helloworld` needs (read its three files)

- `helloworld.lpr`: `uses Interfaces, Forms, main;` then
  `Application.Initialize; Application.CreateForm(TForm1, Form1); Application.Run;`
  (plus `RequireDerivedFormResource := True;` and `Application.Scaled := True;`).
  Also `{$R *.res}`.
- `main.pas`: `unit main; uses Classes, SysUtils, Forms, Controls, Graphics,
  Dialogs, StdCtrls;` declaring `TForm1 = class(TForm) Button1: TButton;
  procedure Button1Click(Sender: TObject); end;` `var Form1: TForm1;`
  `{$R *.lfm}`, and `Button1Click` calls `ShowMessage('Hello World')`.
- `main.lfm`: `object Form1: TForm1 ... object Button1: TButton ... OnClick =
  Button1Click end end`.

## The gaps, in priority order

### 1. `Application.CreateForm(TForm1, Form1)` — metaclass + virtual constructor

`CreateForm` takes a **class reference** (`TForm1`, a "class of" value) and a
`var` form variable. Today `TForm1.Create` would have to be written explicitly
(as in `test_lcl_lfm.pas`). LCL instead has a virtual `TComponent.Create(AOwner)`
that calls `InitInheritedComponent` using the instance's runtime class name, and
`CreateForm` instantiates the passed metaclass and stores it back.

Needs:
- **Class-reference type** (`class of TForm` / passing `TForm1` as a value).
  Check whether the dialect has any `class of` support (grep `class of`,
  `tkClass`); likely none — this is the main new language feature here.
- **Runtime class name** of an instance (for `InitInheritedComponent` to find
  the `.lfm` resource by name) — i.e. a `ClassName`/VMT-name slot. RTTI already
  stores the class name (`TClassRTTI.NamePtr`); wire a way to get it from an
  instance (VMT → RTTI → name).
- **Virtual constructor**: `TForm.Create(AOwner)` virtual; `CreateForm`
  allocates the metaclass and runs it. Virtual dispatch from a metaclass value
  needs the VMT of the runtime class. (Virtual procedure-call statements and
  full VMT inheritance already work — see git log around this date.)

Approach sketch: implement `class of` as a value carrying the class's VMT/RTTI
pointer; `CreateForm(meta, var ref)` allocates `meta.InstanceSize`, sets VMT,
calls the virtual constructor, assigns `ref`. The constructor calls
`InitInheritedComponent(Self, Self.ClassName)`. If `class of` is too big for
one session, a thinner intermediate is acceptable: keep an explicit
`TForm1.Create` in a fallback copy of the project and first close gaps 2–4.

### 2. `ShowMessage` — a `Dialogs` unit over GTK

`main.pas` calls `ShowMessage('Hello World')`. Implement a `Dialogs` unit
(in `test/gui/`, or wherever the LCL units end up — see "Unit path" below)
that wraps `gtk_message_dialog_new` + `gtk_dialog_run` + `gtk_widget_destroy`.
Add the needed externals to `gtk3.pas`. This is self-contained and a good
first task to land. Watch the variadic `gtk_message_dialog_new` — bind a fixed
non-variadic shim or pass a `"%s"` format plus the string; verify arg passing.

### 3. The LCL unit names must resolve with the right API

`helloworld` uses `Interfaces, Forms, Controls, Graphics, Dialogs, StdCtrls,
Classes, SysUtils`. We have `controls`/`stdctrls`/`forms`. Missing/needed:
- `Interfaces` — in LCL this initializes the widgetset; here it can be a
  near-empty stub unit (its `uses` side effect is enough).
- `Graphics`, `Classes`, `SysUtils` — `helloworld` references none of their
  symbols directly in this minimal form, but the `uses` must resolve. Provide
  thin stub units (or alias to existing ones; `classes_lite` exists).
- `Dialogs` — gap 2.

### 4. `{$R *.lfm}` and the form↔resource binding

PXX's resource directive is `{$R name file}` (see `test_lcl_lfm.pas`:
`{$R TMainForm test_lcl_lfm.lfm}`). Lazarus uses `{$R *.lfm}` (wildcard) in the
unit plus `{$R *.res}` in the program. To compile unmodified, `{$R *.lfm}` must
embed the unit's `.lfm` under the form's class name. Options: support the
`*.lfm` wildcard form (resolve `*` to the current unit's base name, register the
embedded form under the class declared in it), and make `{$R *.res}` a no-op.
The streamed-child → published-field wiring (assign the created `Button1` to
`TForm1.Button1`) is a nicety — not required for the button to show or the click
to fire (Realize walks `FChildren`), but do it if reaching for full fidelity.

## Unit path note

The widgetset units live in `test/gui/`. The unit resolver searches the source
file's directory, then `compiler/`. A program in `test/gui/helloworld/` will not
find units in `test/gui/`. Decide early: either move the LCL/RTL units into
`compiler/` (the current de-facto library dir, where `classes_lite.pas`,
`typinfo.pas`, etc. already live) or add a search path. Moving the GUI units to
`compiler/` alongside the existing RTL is the path of least resistance and aligns
with the eventual real-units-dir plan (see todo.md).

## Dialect gotchas (will bite otherwise)

- **No `inherited`.** Each constructor self-initializes; use virtual hooks.
- **Virtual dispatch from inside a method needs `Self.Method`** — a bare call
  binds statically.
- **No nested `{ }` comments** — `{ ... {x} ... }` ends the comment at the inner
  `}` and spills the rest as code. Use parens in comments.
- **No `initialization` sections** — they are parsed but not executed; create
  globals (like `Application`) explicitly.
- **Streamable properties must be field-backed** — `SetStrProp` can't drive a
  method-setter property. (`const` record params are passed by reference now, so
  `SetMethodProp(const v: TMethod)` works.)
- Self-host constraints still apply to anything compiled into the compiler (no
  `shl`, build strings with `AppendChar`, etc.) — but the GUI units are user
  code, not compiler code, so they only need to satisfy the PXX dialect.

## Suggested order

1. `Dialogs.ShowMessage` (+ gtk dialog externals) — small, self-contained.
2. Stub `Interfaces`/`Graphics`/`Classes`/`SysUtils` units so the `uses`
   resolves; decide the unit path.
3. `{$R *.lfm}` wildcard + `{$R *.res}` no-op.
4. `class of` + virtual constructor + `CreateForm` + runtime `ClassName`.

Land each with a small `test/gui/` regression in the working style. Keep commits
per logical unit; do not push without explicit confirmation. When `helloworld`
builds and a synthetic click pops the message box, the GUI arc is complete.

## Key files

- `test/gui/gtk3.pas` — GTK/GLib externals + helpers.
- `test/gui/{controls,stdctrls,forms}.pas` — the widgetset.
- `test/gui/test_lcl_lfm.pas` (+ `.lfm`) — the working streaming template.
- `compiler/lfm.pas` — `InitInheritedComponent`, `.lfm`→TPF0, `TReader` driver.
- `compiler/classes_lite.pas` — `TComponent` + `TReader`.
- `compiler/typinfo.pas` — RTTI API (`GetClass`, `GetMethodAddr`, `SetMethodProp`...).
- `compiler/resources.pas` + `compiler/resources_emit.inc` — `{$R name file}`.
- `compiler/rtti_emit.inc` — class RTTI emission (`ClassHasPublished`, etc.).
- `compiler/parser.inc` — class/VMT/`@`/`external` parsing; `ParseTypeSection`
  for `class of` work.
- `compiler/cparser.inc` / `cpreproc.inc` — C importer (relevant to the broader
  header-import goal, todo §2c, not this mile).

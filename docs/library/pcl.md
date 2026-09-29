---
title: PCL (GUI)
order: 56
---

# PCL: GUI programs in Pascal

The PXX Component Library (PCL) is PXX's own GUI library for Pascal programs,
in the shape Lazarus and Delphi use: a `TForm` holds controls such as
`TButton` and `TEdit`, an event is a method assigned to a property like
`OnClick`, and a form can be designed in an `.lfm` file and streamed in at run
time. It is written from scratch and is much smaller than Lazarus' LCL. Its
units live in `lib/pcl/`.

Underneath, the PCL draws through GTK 3 on Linux. That is its only
"widgetset" so far, and everything below was measured on Linux x86-64.

For a Nil Python program, use [tkinter](./tkinter.md) instead.

## What you need

- To build: the GTK 3 development package, `sudo apt install libgtk-3-dev`.
  The compiler reads the GTK headers from `/usr/include` by itself, so no
  flags are needed.
- To run: GTK 3, which that package pulls in.
- To run without a desktop, Xvfb (`sudo apt install xvfb`), and start the
  program with `GDK_BACKEND=x11 xvfb-run -a`. The `GDK_BACKEND=x11` matters
  when you run it from a Wayland desktop session: without it GTK opens its
  window on your desktop instead of inside Xvfb.

## An example

A form built in code, without an `.lfm` file: an edit box, a check box, a
button and a label in a vertical box. The button's `OnClick` is a method.
Instead of waiting for a person, a `TTimer` types a name, clicks the button,
ticks the box, prints what the controls now hold, and quits, so the program
also runs headless.

```pascal
program pcl_hello;

uses interfaces, uwidgetset, forms, controls, stdctrls, extctrls, gtk3_c;

type
  TApp = class
    Edit: TEdit;
    Check: TCheckBox;
    Button: TButton;
    Greeting: TLabel;
    procedure ButtonClick(Sender: TObject);
    procedure Tick(Sender: TObject);
  end;

procedure TApp.ButtonClick(Sender: TObject);
begin
  Greeting.Caption := 'Hello, ' + Edit.Text;
end;

procedure TApp.Tick(Sender: TObject);
begin
  Edit.Text := 'PXX';
  gtk_button_clicked(Button.Handle);   { what a real click does }
  Check.Checked := True;
  writeln('label: ', Greeting.Caption);
  writeln('checked: ', Check.Checked);
  WidgetSet.AppQuit;
end;

var
  Form: TForm;
  Box: TBox;
  App: TApp;
  Timer: TTimer;
begin
  Application.Initialize;
  Form := TForm.Create(nil);
  Form.Caption := 'PCL hello';
  Box := TBox.Create(nil);
  Box.Vertical := True;
  Box.Parent := Form;

  App := TApp.Create;
  App.Edit := TEdit.Create(nil);
  App.Edit.Parent := Box;
  App.Check := TCheckBox.Create(nil);
  App.Check.Caption := 'Remember me';
  App.Check.Parent := Box;
  App.Button := TButton.Create(nil);
  App.Button.Caption := 'Greet';
  App.Button.OnClick := @App.ButtonClick;
  App.Button.Parent := Box;
  App.Greeting := TLabel.Create(nil);
  App.Greeting.Caption := '(nobody yet)';
  App.Greeting.Parent := Box;

  Timer := TTimer.Create(nil);
  Timer.Interval := 300;
  Timer.OnTimer := @App.Tick;
  Timer.Enabled := True;

  Application.MainForm := Form;
  Application.Run;
  writeln('closed');
end.
```

```sh
./pxx pcl_hello.pas pcl_hello
GDK_BACKEND=x11 xvfb-run -a ./pcl_hello
```

```text
label: Hello, PXX
checked: TRUE
closed
```

Built with pin v451 (compiler sha256 `d9b7226769cc`) through `./pxx`, and
with the pinned compiler called directly (the same binary), and run under
`xvfb-run` on 2026-09-29. `gtk_button_clicked` comes from `gtk3_c`, the GTK
binding, and stands in for a person clicking. Remove the timer to keep the
window open. Closing the main form ends `Application.Run`, and
`WidgetSet.AppQuit` (unit `uwidgetset`) ends it from code.

## What works

| Unit | Classes and routines |
| --- | --- |
| `forms` | `TForm` (`Caption`, `Menu`, `Realize`), `TApplication` (`Initialize`, `CreateForm`, `Run`, `MainForm`); the global `Application` |
| `controls` | `TControl`: `Left`, `Top`, `Width`, `Height`, `SetBounds`, `Caption`, `Parent`, `Handle`, `Show`, `Invalidate`, and the events `OnClick`, `OnMouseDown`, `OnMouseUp`, `OnMouseMove`, `OnKeyDown`, `OnResize` |
| `stdctrls` | `TButton`, `TLabel`, `TEdit`, `TCheckBox`, `TMemo`, `TListBox`, `TComboBox` (`Text`, `Checked`, `AddItem`, `Item`, `Count`, `ItemIndex`, `OnChange`) |
| `extctrls` | `TPanel`, `TTimer`, `TPaintBox` (`Canvas`, `OnPaint`), `TBox` (a row or column), `TPaned` (a split with a movable divider), `TTabBar` |
| `comctrls` | `TTreeView` and `TTreeNode`, `TToolBar` |
| `menus` | `TMainMenu`, `TMenuItem` (`Caption`, `Enabled`, `Visible`, `OnClick`) |
| `dialogs` | `ShowMessage`; `TOpenDialog`, `TSaveDialog`, `TSelectDirectoryDialog` (set the properties, call `Execute`, read `FileName`) |
| `graphics` | `TCanvas` (`MoveTo`, `LineTo`, `Rectangle`, `Ellipse`, `TextOut`, `Draw`) with `TPen`, `TBrush`, `TFont`; `TBitmap`; colour constants such as `clRed`. Drawing goes through Cairo. |
| `glarea` | `TGLArea`: an OpenGL drawing area with `OnRender` |

A form can also be designed in a Lazarus-style `.lfm` file. With
`{$R *.lfm}` in the program, `Application.CreateForm(TForm1, Form1)`
creates the form, its controls and their event links from the file. With v451
on 2026-09-29, the test programs for these parts ran under Xvfb and printed
their success lines: `test/gui/test_pcl_lfm.pas` and
`test/gui/test_pcl_helloworld.pas` (`.lfm` streaming and `ShowMessage`),
`test/gui/test_pcl_widgets.pas`, `test/gui/test_pcl_drawing.pas` and
`test/gui/test_pcl_menus.pas`. `tools/gui_suite.sh` runs the whole set.

Larger programs built on the PCL are shown on the
[Examples page](../examples/index.md#pascal-gui-applications): an OpenGL
triangle, the Game of Life, a Mandelbrot explorer, a ray tracer and
Solitaire. All five build with v451. The Mandelbrot explorer renders on
several threads, so it needs the flag: `./pxx --threadsafe
examples/mandelbrot/mandelbrot_gui.pas mandelbrot_gui`.

## Limits

Measured with pin v451 on 2026-09-29:

- **Linux and GTK 3 only.** `-dWIDGETSET_WIN32` stops the build ("widgetset
  win32 exists only on windows"), and on Windows neither a Win32 nor a Qt
  widgetset exists yet.
- **A subset of the LCL.** `TControl` has no `Enabled`, `Visible`, `Align`,
  `Anchors`, `Font` or `Color`, so `Button.Enabled := False` stops the build
  ("no such member"). Arrange controls with `TBox`, `TPaned` and `TTabBar`
  rather than `Align` and anchors. A form written for Lazarus usually needs
  changes before it compiles.
- **No `Application.Terminate`.** Close the main form, or call
  `WidgetSet.AppQuit`.
- **Pascal only.** A Nil Python program uses [tkinter](./tkinter.md).

---
title: Terminal UI
order: 54
---

# Terminal UI

PXX includes a small terminal UI stack for ANSI terminals. It is split into
low-level escape helpers, a buffered screen manager, and pure state helpers for
common widgets.

These units are intended for local terminal programs. They are not a replacement
for a full GUI toolkit, and they assume an ANSI-compatible terminal.

## Units

| Unit | Purpose |
| --- | --- |
| `ansiterm` | ANSI escape strings, cursor movement, raw mode, terminal size, and unbuffered terminal output. |
| `screen` | Buffered ncurses-style screen manager with colors, clipping, boxes, lines, key decoding, and minimal repaint output. |
| `lineedit` | Pure single-line editor state: text, cursor, insertion, deletion, and navigation keys. |
| `menu` | Pure vertical menu navigation helper. The caller renders the selected item. |
| `ansirender` | Render `image` buffers as ASCII, 256-color ANSI, or true-color block output. |

## Screen Drawing

The `screen` unit keeps a back buffer and a front buffer. Drawing calls change
the back buffer. `ScreenRender` computes the escape sequence needed to update the
terminal, and `ScreenRefresh` writes that sequence to stdout.

For non-interactive layout tests, initialize a fixed-size screen and inspect the
plain text rows:

```pascal
program screen_layout;

uses screen;

begin
  ScreenInitSize(20, 5);
  ScreenBox(0, 0, 20, 5);
  ScreenWrite(2, 2, 'Hello');
  writeln(ScreenDumpRow(0));
  writeln(ScreenDumpRow(2));
end.
```

Expected output:

```text
+------------------+
| Hello            |
```

For a real full-screen TUI, enter raw alternate-screen mode with `ScreenStart`,
redraw the back buffer each frame, call `ScreenRefresh`, then restore the
terminal with `ScreenEnd`:

```pascal
program fullscreen_example;

uses screen;

begin
  ScreenStart;
  try
    ScreenClear;
    ScreenWrite(2, 1, 'Press q to quit');
    ScreenRefresh;
    while ScreenWaitKey <> Ord('q') do begin end;
  finally
    ScreenEnd;
  end;
end.
```

If you avoid exceptions in a small demo, use the same shape with a Boolean loop
and make sure `ScreenEnd` runs before the program exits.

## Colors And Attributes

`ScreenSetPen(fg, bg, attr)` selects the current drawing style.

Common color constants:

| Constant | Meaning |
| --- | --- |
| `COLOR_DEFAULT` | Use the terminal default color. |
| `COLOR_BLACK` through `COLOR_WHITE` | Normal ANSI colors `0..7`. |
| `COLOR_BRIGHT_BLACK` through `COLOR_BRIGHT_WHITE` | Bright ANSI colors `8..15`. |

Attributes can be combined with bitwise `or`:

```pascal
program color_example;

uses screen;

begin
  ScreenInitSize(10, 1);
  ScreenSetPen(COLOR_BRIGHT_YELLOW, COLOR_DEFAULT, ATTR_BOLD or ATTR_UNDERLINE);
  ScreenWrite(0, 0, 'Warning');
  writeln(ScreenDumpRow(0));
end.
```

Available attributes are `ATTR_NONE`, `ATTR_BOLD`, `ATTR_DIM`,
`ATTR_UNDERLINE`, and `ATTR_REVERSE`.

## Clipping

`ScreenSetClip(x, y, w, h)` makes later draw coordinates relative to a rectangular
region. This is the basis for panels:

```pascal
program clipping_example;

uses screen;

begin
  ScreenInitSize(13, 5);
  ScreenSetClip(0, 1, 6, 4);
  ScreenBox(0, 0, 6, 4);
  ScreenWrite(1, 1, 'L');

  ScreenSetClip(7, 1, 6, 4);
  ScreenBox(0, 0, 6, 4);
  ScreenWrite(1, 1, 'R');

  ScreenResetClip;
  writeln(ScreenDumpRow(2));
end.
```

## Keyboard Input

Plain byte keys are returned as their ordinal values. Non-byte keys use
`KEY_*` constants from `screen`:

| Key | Constant |
| --- | --- |
| Arrow keys | `KEY_UP`, `KEY_DOWN`, `KEY_LEFT`, `KEY_RIGHT` |
| Home / End | `KEY_HOME`, `KEY_END` |
| Page keys | `KEY_PGUP`, `KEY_PGDN` |
| Insert / Delete | `KEY_INS`, `KEY_DEL` |
| Escape | `KEY_ESC` |
| No key | `KEY_NONE` |
| Unknown escape sequence | `KEY_UNKNOWN` |

Use `ScreenWaitKey` in an event loop when you want to block until input arrives.
Use `ScreenReadKey` for polling.

`ScreenDecodeKey` is pure and useful in tests:

```pascal
program key_example;

uses screen;

begin
  if ScreenDecodeKey(#27 + '[A') = KEY_UP then
    writeln('up');
end.
```

## Line Editing

`lineedit` stores only text and cursor state. It does not draw itself, so it can
be tested without a terminal and rendered however the application wants.

```pascal
program lineedit_example;

uses screen, lineedit;

var
  edit: TLineEdit;

begin
  LineEditInit(edit);
  LineEditKey(edit, Ord('h'));
  LineEditKey(edit, Ord('i'));
  LineEditKey(edit, KEY_LEFT);
  LineEditKey(edit, Ord('!'));
  writeln(edit.Text);
end.
```

`LineEditKey` returns `True` when it consumed a printable character or editing
key. It returns `False` for keys such as Enter or Escape so the caller can submit
or cancel.

## Menus

`menu` provides `MenuNavigate(count, selected, key, wrap)`. It updates the
selected index for arrow, Home, and End keys, clamps out-of-range selections, and
optionally wraps at the ends.

Rendering is caller-side:

```pascal
program menu_render_example;

uses screen, menu;

var
  items: array[0..2] of AnsiString;
  i, selected: Integer;

begin
  items[0] := 'Open';
  items[1] := 'Save';
  items[2] := 'Quit';
  selected := MenuNavigate(3, 0, KEY_DOWN, True);

  ScreenInitSize(8, 3);
  for i := 0 to 2 do
  begin
    if i = selected then
      ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_REVERSE)
    else
      ScreenSetPen(COLOR_DEFAULT, COLOR_DEFAULT, ATTR_NONE);
    ScreenWrite(1, i, items[i]);
  end;
  writeln(ScreenDumpRow(selected));
end.
```

See `examples/tui/menudemo.pas` for a complete interactive menu.

## Image Rendering

`ansirender` converts an `image.TImage` to terminal text:

| Function | Output |
| --- | --- |
| `RenderAscii` | Plain ASCII luminance ramp. |
| `RenderAnsi256` | 256-color ANSI foreground output. |
| `RenderAnsiTrueColorHalfBlock` | True-color upper-half-block cells. |
| `RenderAnsiTrueColorQuadrant` | True-color quadrant-block approximation. |

These functions return strings; they do not write to the terminal directly.

## Next

- [Standard library](./)
- [Examples](../examples/)

program test_pcl_input;
{ Verifies PCL mouse events end to end: assign OnMouseDown to a PaintBox, then
  synthesize a GdkEventButton (a layout-matched record) and dispatch it through
  gtk_widget_event. The trampoline reads button/x/y via the gdk accessors and the
  asm method-dispatch delivers them to the handler — we assert the handler ran
  with the injected values. }

uses gtk3, controls, extctrls, forms;

type
  { GdkEventButton, GTK3 / 64-bit layout — enough fields for a button press. }
  TGdkBtn = record
    etype: Integer;        { 0  : GdkEventType (GDK_BUTTON_PRESS = 4) }
    pad0: Integer;         { 4  : align window to 8 }
    window: Pointer;       { 8  }
    sendEvent: Byte;       { 16 }
    pb0, pb1, pb2: Byte;   { 17..19 : pad time to 20 }
    time: LongWord;        { 20 }
    x: Double;             { 24 }
    y: Double;             { 32 }
    axes: Pointer;         { 40 }
    state: LongWord;       { 48 }
    button: LongWord;      { 52 }
  end;
  PGdkBtn = ^TGdkBtn;

  { GdkEventKey, GTK3 / 64-bit — keyval at offset 28. }
  TGdkKey = record
    etype: Integer;        { 0  : GDK_KEY_PRESS = 8 }
    pad0: Integer;         { 4  }
    window: Pointer;       { 8  }
    sendEvent: Byte;       { 16 }
    pk0, pk1, pk2: Byte;   { 17..19 }
    time: LongWord;        { 20 }
    state: LongWord;       { 24 }
    keyval: LongWord;      { 28 }
  end;
  PGdkKey = ^TGdkKey;

  { GtkAllocation is gint x, y, width, height. }
  TAlloc = record x, y, w, h: Integer; end;
  PAlloc = ^TAlloc;

  THandler = class
    gotButton, gotX, gotY, gotKey, gotW, gotH, count, keyCount, resizeCount: Integer;
    procedure MouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure KeyDown(Sender: TControl; KeyCode: Integer);
    procedure Resize(Sender: TControl; Width, Height: Integer);
  end;

procedure THandler.MouseDown(Sender: TControl; Button, X, Y: Integer);
begin
  gotButton := Button;
  gotX := X;
  gotY := Y;
  count := count + 1;
end;

procedure THandler.KeyDown(Sender: TControl; KeyCode: Integer);
begin
  gotKey := KeyCode;
  keyCount := keyCount + 1;
end;

procedure THandler.Resize(Sender: TControl; Width, Height: Integer);
begin
  gotW := Width;
  gotH := Height;
  resizeCount := resizeCount + 1;
end;

var
  Form1: TForm;
  PaintBox: TPaintBox;
  h: THandler;
  m: TMethod;
  ev: PGdkBtn;
  evk: PGdkKey;
  alloc: PAlloc;
  handled, fails: Integer;

begin
  fails := 0;
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create(nil);
  Form1.Caption := 'Input test';
  PaintBox := TPaintBox.Create(nil);
  PaintBox.Parent := Form1;
  PaintBox.SetBounds(0, 0, 200, 200);

  h := THandler.Create;
  h.count := 0;
  h.keyCount := 0;
  h.resizeCount := 0;
  m.Code := @h.MouseDown; m.Data := h;
  PaintBox.OnMouseDown := m;
  m.Code := @h.KeyDown; m.Data := h;
  PaintBox.OnKeyDown := m;
  m.Code := @h.Resize; m.Data := h;
  PaintBox.OnResize := m;

  Form1.Realize;

  { synthesize a left-button press at (42,17) }
  ev := malloc(128);
  ev^.etype := 4;            { GDK_BUTTON_PRESS }
  ev^.window := gtk_widget_get_window(PaintBox.Handle);
  ev^.sendEvent := 1;
  ev^.time := 0;
  ev^.x := 42;
  ev^.y := 17;
  ev^.axes := nil;
  ev^.state := 0;
  ev^.button := 1;

  { emit the signal directly -> fires the connected trampoline (no realized-window
    assertion as gtk_widget_event would impose headlessly). }
  handled := 0;
  g_signal_emit_by_name(PaintBox.Handle, PC('button-press-event'), ev, @handled);

  if h.count < 1 then begin writeln('fired=bad'); fails := fails + 1; end
  else writeln('fired=ok');
  if h.gotButton = 1 then writeln('button=ok') else begin writeln('button=bad ', h.gotButton); fails := fails + 1; end;
  if h.gotX = 42 then writeln('x=ok') else begin writeln('x=bad ', h.gotX); fails := fails + 1; end;
  if h.gotY = 17 then writeln('y=ok') else begin writeln('y=bad ', h.gotY); fails := fails + 1; end;

  { synthesize a key press (keyval 65 = 'A') }
  evk := malloc(128);
  evk^.etype := 8;          { GDK_KEY_PRESS }
  evk^.window := gtk_widget_get_window(PaintBox.Handle);
  evk^.sendEvent := 1;
  evk^.time := 0;
  evk^.state := 0;
  evk^.keyval := 65;
  handled := 0;
  g_signal_emit_by_name(PaintBox.Handle, PC('key-press-event'), evk, @handled);
  if h.keyCount < 1 then begin writeln('key-fired=bad'); fails := fails + 1; end
  else writeln('key-fired=ok');
  if h.gotKey = 65 then writeln('key=ok') else begin writeln('key=bad ', h.gotKey); fails := fails + 1; end;

  { synthesize a size-allocate (new allocation 800x600) }
  alloc := malloc(64);
  alloc^.x := 0; alloc^.y := 0; alloc^.w := 800; alloc^.h := 600;
  handled := 0;
  g_signal_emit_by_name(PaintBox.Handle, PC('size-allocate'), alloc, @handled);
  if h.resizeCount < 1 then begin writeln('resize-fired=bad'); fails := fails + 1; end
  else writeln('resize-fired=ok');
  if (h.gotW = 800) and (h.gotH = 600) then writeln('resize=ok')
  else begin writeln('resize=bad ', h.gotW, 'x', h.gotH); fails := fails + 1; end;

  if fails = 0 then writeln('ALL OK') else writeln('FAILS=', fails);
  if fails <> 0 then Halt(1);
end.

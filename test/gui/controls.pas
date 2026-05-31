unit controls;

{ LCL-compatible control base classes, bridged to GTK3.

  TControl carries the GTK widget handle and the common geometry/caption
  properties; TWinControl is the windowed-container base (forms, buttons).
  The dialect has no `inherited`, so each concrete control's constructor
  builds its own widget and stores it in FHandle; ApplyCaption is a virtual
  hook each control overrides to push its caption into the right GTK call. }

interface

uses typinfo, classes_lite, gtk3;

type
  TControl = class(TComponent)
  private
    FHandle: Pointer;
    FParent: TControl;
    FLeft, FTop, FWidth, FHeight: Integer;
    FCaption: string;
    FOnClick: TMethod;
    procedure SetParent(p: TControl);
  public
    procedure CreateHandle; virtual;   { build the GTK widget; overridden per control }
    procedure HandleNeeded;            { ensure FHandle exists (lazy, for streamed instances) }
    procedure Realize;                 { build handle + caption + child widgets, recursively }
    procedure ApplyCaption; virtual;
    procedure Show;
    procedure ConnectClick;
    property Handle: Pointer read FHandle write FHandle;
    property Parent: TControl read FParent write SetParent;
  published
    property Left: Integer read FLeft write FLeft;
    property Top: Integer read FTop write FTop;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    { Field-backed so the streamer (SetStrProp) can set it; the GTK widget is
      updated at Realize via ApplyCaption (the widget may not exist yet). }
    property Caption: string read FCaption write FCaption;
    { `of object` event (TMethod, Code+Data). Streamable as RTTI piMethod;
      set via the RTTI path (SetMethodProp) or directly with @obj.method. }
    property OnClick: TMethod read FOnClick write FOnClick;
  end;

  TWinControl = class(TControl)
  end;

implementation

{ Indirect call of an `of object` event handler: rdi = Self (method Data),
  rsi = Sender, then `call rax`. Inline asm has no call mnemonic, so the call
  is raw bytes (FF D0 = call rax). rsp is realigned to 16 around the call
  because the handler may itself call GTK/SSE; old rsp is saved on the stack
  (r11 is scratch but the handler may clobber it, so it is reloaded after). }
procedure CallMethod(code: Pointer; data: Pointer; sender: Pointer);
begin
  asm
    mov rdi, data
    mov rsi, sender
    mov rax, code
    mov r11, rsp
    db 72, 131, 228, 240   { and rsp, -16 (raw: `and` is a keyword, unusable as an asm mnemonic here) }
    sub rsp, 8
    push r11
    db 255, 208
    pop r11
    mov rsp, r11
  end;
end;

{ Static GTK 'clicked' handler. user_data is the control instance; dispatch to
  its OnClick method (if set), passing the control as Sender. }
procedure ControlClickTramp(widget: Pointer; userdata: Pointer); cdecl;
var ctl: TControl; m: TMethod;
begin
  ctl := userdata;
  m := ctl.OnClick;
  if m.Code <> nil then
    CallMethod(m.Code, m.Data, userdata);
end;

procedure TControl.ConnectClick;
var h, sp: Pointer;
begin
  h := FHandle;
  sp := Self;
  SignalConnectData(h, 'clicked', @ControlClickTramp, sp);
end;

procedure TControl.CreateHandle;
begin
  { base: no widget. Subclasses build their GTK widget here. }
end;

procedure TControl.HandleNeeded;
begin
  { Self-qualified so CreateHandle dispatches virtually to the concrete control;
    a bare call would bind statically to TControl.CreateHandle (empty). }
  if FHandle = nil then
    Self.CreateHandle;
end;

{ Realize the control and its children: build GTK widgets (lazily, since a
  streamed instance never ran a constructor), push the streamed caption into
  the widget, then realize + parent each child. Window/bin holds one child. }
procedure TControl.Realize;
var i, n: Integer; c: TComponent; ctl: TControl; ph, ch: Pointer;
begin
  Self.HandleNeeded;
  Self.ApplyCaption;
  ph := FHandle;
  n := ChildCount;
  for i := 0 to n - 1 do
  begin
    c := Child(i);
    ctl := c;
    ctl.Realize;
    ch := ctl.Handle;
    gtk_container_add(ph, ch);
  end;
end;

procedure TControl.ApplyCaption;
begin
  { base: no caption surface }
end;

{ Register as a child of p; the actual GTK parenting happens at Realize, which
  unifies the programmatic and streamed (FChildren) paths. }
procedure TControl.SetParent(p: TControl);
begin
  FParent := p;
  p.AddChild(Self);
end;

procedure TControl.Show;
var h: Pointer;
begin
  h := FHandle;
  gtk_widget_show_all(h);
end;

end.

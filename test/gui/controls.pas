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
    procedure SetParent(p: TControl);
    procedure SetCaption(const v: string);
  public
    { `of object` event: a TMethod (Code+Data). Assign with @obj.method.
      Public field for now; a published property (for LFM streaming) is later. }
    OnClick: TMethod;
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
    property Caption: string read FCaption write SetCaption;
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

procedure TControl.ApplyCaption;
begin
  { base: no caption surface }
end;

procedure TControl.SetCaption(const v: string);
begin
  FCaption := v;
  ApplyCaption;
end;

procedure TControl.SetParent(p: TControl);
var ph, ch: Pointer;
begin
  FParent := p;
  ph := p.Handle;
  ch := FHandle;
  gtk_container_add(ph, ch);
end;

procedure TControl.Show;
var h: Pointer;
begin
  h := FHandle;
  gtk_widget_show_all(h);
end;

end.

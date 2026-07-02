{ SPDX-License-Identifier: Zlib }
unit glarea;

interface

uses classes_lite, controls, uwidgetset;

type
  TGLArea = class(TControl)
  private
    FOnRender: TMethod;
    FGLWidth, FGLHeight: Integer;
  public
    constructor Create(AOwner: TComponent); override;
    procedure CreateHandle; override;
    procedure MakeCurrent;
    procedure QueueRender;
    property GLWidth: Integer read FGLWidth write FGLWidth;
    property GLHeight: Integer read FGLHeight write FGLHeight;
  published
    property OnRender: TMethod read FOnRender write FOnRender;
  end;

implementation

uses gl_c, gtk3;

{ Inline asm helper: calls a Pascal method(Self, Width, Height) from C context.
  On entry: data=Self, code=method code ptr, w/h=dimensions.
  Follows the same ABI/callee-save pattern as CallPaintMethod in gtk3widgets. }
procedure CallRenderMethod(code: Pointer; data: Pointer; w, h: Integer);
begin
  asm
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi, data
    mov rsi, w
    mov rdx, h
    mov rax, code
    mov r11, rsp
    db 72, 131, 228, 240   { and rsp, -16 }
    sub rsp, 8
    push r11
    db 255, 208
    pop r11
    mov rsp, r11
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
  end;
end;

{ GtkGLArea "render" signal: gboolean (*)(GtkGLArea*, GdkGLContext*, gpointer)
  Return FALSE to let GTK present; we always return FALSE (0). }
function GLAreaRenderTramp(widget: Pointer; context: Pointer; userdata: Pointer): Integer; cdecl;
var
  gl: TGLArea;
  m: TMethod;
begin
  asm
    push rbx
    push r12
    push r13
    push r14
    push r15
  end;
  Result := 0;
  gl := TGLArea(userdata);
  gtk_gl_area_make_current(widget);
  m := gl.OnRender;
  if m.Code <> nil then
    CallRenderMethod(m.Code, m.Data, gl.GLWidth, gl.GLHeight);
  asm
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
  end;
end;

{ GtkGLArea "resize" signal: void (*)(GtkGLArea*, gint, gint, gpointer) }
procedure GLAreaResizeTramp(widget: Pointer; w, h: Integer; userdata: Pointer); cdecl;
var
  gl: TGLArea;
begin
  asm
    push rbx
    push r12
    push r13
    push r14
    push r15
  end;
  gl := TGLArea(userdata);
  gl.GLWidth  := w;
  gl.GLHeight := h;
  asm
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
  end;
end;

constructor TGLArea.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Self.HandleNeeded;
end;

procedure TGLArea.CreateHandle;
var widget: Pointer;
begin
  widget := gtk_gl_area_new();
  gtk_gl_area_set_required_version(widget, 3, 3);
  SignalConnectData(widget, 'render', @GLAreaRenderTramp, Pointer(Self));
  SignalConnectData(widget, 'resize', @GLAreaResizeTramp, Pointer(Self));
  Self.Handle := widget;
end;

procedure TGLArea.MakeCurrent;
begin
  if Self.Handle <> nil then
    gtk_gl_area_make_current(Self.Handle);
end;

procedure TGLArea.QueueRender;
begin
  if Self.Handle <> nil then
    gtk_gl_area_queue_render(Self.Handle);
end;

end.

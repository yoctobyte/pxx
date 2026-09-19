{ SPDX-License-Identifier: Zlib }
unit glarea;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

uses classes_lite, controls, uwidgetset, typinfo;

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

uses uwidgetset, gtk3gl;   { gtk3gl only INSTALLS the backend; nothing here names it }

{ Inline asm helper: calls a Pascal method(Self, Sender, Width, Height) from C
  context -- the PCL event shape, Sender first, as CallPaintMethod in gtk3widgets
  passes it. On entry: data=Self, code=method code ptr, sender=the TGLArea, w/h=
  dimensions. It used to pass (Self, Width, Height) with no Sender, so a handler
  declared the PCL way, OnRender(Sender; W, H), got the width as Sender, the
  height as W and a stray register as H: measured 2026-09-19, examples/gl/
  triangle rendered into a 480x480 viewport of its 640x480 area. }
procedure CallRenderMethod(code: Pointer; data: Pointer; sender: Pointer; w, h: Integer);
begin
  asm
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi, data
    mov rsi, sender
    mov rdx, w
    mov rcx, h
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
  GLBackend.MakeCurrent(widget);
  m := gl.OnRender;
  if m.Code <> nil then
    CallRenderMethod(m.Code, m.Data, Pointer(gl), gl.GLWidth, gl.GLHeight);
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

{ The GL surface is the allowed sparse point of the seam: a widgetset with no
  GL returns nil from CreateGLArea and the rest degrades to no-ops, rather than
  every backend being forced to implement a GL context. }
procedure TGLArea.CreateHandle;
var widget: Pointer;
begin
  widget := GLBackend.CreateArea(3, 3);
  GLBackend.OnRender(widget, @GLAreaRenderTramp, Pointer(Self));
  GLBackend.OnResize(widget, @GLAreaResizeTramp, Pointer(Self));
  Self.Handle := widget;
end;

procedure TGLArea.MakeCurrent;
begin
  GLBackend.MakeCurrent(Self.Handle);
end;

procedure TGLArea.QueueRender;
begin
  GLBackend.QueueRender(Self.Handle);
end;

end.

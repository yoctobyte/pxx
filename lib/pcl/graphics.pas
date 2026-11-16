{ SPDX-License-Identifier: Zlib }
unit graphics;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ PCL Graphics: TCanvas over a cairo context (linux, the GTK widgetset) or a
  GDI device context (--os=windows, the Win32 widgetset). The two draw the
  same: a rectangle or ellipse is filled with Brush and outlined with Pen,
  TextOut's Y is the top of a line whose baseline sits Font.Size below it,
  and a TBitmap is 32-bit pixels B,G,R,A in memory on both (cairo ARGB32 and a
  top-down GDI DIB section share that layout). }

interface

{$ifdef PXX_OS_WINDOWS}
uses classes_lite;
{$else}
uses classes_lite, gtk3_c;
{$endif}

type
  TColor = LongWord;

const
  clBlack = $00000000;
  clWhite = $00FFFFFF;
  clRed = $000000FF;
  clGreen = $0000FF00;
  clBlue = $00FF0000;
  clYellow = $0000FFFF;
  clNone = $FFFFFFFF;

type
  TFont = class
  private
    FName: string;
    FSize: Integer;
    FColor: TColor;
  public
    constructor Create;
    destructor Destroy;
  published
    property Name: string read FName write FName;
    property Size: Integer read FSize write FSize;
    property Color: TColor read FColor write FColor;
  end;

  TPen = class
  private
    FColor: TColor;
    FWidth: Integer;
  public
    constructor Create;
    destructor Destroy;
  published
    property Color: TColor read FColor write FColor;
    property Width: Integer read FWidth write FWidth;
  end;

  TBrush = class
  private
    FColor: TColor;
  public
    constructor Create;
    destructor Destroy;
  published
    property Color: TColor read FColor write FColor;
  end;

  TBitmap = class
  private
    FWidth: Integer;
    FHeight: Integer;
    FSurface: Pointer;
    FData: Pointer;
    procedure RecreateSurface;
    procedure SetWidth(v: Integer);
    procedure SetHeight(v: Integer);
  public
    constructor Create;
    destructor Destroy;
    procedure Clear(Color: TColor);
    procedure SetPixel(X, Y: Integer; Color: TColor);
    function GetPixel(X, Y: Integer): TColor;
    property Width: Integer read FWidth write SetWidth;
    property Height: Integer read FHeight write SetHeight;
    property Handle: Pointer read FSurface;
    property Data: Pointer read FData;
  end;

  TCanvas = class
  private
    FHandle: Pointer; { cairo_t, or a GDI HDC on windows }
    FPen: TPen;
    FBrush: TBrush;
    FFont: TFont;
    procedure ApplyPen;
    procedure ApplyBrush;
    procedure ApplyFont;
  public
    constructor Create;
    destructor Destroy;
    procedure MoveTo(X, Y: Integer);
    procedure LineTo(X, Y: Integer);
    procedure Rectangle(X1, Y1, X2, Y2: Integer);
    procedure Ellipse(X1, Y1, X2, Y2: Integer);
    procedure TextOut(X, Y: Integer; const Text: string);
    procedure Draw(X, Y: Integer; Bitmap: TBitmap);
    property Handle: Pointer read FHandle write FHandle;
    property Pen: TPen read FPen write FPen;
    property Brush: TBrush read FBrush write FBrush;
    property Font: TFont read FFont write FFont;
  end;

implementation

constructor TFont.Create;
begin
  FName := 'Sans';
  FSize := 10;
  FColor := clBlack;
end;

destructor TFont.Destroy;
begin
end;

constructor TPen.Create;
begin
  FColor := clBlack;
  FWidth := 1;
end;

destructor TPen.Destroy;
begin
end;

constructor TBrush.Create;
begin
  FColor := clWhite;
end;

destructor TBrush.Destroy;
begin
end;

constructor TCanvas.Create;
begin
  FPen := TPen.Create;
  FBrush := TBrush.Create;
  FFont := TFont.Create;
  FHandle := nil;
end;

destructor TCanvas.Destroy;
begin
  FPen.Destroy;
  FBrush.Destroy;
  FFont.Destroy;
end;

{$ifdef PXX_OS_WINDOWS}
{ ---- GDI ------------------------------------------------------------------- }
type
  TBitmapInfo32 = record
    biSize: LongWord;
    biWidth, biHeight: LongInt;
    biPlanes, biBitCount: Word;
    biCompression, biSizeImage: LongWord;
    biXPelsPerMeter, biYPelsPerMeter: LongInt;
    biClrUsed, biClrImportant: LongWord;
    colors: LongWord;
  end;

function CreatePen(style, width: LongInt; color: LongWord): Pointer; stdcall; external 'gdi32.dll';
function CreateSolidBrush(color: LongWord): Pointer; stdcall; external 'gdi32.dll';
function GetStockObject(i: LongInt): Pointer; stdcall; external 'gdi32.dll';
function CreateFontW(h, w, esc, orient, weight: LongInt; italic, underline, strike, charset,
  outprec, clipprec, quality, pitch: LongWord; face: PWideChar): Pointer; stdcall; external 'gdi32.dll';
function SelectObject(dc, obj: Pointer): Pointer; stdcall; external 'gdi32.dll';
function DeleteObject(obj: Pointer): LongInt; stdcall; external 'gdi32.dll';
function MoveToEx(dc: Pointer; x, y: LongInt; old: Pointer): LongInt; stdcall; external 'gdi32.dll';
function GdiLineTo(dc: Pointer; x, y: LongInt): LongInt; stdcall; external 'gdi32.dll' name 'LineTo';
function GdiRectangle(dc: Pointer; l, t, r, b: LongInt): LongInt; stdcall; external 'gdi32.dll' name 'Rectangle';
function GdiEllipse(dc: Pointer; l, t, r, b: LongInt): LongInt; stdcall; external 'gdi32.dll' name 'Ellipse';
function TextOutW(dc: Pointer; x, y: LongInt; s: PWideChar; n: LongInt): LongInt; stdcall; external 'gdi32.dll';
function SetTextColor(dc: Pointer; c: LongWord): LongWord; stdcall; external 'gdi32.dll';
function SetBkMode(dc: Pointer; mode: LongInt): LongInt; stdcall; external 'gdi32.dll';
function SetTextAlign(dc: Pointer; align: LongWord): LongWord; stdcall; external 'gdi32.dll';
function CreateDIBSection(dc: Pointer; const bmi: TBitmapInfo32; usage: LongWord; var bits: Pointer;
  section: Pointer; offset: LongWord): Pointer; stdcall; external 'gdi32.dll';
function CreateCompatibleDC(dc: Pointer): Pointer; stdcall; external 'gdi32.dll';
function DeleteDC(dc: Pointer): LongInt; stdcall; external 'gdi32.dll';
function BitBlt(dst: Pointer; x, y, w, h: LongInt; src: Pointer; sx, sy: LongInt; rop: LongWord): LongInt; stdcall; external 'gdi32.dll';
function MultiByteToWideChar(cp, flags: LongWord; s: PChar; n: LongInt; w: PWideChar; wn: LongInt): LongInt; stdcall; external 'kernel32.dll';

{ TColor is $00BBGGRR, which is GDI's COLORREF already. }
function GdiColor(c: TColor): LongWord;
begin
  Result := c and $00FFFFFF;
end;

{ Select a pen for Pen (or none), and a brush for Brush (or the hollow
  stock brush); the caller draws and then calls GdiRestore. }
procedure GdiSelect(dc: Pointer; pen: TPen; brush: TBrush; var oldPen, oldBrush, newPen, newBrush: Pointer);
var w: LongInt;
begin
  newPen := nil; newBrush := nil; oldBrush := nil;
  w := pen.Width;
  if w < 1 then w := 1;
  newPen := CreatePen(0, w, GdiColor(pen.Color));            { PS_SOLID }
  oldPen := SelectObject(dc, newPen);
  if brush <> nil then
  begin
    newBrush := CreateSolidBrush(GdiColor(brush.Color));
    oldBrush := SelectObject(dc, newBrush);
  end
  else
    oldBrush := SelectObject(dc, GetStockObject(5));         { NULL_BRUSH }
end;

procedure GdiRestore(dc: Pointer; oldPen, oldBrush, newPen, newBrush: Pointer);
begin
  SelectObject(dc, oldPen);
  SelectObject(dc, oldBrush);
  if newPen <> nil then DeleteObject(newPen);
  if newBrush <> nil then DeleteObject(newBrush);
end;

procedure TCanvas.ApplyPen; begin end;
procedure TCanvas.ApplyBrush; begin end;
procedure TCanvas.ApplyFont; begin end;

procedure TCanvas.MoveTo(X, Y: Integer);
begin
  if FHandle <> nil then MoveToEx(FHandle, X, Y, nil);
end;

procedure TCanvas.LineTo(X, Y: Integer);
var op, ob, np, nb: Pointer;
begin
  if FHandle = nil then Exit;
  GdiSelect(FHandle, FPen, nil, op, ob, np, nb);
  GdiLineTo(FHandle, X, Y);
  GdiRestore(FHandle, op, ob, np, nb);
end;

procedure TCanvas.Rectangle(X1, Y1, X2, Y2: Integer);
var op, ob, np, nb: Pointer;
begin
  if FHandle = nil then Exit;
  GdiSelect(FHandle, FPen, FBrush, op, ob, np, nb);
  GdiRectangle(FHandle, X1, Y1, X2, Y2);
  GdiRestore(FHandle, op, ob, np, nb);
end;

procedure TCanvas.Ellipse(X1, Y1, X2, Y2: Integer);
var op, ob, np, nb: Pointer;
begin
  if FHandle = nil then Exit;
  GdiSelect(FHandle, FPen, FBrush, op, ob, np, nb);
  GdiEllipse(FHandle, X1, Y1, X2, Y2);
  GdiRestore(FHandle, op, ob, np, nb);
end;

procedure TCanvas.TextOut(X, Y: Integer; const Text: string);
var font, old: Pointer; face, w: array of WideChar; n, i: Integer; fname: string;
begin
  if (FHandle = nil) or (Length(Text) = 0) then Exit;
  fname := FFont.Name;
  SetLength(face, 32);
  for i := 0 to 31 do face[i] := #0;
  for i := 1 to Length(fname) do
    if i <= 31 then face[i - 1] := WideChar(Ord(fname[i]));
  { cairo's font size is the em height in pixels; a negative CreateFont
    height asks GDI for the same }
  font := CreateFontW(-FFont.Size, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 5, 0, @face[0]);   { DEFAULT_CHARSET, CLEARTYPE_QUALITY }
  old := SelectObject(FHandle, font);
  SetBkMode(FHandle, 1);                                     { TRANSPARENT }
  SetTextColor(FHandle, GdiColor(FFont.Color));
  SetTextAlign(FHandle, 24);                                 { TA_BASELINE: as cairo_show_text }
  n := MultiByteToWideChar(65001, 0, PChar(Text), Length(Text), nil, 0);
  SetLength(w, n + 1);
  MultiByteToWideChar(65001, 0, PChar(Text), Length(Text), @w[0], n);
  TextOutW(FHandle, X, Y + FFont.Size, @w[0], n);
  SetTextAlign(FHandle, 0);
  SelectObject(FHandle, old);
  DeleteObject(font);
end;
{$else}
procedure SetCairoColor(cr: Pointer; AColor: TColor);
var r, g, b: Double;
begin
  r := (AColor and $FF) / 255.0;
  g := ((AColor shr 8) and $FF) / 255.0;
  b := ((AColor shr 16) and $FF) / 255.0;
  cairo_set_source_rgb(cr, r, g, b);
end;

procedure TCanvas.ApplyPen;
var w: Double;
begin
  if FHandle <> nil then
  begin
    SetCairoColor(FHandle, FPen.Color);
    w := FPen.Width;
    cairo_set_line_width(FHandle, w);
  end;
end;

procedure TCanvas.ApplyBrush;
begin
  if FHandle <> nil then
  begin
    SetCairoColor(FHandle, FBrush.Color);
  end;
end;

procedure TCanvas.ApplyFont;
var sz: Double;
begin
  if FHandle <> nil then
  begin
    cairo_select_font_face(FHandle, PChar(FFont.Name), 0, 0);
    sz := FFont.Size;
    cairo_set_font_size(FHandle, sz);
  end;
end;

procedure TCanvas.MoveTo(X, Y: Integer);
var dx, dy: Double;
begin
  if FHandle <> nil then
  begin
    dx := X;
    dy := Y;
    cairo_move_to(FHandle, dx, dy);
  end;
end;

procedure TCanvas.LineTo(X, Y: Integer);
var dx, dy: Double;
begin
  if FHandle <> nil then
  begin
    dx := X;
    dy := Y;
    cairo_line_to(FHandle, dx, dy);
    Self.ApplyPen;
    cairo_stroke(FHandle);
    cairo_move_to(FHandle, dx, dy);
  end;
end;

procedure TCanvas.Rectangle(X1, Y1, X2, Y2: Integer);
var dx, dy, dw, dh: Double;
begin
  if FHandle <> nil then
  begin
    dx := X1;
    dy := Y1;
    dw := X2 - X1;
    dh := Y2 - Y1;
    cairo_rectangle(FHandle, dx, dy, dw, dh);
    Self.ApplyBrush;
    cairo_fill_preserve(FHandle);
    Self.ApplyPen;
    cairo_stroke(FHandle);
  end;
end;

procedure TCanvas.Ellipse(X1, Y1, X2, Y2: Integer);
var xc, yc, rx, ry: Double;
begin
  if FHandle <> nil then
  begin
    xc := (X1 + X2) / 2.0;
    yc := (Y1 + Y2) / 2.0;
    rx := (X2 - X1) / 2.0;
    ry := (Y2 - Y1) / 2.0;
    
    cairo_save(FHandle);
    cairo_translate(FHandle, xc, yc);
    cairo_scale(FHandle, rx, ry);
    cairo_arc(FHandle, 0.0, 0.0, 1.0, 0.0, 2.0 * 3.14159265);
    cairo_restore(FHandle);
    
    Self.ApplyBrush;
    cairo_fill_preserve(FHandle);
    Self.ApplyPen;
    cairo_stroke(FHandle);
  end;
end;

procedure TCanvas.TextOut(X, Y: Integer; const Text: string);
var dx, dy: Double;
begin
  if FHandle <> nil then
  begin
    Self.ApplyFont;
    dx := X;
    dy := Y + FFont.Size;
    cairo_move_to(FHandle, dx, dy);
    SetCairoColor(FHandle, FFont.Color);
    cairo_show_text(FHandle, PChar(Text));
  end;
end;
{$endif}

type
  PLongWord = ^LongWord;

constructor TBitmap.Create;
begin
  FWidth := 0;
  FHeight := 0;
  FSurface := nil;
  FData := nil;
end;

{$ifdef PXX_OS_WINDOWS}
destructor TBitmap.Destroy;
begin
  if FSurface <> nil then DeleteObject(FSurface);
end;

procedure TBitmap.RecreateSurface;
var bmi: TBitmapInfo32; bits: Pointer;
begin
  if FSurface <> nil then
  begin
    DeleteObject(FSurface);
    FSurface := nil;
    FData := nil;
  end;
  if (FWidth > 0) and (FHeight > 0) then
  begin
    FillChar(bmi, SizeOf(bmi), 0);
    bmi.biSize := 40;
    bmi.biWidth := FWidth;
    bmi.biHeight := -FHeight;                                { top-down, as cairo }
    bmi.biPlanes := 1;
    bmi.biBitCount := 32;
    bits := nil;
    FSurface := CreateDIBSection(nil, bmi, 0, bits, nil, 0);
    if FSurface <> nil then FData := bits;
  end;
end;
{$else}
destructor TBitmap.Destroy;
begin
  if FSurface <> nil then
    cairo_surface_destroy(FSurface);
end;

procedure TBitmap.RecreateSurface;
begin
  if FSurface <> nil then
  begin
    cairo_surface_destroy(FSurface);
    FSurface := nil;
    FData := nil;
  end;
  if (FWidth > 0) and (FHeight > 0) then
  begin
    FSurface := cairo_image_surface_create(CAIRO_FORMAT_ARGB32, FWidth, FHeight);
    if FSurface <> nil then
      FData := cairo_image_surface_get_data(FSurface);
  end;
end;
{$endif}

procedure TBitmap.SetWidth(v: Integer);
begin
  if FWidth <> v then
  begin
    FWidth := v;
    Self.RecreateSurface;
  end;
end;

procedure TBitmap.SetHeight(v: Integer);
begin
  if FHeight <> v then
  begin
    FHeight := v;
    Self.RecreateSurface;
  end;
end;

procedure TBitmap.Clear(Color: TColor);
var
  i, count: Integer;
  p: PLongWord;
  val: LongWord;
begin
  if FData = nil then Exit;
  count := FWidth * FHeight;
  val := ($FF shl 24) or ((Color and $FF) shl 16) or (((Color shr 8) and $FF) shl 8) or ((Color shr 16) and $FF);
  p := PLongWord(FData);
  for i := 0 to count - 1 do
  begin
    PLongWord(Pointer(Int64(p) + i * 4))^ := val;
  end;
end;

procedure TBitmap.SetPixel(X, Y: Integer; Color: TColor);
var
  p: PLongWord;
  val: LongWord;
begin
  if (X < 0) or (X >= FWidth) or (Y < 0) or (Y >= FHeight) then Exit;
  if FData = nil then Exit;
  p := PLongWord(Pointer(Int64(FData) + (Y * FWidth + X) * 4));
  val := ($FF shl 24) or ((Color and $FF) shl 16) or (((Color shr 8) and $FF) shl 8) or ((Color shr 16) and $FF);
  p^ := val;
end;

function TBitmap.GetPixel(X, Y: Integer): TColor;
var
  p: PLongWord;
  val: LongWord;
begin
  if (X < 0) or (X >= FWidth) or (Y < 0) or (Y >= FHeight) then begin Result := 0; Exit; end;
  if FData = nil then begin Result := 0; Exit; end;
  p := PLongWord(Pointer(Int64(FData) + (Y * FWidth + X) * 4));
  val := p^;
  Result := ((val shr 16) and $FF) or (((val shr 8) and $FF) shl 8) or ((val and $FF) shl 16) or ($FF000000);
end;

{$ifdef PXX_OS_WINDOWS}
procedure TCanvas.Draw(X, Y: Integer; Bitmap: TBitmap);
var mem, old: Pointer;
begin
  if (FHandle <> nil) and (Bitmap <> nil) and (Bitmap.Handle <> nil) then
  begin
    mem := CreateCompatibleDC(FHandle);
    old := SelectObject(mem, Bitmap.Handle);
    BitBlt(FHandle, X, Y, Bitmap.Width, Bitmap.Height, mem, 0, 0, $00CC0020);   { SRCCOPY }
    SelectObject(mem, old);
    DeleteDC(mem);
  end;
end;
{$else}
procedure TCanvas.Draw(X, Y: Integer; Bitmap: TBitmap);
var
  dx, dy: Double;
begin
  if (FHandle <> nil) and (Bitmap <> nil) and (Bitmap.Handle <> nil) then
  begin
    dx := X;
    dy := Y;
    cairo_surface_mark_dirty(Bitmap.Handle);
    cairo_save(FHandle);
    cairo_set_source_surface(FHandle, Bitmap.Handle, dx, dy);
    cairo_paint(FHandle);
    cairo_restore(FHandle);
  end;
end;
{$endif}

end.

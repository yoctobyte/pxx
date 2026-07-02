{ SPDX-License-Identifier: Zlib }
unit graphics;

{ PCL Graphics implementation wrapping Cairo drawing contexts. }

interface

uses classes_lite, gtk3_c;

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
    FHandle: Pointer; { cairo_t }
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

type
  PLongWord = ^LongWord;

constructor TBitmap.Create;
begin
  FWidth := 0;
  FHeight := 0;
  FSurface := nil;
  FData := nil;
end;

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

end.

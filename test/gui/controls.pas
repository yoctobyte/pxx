unit controls;

{ LCL-compatible control base classes, bridged to GTK3.

  TControl carries the GTK widget handle and the common geometry/caption
  properties; TWinControl is the windowed-container base (forms, buttons).
  The dialect has no `inherited`, so each concrete control's constructor
  builds its own widget and stores it in FHandle; ApplyCaption is a virtual
  hook each control overrides to push its caption into the right GTK call. }

interface

uses classes_lite, gtk3;

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
    procedure ApplyCaption; virtual;
    procedure Show;
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

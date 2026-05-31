unit stdctrls;

{ LCL-compatible standard controls on GTK3. Slice 1: TButton. }

interface

uses controls, gtk3;

type
  TButton = class(TWinControl)
  public
    constructor Create;
    procedure ApplyCaption; override;
  end;

implementation

constructor TButton.Create;
begin
  Self.Handle := gtk_button_new_with_label(PC(''));
end;

procedure TButton.ApplyCaption;
var h: Pointer; s: string;
begin
  h := Self.Handle;
  s := Self.Caption;
  gtk_button_set_label(h, PC(s));
end;

end.

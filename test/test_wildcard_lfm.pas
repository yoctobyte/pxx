program test_wildcard_lfm;

{ Feature 3: the *.lfm wildcard R-directive resolves to this unit's base .lfm,
  and the resource name is derived from the .lfm root object class (TWForm). }

uses typinfo, streams, classes_lite, resources, lfm;

{$R *.lfm}

type
  TWForm = class(TComponent)
  private
    FCaption: string;
    FWidth: Integer;
  public
    constructor Create;
  published
    property Caption: string read FCaption write FCaption;
    property Width: Integer read FWidth write FWidth;
  end;

constructor TWForm.Create;
begin
  InitInheritedComponent(Self, 'TWForm');
end;

var form: TWForm;
begin
  form := TWForm.Create;
  writeln('Caption=', form.Caption);
  writeln('Width=', form.Width);
end.

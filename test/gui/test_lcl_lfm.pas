program test_lcl_lfm;

{ Slice 3b: full LFM instantiation. The form's constructor streams an embedded
  .lfm: it sets the form Caption, instantiates the child TButton (GetClass +
  CreateInstance), sets its Caption, and wires OnClick = Btn1Click as a TMethod
  (GetMethodAddr on the form class + the form instance). Realize then builds the
  GTK widgets (CreateInstance never ran constructors), applies captions, and
  parents the button. A synchronous click runs the streamed handler. }

uses typinfo, classes_lite, resources, lfm, gtk3, controls, stdctrls, forms;

{$R TMainForm test_lcl_lfm.lfm}

type
  TMainForm = class(TForm)
    count: Integer;
    constructor Create;
  published
    procedure Btn1Click(Sender: TObject);
  end;

constructor TMainForm.Create;
begin
  Self.HandleNeeded;                          { build the window }
  InitInheritedComponent(Self, 'TMainForm');  { stream caption + child + event }
end;

procedure TMainForm.Btn1Click(Sender: TObject);
begin
  Self.count := Self.count + 1;
  writeln('lfm click! count=', Self.count);
end;

var
  Form1: TMainForm;
  btn: TComponent;
  bc: TControl;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TMainForm.Create;
  writeln('streamed Caption=', Form1.Caption);
  writeln('childCount=', Form1.ChildCount);

  Form1.Realize;

  btn := Form1.FindChild('Btn1');
  if btn = nil then begin writeln('FAIL: no Btn1'); Halt(1); end;
  bc := btn;
  writeln('btn Caption=', bc.Caption);

  gtk_button_clicked(bc.Handle);
  gtk_button_clicked(bc.Handle);

  writeln('total clicks=', Form1.count);
end.

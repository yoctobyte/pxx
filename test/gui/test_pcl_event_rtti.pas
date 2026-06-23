program test_pcl_event_rtti;

{ Slice 3a: wire a form method to a button's OnClick through the RTTI path --
  the exact calls the LFM reader makes (GetClass, GetMethodAddr, GetPropInfo,
  SetMethodProp). Proves the widgetset's published OnClick is streaming-ready.
  A TForm subclass inherits TForm.Create (window) via parent method lookup;
  its published BtnClick handler is found in RTTI. Fires synchronously twice. }

uses typinfo, classes_lite, gtk3, controls, stdctrls, forms;

type
  TMyForm = class(TForm)
    count: Integer;
  published
    procedure BtnClick(Sender: TObject);
  end;

procedure TMyForm.BtnClick(Sender: TObject);
begin
  Self.count := Self.count + 1;
  writeln('rtti-wired click! count=', Self.count);
end;

var
  Form1: TMyForm;
  Btn: TButton;
  m: TMethod;
  fCls, ctlCls: PClassRTTI;
  p: PPropInfo;
  fp, bp: Pointer;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TMyForm.Create(nil);
  Form1.Caption := 'RTTI event';

  Btn := TButton.Create(nil);
  Btn.Caption := 'Click';
  Btn.Parent := Form1;

  { Wire OnClick exactly as the LFM streamer would. }
  fCls := GetClass('TMyForm');
  m.Code := GetMethodAddr(fCls, 'BtnClick');
  fp := Form1;
  m.Data := fp;

  ctlCls := GetClass('TControl');
  p := GetPropInfo(ctlCls, 'OnClick');
  bp := Btn;
  SetMethodProp(bp, p, m);

  gtk_button_clicked(Btn.Handle);
  gtk_button_clicked(Btn.Handle);

  writeln('done, count=', Form1.count);
end.

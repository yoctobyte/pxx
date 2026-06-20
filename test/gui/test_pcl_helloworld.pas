program test_pcl_helloworld;

{ End-to-end of the PCL final mile, mirroring the stock Lazarus helloworld but
  self-terminating: Application.CreateForm instantiates TForm1 from a metaclass
  and streams its *.lfm; a timeout synthesises a button click (firing the
  streamed OnClick -> ShowMessage), a second timeout dismisses the dialog and
  quits. Proves metaclass + initialization + wildcard $R + ShowMessage together. }

uses interfaces, forms, controls, stdctrls, dialogs, classes_lite, typinfo, lfm, gtk3;

{$R *.lfm}

type
  TForm1 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  end;

var
  Form1: TForm1;
  clicks: Integer;

procedure TForm1.Button1Click(Sender: TObject);
begin
  clicks := clicks + 1;
  writeln('Button1Click -> ShowMessage');
  ShowMessage('Hello World');
end;

function ClickCB(data: Pointer): Integer; cdecl;
var h: Pointer;
begin
  { Reach the streamed button through the published FIELD (not FindChild),
    proving the streamer wired the child into TForm1.Button1. }
  if Form1.Button1 = nil then
    writeln('FAIL: Button1 field nil')
  else
  begin
    h := Form1.Button1.Handle;
    gtk_button_clicked(h);          { fires OnClick -> ShowMessage (blocks) }
  end;
  ClickCB := 0;
end;

function DismissCB(data: Pointer): Integer; cdecl;
begin
  DismissActiveDialog;              { close the ShowMessage dialog }
  gtk_main_quit;
  DismissCB := 0;
end;

begin
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  g_timeout_add(300, @ClickCB, nil);
  g_timeout_add(900, @DismissCB, nil);
  Application.Run;
  writeln('clicks=', clicks);
end.

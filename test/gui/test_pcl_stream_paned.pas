program test_pcl_stream_paned;

{ De-risk for feature-eliah-from-lfm: prove a DEEP nested TPaned tree streams from
  a .lfm and Realizes into the right gtk layout. The form has a toolbar button +
  a horizontal RootPaned -> [ vertical ColLeft -> BtnA / BtnB | Editor ]. If this
  renders, Eliah's whole splitter shell can be data-driven the same way.

  --smoke: stream + Realize, verify the tree + streamed TPaned props, print results.
  (no arg): also show the window so tools/gui_shot.sh can screenshot it.
  Needs a display (widget ctors build gtk handles) — run on Xvfb. }

uses typinfo, classes_lite, resources, lfm, gtk3, controls, stdctrls, extctrls,
  forms, sysutils;

function YN(b: Boolean): AnsiString; begin if b then YN := 'T' else YN := 'F'; end;

{$R TStreamPanedForm test_pcl_stream_paned.lfm}

type
  TStreamPanedForm = class(TForm)
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TStreamPanedForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Self.HandleNeeded;
  InitInheritedComponent(Self, 'TStreamPanedForm');
end;

var
  Form1: TStreamPanedForm;
  rp, cl: TPaned;
  show: Boolean;
begin
  { default: stream + verify + exit (gui_suite checks exit code). --show: also
    raise the window for a gui_shot screenshot. }
  show := (ParamCount >= 1) and (ParamStr(1) = '--show');

  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TStreamPanedForm.Create(nil);
  if Form1.ChildCount <> 2 then begin writeln('FAIL: form childCount'); Halt(1); end;
  rp := TPaned(Form1.FindChild('RootPaned'));
  if rp = nil then begin writeln('FAIL: no RootPaned'); Halt(1); end;
  cl := TPaned(rp.FindChild('ColLeft'));
  if cl = nil then begin writeln('FAIL: no ColLeft'); Halt(1); end;

  { single-string diagnostics (multi-arg writeln does not flush before Halt here) }
  writeln('DIAG root.Vert=' + YN(rp.Vertical) + ' root.Pos=' + IntToStr(rp.Position) +
    ' cl.Vert=' + YN(cl.Vertical) + ' cl.Pos=' + IntToStr(cl.Position) +
    ' cl.kids=' + IntToStr(cl.ChildCount));

  if rp.FindChild('Editor') = nil then begin writeln('FAIL: no Editor'); Halt(1); end;
  if rp.Vertical then begin writeln('FAIL: RootPaned should be horizontal'); Halt(1); end;
  if rp.Position <> 200 then begin writeln('FAIL: RootPaned.Position not streamed'); Halt(1); end;
  if not cl.Vertical then begin writeln('FAIL: ColLeft.Vertical not streamed'); Halt(1); end;

  writeln('STREAM PANED OK');

  Form1.Realize;
  if show then
  begin
    WidgetSet.ShowWidget(Form1);
    Application.Run;
  end;
end.

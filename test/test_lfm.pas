program test_lfm;

{ Phase 5 end-to-end: an embedded .lfm text is converted to TPF0 in memory and
  streamed into a component tree at TMyForm.Create time. Asserts the root's
  published props and a streamed child component's props. No GUI. }

uses typinfo, streams, classes_lite, resources, lfm;

{$R TMyForm test_lfm_form.lfm}

type
  TAlign      = (alNone, alTop, alClient);
  TAnchorKind = (akTop, akLeft, akRight, akBottom);
  TAnchors    = set of TAnchorKind;

  TButton = class(TComponent)
  private
    FCaption: string;
    FTag:     Integer;
  published
    property Caption: string  read FCaption write FCaption;
    property Tag:     Integer read FTag     write FTag;
  end;

  TMyForm = class(TComponent)
  private
    FCaption: string;
    FWidth:   Integer;
    FAlign:   TAlign;
    FAnchors: TAnchors;
  public
    constructor Create;
  published
    property Caption: string   read FCaption write FCaption;
    property Width:   Integer  read FWidth   write FWidth;
    property Align:   TAlign   read FAlign   write FAlign;
    property Anchors: TAnchors read FAnchors write FAnchors;
  end;

constructor TMyForm.Create;
begin
  InitInheritedComponent(Self, 'TMyForm');
end;

var
  form:   TMyForm;
  btn:    TComponent;
  bc:     PClassRTTI;
  fc:     PClassRTTI;
  pCap:   PPropInfo;
  pTag:   PPropInfo;
  pAlign: PPropInfo;
  pAnch:  PPropInfo;

begin
  form := TMyForm.Create;
  fc := GetClass('TMyForm');

  writeln('Caption=', form.Caption);
  writeln('Width=', form.Width);
  pAlign := GetPropInfo(fc, 'Align');
  pAnch  := GetPropInfo(fc, 'Anchors');
  writeln('Align=', GetOrdProp(Pointer(form), pAlign));     { alClient = 2 }
  writeln('Anchors=', GetOrdProp(Pointer(form), pAnch));    { akLeft|akBottom = 2+8 = 10 }
  writeln('childCount=', form.ChildCount);

  btn := form.FindChild('Btn');
  if btn = nil then begin writeln('FAIL: no child Btn'); Halt(1); end;
  writeln('btn.Name=', btn.Name);

  bc := GetClass('TButton');
  pCap := GetPropInfo(bc, 'Caption');
  pTag := GetPropInfo(bc, 'Tag');
  writeln('btn.Caption=', GetStrProp(Pointer(btn), pCap));
  writeln('btn.Tag=', GetOrdProp(Pointer(btn), pTag));
end.

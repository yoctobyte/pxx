program test_metaclass_getclass;

{ Metaclass construction through a GetClass result + inline cast —
  `TBaseClass(GetClass(name)).Create(args)` (the streamer's shape). The
  constructed instance must carry the CANONICAL class VMT (cls^.VMTPtr), so
  virtual dispatch and RTTI identity work, not just the ctor body running.
  Regression for bug-metaclass-new-getclass-vmt. }

uses typinfo;

type
  PP = ^Pointer;
  TBase = class
    tag: Integer;
    constructor Create(n: Integer); virtual;
    function Kind: string; virtual;
  published
    property Tag: Integer read tag write tag;
  end;
  TDer = class(TBase)
    constructor Create(n: Integer); override;
    function Kind: string; override;
  end;
  TBaseClass = class of TBase;

constructor TBase.Create(n: Integer); begin tag := n; end;
function TBase.Kind: string; begin Kind := 'base'; end;
constructor TDer.Create(n: Integer); begin inherited Create(n); tag := n * 10; end;
function TDer.Kind: string; begin Kind := 'der'; end;

var clsB, clsD: PClassRTTI; o: TBase;
begin
  clsB := GetClass('TBase');
  clsD := GetClass('TDer');

  o := TBaseClass(clsB).Create(3);
  writeln(o.tag, ' ', o.Kind, ' ', PP(o)^ = clsB^.VMTPtr);   { 3 base TRUE }

  o := TBaseClass(clsD).Create(4);
  writeln(o.tag, ' ', o.Kind, ' ', PP(o)^ = clsD^.VMTPtr);   { 40 der TRUE }
end.

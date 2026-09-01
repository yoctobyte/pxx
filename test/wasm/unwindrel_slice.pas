program unwindrel_slice;
{ Managed locals owned by a frame an exception unwinds THROUGH.

  A SEPARATE SLICE FROM scopeexit_slice ON PURPOSE. That one covers the ordinary
  path: a procedure returns normally and its epilogue releases. This one covers
  the path where the epilogue never runs at all -- `Middle` neither catches the
  exception nor returns, so neither its own epilogue nor the eventual handler's
  frame releases what it owned. Only a PROC CLEANUP FRAME can, and wasm32 had
  none. Two mechanisms in one probe would be one assertion wearing two names,
  and the mechanism that broke second would never be tested.

  Measured before the fix (node host): `made=20 gone=0`, and the shadow stack
  ended 16 bytes low. After: `gone=20` and $sp exactly balanced, which is what
  x86-64 says.

  bug-a-managed-locals-leak-on-an-unwind-on-wasm32-and-xtensa }
type
  IThing = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Poke;
  end;
var Made, Gone: Integer;
type
  TThing = class(TInterfacedObject, IThing)
    procedure Poke;
    destructor Destroy; override;
  end;
procedure TThing.Poke; begin end;
destructor TThing.Destroy; begin Inc(Gone); inherited Destroy; end;

procedure Deep;
begin
  raise 11;
end;

procedure Middle;          { owns a managed local; does NOT catch }
var t: IThing;
begin
  t := TThing.Create;
  Inc(Made);
  t.Poke;
  Deep;                    { unwinds THROUGH this frame }
  WriteLn('FAIL: Deep returned');
end;

var i: Integer;
begin
  Made := 0; Gone := 0;
  for i := 1 to 20 do
    try Middle; except end;
  WriteLn('made=', Made, ' gone=', Gone);
  if Gone <> Made then begin WriteLn('LEAK: ', Made - Gone, ' not released on unwind'); Halt(1); end;
  WriteLn('UNWIND RELEASE OK');
end.

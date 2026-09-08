{ An interface type name used as a VALUE means its GUID, and nothing else. That
  worked in a statement and was wrong in every DECLARATION spelling:

    var  g: TGUID = ICom   accepted and stored an ADDRESS (0x00410BD8) --
                           the interface is a class type, so the metaclass arm
                           of the var-section initialiser claimed it and baked
                           an AN_CLASSREF VMT address into the first eight bytes
    const g: TGUID = ICom  refused: `expected '(' before 'ICom'`, because a
                           record-typed const goes straight to the parenthesised
                           record-constant parser

  Two paths, two different wrong answers, pointing in OPPOSITE directions. The
  var one is the dangerous half: nothing diagnoses it, the record is the right
  size, and the program runs -- with an interface identity that can never match,
  since TObject.GetInterface looks interfaces up BY GUID at run time.

  THE BYTES ARE THE ASSERTION AND THE STATEMENT ROW IS THE CONTROL. `h := ICom`
  has always been right, so it is printed beside the others: a fixture that only
  checked the declarations would pass if all of them broke the same way. Eight
  bytes are enough to separate them -- 114 171 182 4 is 04B6AB72 little-endian,
  the real GUID, while an address shows as a small number followed by zeros.

  The local rows are here because the routine-local emitter is a SEPARATE
  emitter: FlushLocalInits knew kinds 1/2/4/5/9 and its `else` turns an
  unrecognised kind into an integer literal, so the first version of this fix
  compiled `local: ok` and SIGSEGV'd at run time -- a node index assigned into a
  TGuid. A kind the global emitter knows and the local one does not is not a
  missing feature, it is a wrong value.
  bug-p-an-interface-name-in-a-var-initialiser-stores-the-guids-address-not-the-guid }
program test_interface_name_as_guid_initialiser;
{$mode objfpc}{$H+}
type
  ICom = interface ['{04B6AB72-8F86-45F8-8D49-393E799F51A8}']
  end;
var
  gVar: TGUID = ICom;
const
  gConst: TGUID = ICom;

procedure Dump(const nm: string; const g: TGUID);
var p: PByte; i: Integer;
begin
  p := PByte(@g);
  Write(nm, ':');
  for i := 0 to 7 do Write(' ', p[i]);
  WriteLn;
end;

procedure Locals;
var   lVar: TGUID = ICom;
const lConst: TGUID = ICom;
begin
  Dump('localvar  ', lVar);
  Dump('localconst', lConst);
end;

var h: TGUID;
begin
  h := ICom;                  { the control: this spelling was always correct }
  Dump('statement ', h);
  Dump('globalvar ', gVar);
  Dump('globalcons', gConst);
  Locals;
end.

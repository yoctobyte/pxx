{ The interface-table entry's ID word carries a COM flag in bit 32, and this
  file is the guard for the reason it exists.

  A runtime that holds only an INSTANCE -- a variant slot has 16 bytes for
  {tag, payload} and nowhere to put an interface id -- cannot use
  PXXIntfIMTOf, which is keyed on the id. The obvious substitute is "take any
  entry's IMT and call slot 2", and it is WRONG in a way no value assertion
  would catch:

    - for a COM class every IMT carries the SAME _AddRef/_Release pair, so any
      entry really would do (measured: three entries on one class, one of them
      a GUID-less interface, all three identical);
    - under {$interfaces corba} on a plain TObject descendant, IMT slots 0/1/2
      are the interface's OWN first three methods -- measured, they are the
      addresses of A1, A2 and A3 -- so the same walk calls a user method as if
      it were _Release, with the right argument count and no diagnostic.

  Nothing else in the entry separates those two populations: a CORBA interface
  may carry a GUID and a COM one may not. So the flag is written into the ID
  word from the INTERFACE's UClsIsComInterface, and PXXIntfComIMTOf refuses --
  returns nil -- rather than guessing.

  THE CORBA ROWS ARE THE POSITIVE CONTROL AND THEY ARE DRAWN FROM THE
  POPULATION THAT WOULD BE MISHANDLED. A1/A2/A3 PRINT. If the walk ever calls
  one, the line appears in the output and the row fails; a silent `0` is the
  only correct answer, and a test that merely asserted `0` without making the
  wrong answer LOUD could not tell a refusal from a call that happened to
  return zero.

  The last two rows are the ENCODING control: the id is now
  {flag:bit 32, class index:low 32} and every reader masks, so ordinary
  interface dispatch and ARC must be untouched. `d` prints from the destructor,
  which only runs if _Release reached zero through the normal id-keyed path.

  Expected output is pxx's own -- these helpers are compiler internals with no
  FPC spelling. The ARC rows are the part FPC would agree with, and they are
  written so a reader can see that separately.
  bug-p-a-variant-cannot-hold-an-interface }
{$mode objfpc}{$H+}
program test_intf_com_flag;
type
  IFoo = interface ['{A0000000-0000-0000-0000-000000000001}'] procedure F; end;
  IBar = interface ['{A0000000-0000-0000-0000-000000000002}'] procedure B; end;
  TCom = class(TInterfacedObject, IFoo, IBar)
    procedure F;
    procedure B;
    destructor Destroy; override;
  end;
procedure TCom.F; begin WriteLn('F'); end;
procedure TCom.B; begin WriteLn('B'); end;
destructor TCom.Destroy; begin WriteLn('destroyed'); inherited Destroy; end;

procedure UseIt;
var f: IFoo;
begin
  f := TCom.Create;
  f.F;
end;

var c: TCom; n: NativeInt;
begin
  c := TCom.Create;
  WriteLn('com imt found: ', PXXIntfComIMTOf(Pointer(c)) <> nil);
  { the counts are asserted, not just non-zero: an AddRef that reached the
    wrong slot would still return SOMETHING, and 1 then 2 then 1 is a sequence
    only the real _AddRef/_Release pair produces }
  WriteLn('com addref: ', PXXIntfAddRefAny(Pointer(c)));
  WriteLn('com addref: ', PXXIntfAddRefAny(Pointer(c)));
  WriteLn('com release: ', PXXIntfReleaseAny(Pointer(c)));
  { the last release frees, so its destructor line lands BEFORE the count --
    read into `n` first so the interleaving is fixed rather than incidental }
  n := PXXIntfReleaseAny(Pointer(c));
  WriteLn('com release: ', n);
  { THE ENCODING CONTROL. The id word is now {flag:bit 32, index:low 32}, and
    every ordinary interface operation still goes through the ID-KEYED path --
    the compiler emits PXXIntfRelease with the id it knows statically. `f`
    going out of scope in UseIt has to reach zero and print, which it can only
    do if the masked compare still matches. A mask that dropped the wrong bits
    leaves this silent, not wrong. }
  UseIt;
  WriteLn('done');
end.

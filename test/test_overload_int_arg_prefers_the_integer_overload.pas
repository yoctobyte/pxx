program test_overload_int_arg_prefers_the_integer_overload;
{ An INTEGER argument, and a same-arity overload pair where the OTHER parameter
  is not a number. The integer overload must win, whichever is declared first.

  WHAT WENT WRONG, AND WHY IT LOOKED LIKE SIX BUGS. OverloadArgRank's
  "numeric widening" arm asked TypeIsOrdinal, which admits tyPointer and
  tyBoolean, so an integer argument scored rank 1 -- a PREFERRED conversion --
  against a parameter that is not a number at all. That TIED with the genuine
  widening onto the integer overload, and a tie is broken by declaration order.
  So the answer depended on which line came first, and the reported symptom was
  whichever spelling the reporter happened to use.

  THE NON-INTEGER PARAMETER IS DECLARED FIRST IN EVERY PAIR. That is the whole
  design of this fixture: with the integer overload first the bug is invisible,
  because the tie resolves to it by accident. The DeclarationOrder rows below
  are the control that says so -- they are the same calls with the pair
  reversed, and they must answer the same.

  THE ARGUMENT IS AN `Integer` VARIABLE, NOT A `LongInt` ONE. A LongInt argument
  is an EXACT match for the LongInt parameter (rank 0) and already won before
  the fix, so it cannot see this defect. The ExactMatch rows keep that case
  visible as the second control.

  fpc 3.2.2 answers the integer overload on every row, and .expected is its
  output byte for byte.
  bug-p-an-integer-argument-binds-a-procedural-overload-over-an-exact-integer-one }
{$mode objfpc}{$H+}
type
  TCmp = function(a, b: Pointer): Integer;

  TC = class
    { the non-integer parameter FIRST in every pair }
    procedure ViaPointer(x: Pointer);   overload;
    procedure ViaPointer(n: LongInt);   overload;
    procedure ViaProc(c: TCmp);         overload;
    procedure ViaProc(n: LongInt);      overload;
    procedure ViaPChar(p: PChar);       overload;
    procedure ViaPChar(n: LongInt);     overload;
    procedure ViaBool(b: Boolean);      overload;
    procedure ViaBool(n: LongInt);      overload;
    procedure ViaWide(w: WideChar);     overload;
    procedure ViaWide(n: LongInt);      overload;
    procedure ViaUcs(u: UCS4Char);      overload;
    procedure ViaUcs(n: LongInt);       overload;
    { CONTROL: the integer one first -- must answer the same }
    procedure Rev(n: LongInt);          overload;
    procedure Rev(x: Pointer);          overload;
    { CONTROL: a Char parameter, which the arm has always excluded, so a
      character argument still prefers the string overload }
    procedure Ch(s: string);            overload;
    procedure Ch(n: LongInt);           overload;
  end;

procedure TC.ViaPointer(x: Pointer); begin WriteLn('pointer'); end;
procedure TC.ViaPointer(n: LongInt); begin WriteLn('int ', n); end;
procedure TC.ViaProc(c: TCmp);       begin WriteLn('proc'); end;
procedure TC.ViaProc(n: LongInt);    begin WriteLn('int ', n); end;
procedure TC.ViaPChar(p: PChar);     begin WriteLn('pchar'); end;
procedure TC.ViaPChar(n: LongInt);   begin WriteLn('int ', n); end;
procedure TC.ViaBool(b: Boolean);    begin WriteLn('bool'); end;
procedure TC.ViaBool(n: LongInt);    begin WriteLn('int ', n); end;
procedure TC.ViaWide(w: WideChar);   begin WriteLn('widechar'); end;
procedure TC.ViaWide(n: LongInt);    begin WriteLn('int ', n); end;
procedure TC.ViaUcs(u: UCS4Char);    begin WriteLn('ucs4char'); end;
procedure TC.ViaUcs(n: LongInt);     begin WriteLn('int ', n); end;
procedure TC.Rev(n: LongInt);        begin WriteLn('int ', n); end;
procedure TC.Rev(x: Pointer);        begin WriteLn('pointer'); end;
procedure TC.Ch(s: string);          begin WriteLn('string ', s); end;
procedure TC.Ch(n: LongInt);         begin WriteLn('int ', n); end;

var
  o: TC;
  i: Integer;
  k: LongInt;
  c: Char;
begin
  o := TC.Create;
  i := 65;
  k := 65;
  c := 'A';

  WriteLn('-- Integer argument, non-integer parameter declared first');
  o.ViaPointer(i);
  o.ViaProc(i);
  o.ViaPChar(i);
  o.ViaBool(i);
  o.ViaWide(i);
  o.ViaUcs(i);

  WriteLn('-- control: declaration order reversed');
  o.Rev(i);

  WriteLn('-- control: an exact LongInt argument already won');
  o.ViaPointer(k);
  o.ViaProc(k);

  WriteLn('-- control: a Char argument still prefers the string overload');
  o.Ch(c);

  WriteLn('done');
end.

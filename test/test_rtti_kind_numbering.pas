{ The RTTI blob carries the COMPILER's type-kind numbering, not the TTypeKind
  enum declared beside it in typinfo. This pins that contract in both
  directions, because the bug it replaces was a SILENT wrong answer:
  `mi^.RetKind = Ord(tkInt64)` reads as obviously correct and is false (13 vs
  19), and the two numbering spaces overlap on 1, 2, 11, 15, 18 and 19 with
  different meanings, so a wrong comparison can also be accidentally TRUE.

  Rows 1-2 are the ticket's own repro, both spellings.
  Rows 3+ pin PxxKindToTypeKind, including the many-to-one collapses that are
  exactly why the blob does not carry FPC's numbering: Single and Double both
  answer tkFloat, so an ABI selector reading a converted kind could not tell an
  xmm-32 return from an xmm-64 one.
  (bug-a-rtti-kind-numbers-are-the-compilers-not-the-typinfo-enum-the-unit-documents) }
program test_rtti_kind_numbering;

uses typinfo;

type
  TShapes = class
    B: Byte;
    I: Int64;
    S: AnsiString;
    function RetI64(x: Int64): Int64;
    function RetBool: Boolean;
    function RetDbl: Double;
    function RetStr: AnsiString;
    procedure NoRet;
  end;

function TShapes.RetI64(x: Int64): Int64;  begin RetI64 := x; end;
function TShapes.RetBool: Boolean;         begin RetBool := True; end;
function TShapes.RetDbl: Double;           begin RetDbl := 1.5; end;
function TShapes.RetStr: AnsiString;       begin RetStr := 'x'; end;
procedure TShapes.NoRet;                   begin B := 0; end;

var
  cls: PClassRTTI;
  mi: PMethInfo;
  fi: PFieldInfo;

procedure Show(const what: string; raw: Int64);
begin
  writeln(what, ' raw=', raw, ' asFPC=', PxxKindToTypeKind(raw));
end;

begin
  cls := GetClass('TShapes');
  if cls = nil then begin writeln('no RTTI'); Halt(1); end;

  { --- the ticket's repro, both spellings --- }
  mi := GetMethInfoByName(cls, 'RetI64');
  writeln('RetI64 = Ord(tkInt64)?      ', mi^.RetKind = Ord(tkInt64));
  writeln('RetI64 = pxxTkInt64?        ', mi^.RetKind = pxxTkInt64);
  writeln('RetI64 converted = tkInt64? ', PxxKindToTypeKind(mi^.RetKind) = Ord(tkInt64));

  { --- return kinds --- }
  Show('RetI64 ', GetMethInfoByName(cls, 'RetI64')^.RetKind);
  Show('RetBool', GetMethInfoByName(cls, 'RetBool')^.RetKind);
  Show('RetDbl ', GetMethInfoByName(cls, 'RetDbl')^.RetKind);
  Show('RetStr ', GetMethInfoByName(cls, 'RetStr')^.RetKind);
  writeln('NoRet raw=', GetMethInfoByName(cls, 'NoRet')^.RetKind, ' (0 = procedure)');

  { --- field kinds --- }
  fi := GetFieldInfoByName(cls, 'B');
  Show('field B', fi^.TypeKind);
  writeln('  width=', TypeKindSize(fi^.TypeKind), ' signed=', TypeKindSigned(fi^.TypeKind));
  fi := GetFieldInfoByName(cls, 'I');
  Show('field I', fi^.TypeKind);
  writeln('  width=', TypeKindSize(fi^.TypeKind), ' signed=', TypeKindSigned(fi^.TypeKind));
  fi := GetFieldInfoByName(cls, 'S');
  Show('field S', fi^.TypeKind);

  { --- the many-to-one collapses, stated as the reason the blob keeps its own
        numbering: after conversion these pairs are indistinguishable --- }
  writeln('Single/Double both tkFloat?   ',
          (PxxKindToTypeKind(pxxTkSingle) = Ord(tkFloat)) and
          (PxxKindToTypeKind(pxxTkDouble) = Ord(tkFloat)));
  writeln('UInt8/Int32 both tkInteger?   ',
          (PxxKindToTypeKind(pxxTkUInt8) = Ord(tkInteger)) and
          (PxxKindToTypeKind(pxxTkInt32) = Ord(tkInteger)));
  writeln('...but widths still differ:   ',
          TypeKindSize(pxxTkUInt8), ' vs ', TypeKindSize(pxxTkInt32));

  { --- the overlap that makes a wrong comparison dangerous rather than merely
        wrong: pxx 15 is NativeInt, FPC 15 is tkClass --- }
  writeln('pxx 15 -> ', PxxKindToTypeKind(15), ' (tkInteger=', Ord(tkInteger),
          '), while Ord(tkClass)=', Ord(tkClass));
end.

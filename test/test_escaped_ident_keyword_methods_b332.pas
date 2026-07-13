{ Delphi-compat name plumbing rtl-generics' defaults unit needs (b332):

  - `&keyword` ESCAPED IDENTIFIERS: '&' before a letter lexes the name as a
    plain identifier with no keyword lookup (`&String`, `&Type`). '&777'
    stays an octal literal.
  - Methods NAMED after built-in type keywords: `class function Integer(...)`
    — the method-name positions (record/class decls, impl headers, TClass.X
    call sites) accept type-keyword tokens; their SVal is empty so names read
    through GetTokenStr.
  - `TFooClass = class of TFoo` BEFORE TFoo's declaration mints a forward
    class row, completed by the real declaration.
  Verified against FPC. }
program test_escaped_ident_keyword_methods_b332;
{$mode objfpc}{$h+}

type
  TLateClass = class of TLate;   { forward via class-of }
  TLate = class
    class function Tag: string; virtual;
  end;

  TCmp = record helper for Integer
    class function &String(A: Integer): Integer; static;
  end;

  TBox = class
    class function Integer(A, B: LongInt): LongInt; static;
  end;

class function TLate.Tag: string;
begin
  Result := 'late';
end;

class function TCmp.&String(A: Integer): Integer;
begin
  Result := A * 2;
end;

class function TBox.Integer(A, B: LongInt): LongInt;
begin
  Result := A + B;
end;

var
  c: TLateClass;
  &type: Integer;              { escaped ident as a variable name }
begin
  c := TLate;
  Writeln('tag=', c.Tag);
  Writeln('esc=', TCmp.&String(21));
  Writeln('kw=', TBox.Integer(2, 3));
  &type := 9;
  Writeln('var=', &type);
  Writeln('oct=', &777);
end.

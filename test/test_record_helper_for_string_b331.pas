{ `record helper for <type>` v1 (b331) — the fcl/rtl-generics shape.

  A type helper's methods dispatch on values of the TARGET type: Self (the
  hidden param 0) is the target BY REFERENCE, exactly like an advanced-record
  method's receiver. v1 scope: instance methods on plain-typed VARIABLES and
  parameters (the shape generics.defaults consumes: `ALeft.ToLower` on a const
  AnsiString param); the last visible helper for a type wins; frozen and
  managed strings are one helper family. Statics/consts in helpers and
  type-name receivers (UInt32.GetSignMask) are follow-ups on the ticket. }
program test_record_helper_for_string_b331;
{$mode objfpc}{$h+}
uses SysUtils;

type
  TStrHelper = record helper for AnsiString
    function ToLower2: AnsiString;
    function Doubled: AnsiString;
    procedure Bang;                { mutates Self through the reference }
  end;
  TIntHelper = record helper for Integer
    function Squared: Integer;
  end;

function TStrHelper.ToLower2: AnsiString;
begin
  Result := LowerCase(Self);
end;

function TStrHelper.Doubled: AnsiString;
begin
  Result := Self + Self;
end;

procedure TStrHelper.Bang;
begin
  Self := Self + '!';
end;

function TIntHelper.Squared: Integer;
begin
  Result := Self * Self;
end;

procedure UseParam(const S: AnsiString);
begin
  Writeln('param: ', S.ToLower2);
end;

var
  s: AnsiString;
  n: Integer;
begin
  s := 'HeLLo';
  Writeln('lower:  ', s.ToLower2);
  Writeln('double: ', s.Doubled);
  s.Bang;
  Writeln('bang:   ', s);
  UseParam('MiXeD');
  n := 7;
  Writeln('sq:     ', n.Squared);
end.

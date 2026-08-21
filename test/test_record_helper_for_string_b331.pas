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
  TU32Helper = record helper for Cardinal
    class function GetSignMask: Cardinal; static; inline;
    const BITS = 32;
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

class function TU32Helper.GetSignMask: Cardinal;
begin
  Result := $80000000;
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
  Writeln('mask:   ', TU32Helper.GetSignMask);   { static via the helper's name }
  { QUALIFIED, not bare. This read was `BITS` until 2026-08-21, with the comment
    "helper const (global scope)" — codifying a leak: an untyped const declared
    inside a helper was registered as an ordinary global, so its name was
    visible everywhere. FPC 3.2.2 refuses the bare form
    (`Identifier not found "BITS"`, measured), and ee388cf3a closed the leak as
    a side effect of giving typed class/record consts their own backing symbol.
    The test went red asserting the old behaviour, so the assertion moved to
    what FPC actually does. bug-a-a-units-mode-directive-... is the sibling
    story: the commit that exposes a divergence is not the one that caused it. }
  Writeln('bits:   ', TU32Helper.BITS);          { helper const, qualified by its owner }
end.

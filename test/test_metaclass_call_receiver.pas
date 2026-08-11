{$mode objfpc}{$H+}
{ A metaclass returned from a FUNCTION used as a receiver: `Give.Kind`,
  `Give.ClassName`, `Give.Create`.

  The fifth spelling of "this value is a metaclass", and the one nobody added:
  a call result never reached the receiver list at all. ApplyCallResultPtrSuffix
  saw a typed-pointer return and walked `.Kind` with the record-FIELD builder,
  so lowering answered

      IR_UNSUPPORTED: frontend could not lower AST node (kind 8)

  — an internal message, not a diagnostic. The other four spellings (variable,
  cast, array element, field) had each been added one ticket at a time as four
  copies of the same test; they now share one predicate, NodeMetaclassCi, and
  the controls below are those four still working.

  Every row diffed against FPC.
  bug-a-a-metaclass-returned-from-a-function-is-not-a-receiver }
program test_metaclass_call_receiver;
type
  TBase = class
    class function Kind: string; virtual;
    constructor Create; virtual;
  end;
  TDer = class(TBase)
    class function Kind: string; override;
    constructor Create; override;
  end;
  TBaseClass = class of TBase;

var built: string;

class function TBase.Kind: string; begin Result := 'base'; end;
class function TDer.Kind: string;  begin Result := 'der'; end;
constructor TBase.Create; begin inherited Create; built := built + 'B'; end;
constructor TDer.Create;  begin inherited Create; built := built + 'D'; end;

function Give: TBaseClass; begin Result := TDer; end;
function GiveBase: TBaseClass; begin Result := TBase; end;
function Pick(which: Integer): TBaseClass;
begin if which = 0 then Pick := TBase else Pick := TDer; end;

var
  v: TBaseClass;
  arr: array[0..1] of TBaseClass;
  o: TBase;
begin
  { the controls: spellings that already worked }
  v := TDer;      WriteLn('var     ', v.Kind, ' ', v.ClassName);
  arr[0] := TDer; WriteLn('element ', arr[0].Kind);

  { the bug: the same value reached through a CALL }
  WriteLn('call    ', Give.Kind, ' ', Give.ClassName);
  WriteLn('base    ', GiveBase.Kind);
  WriteLn('args    ', Pick(0).Kind, ' ', Pick(1).Kind);

  { construction through a call result dispatches the VIRTUAL constructor }
  built := '';
  o := Give.Create;
  o.Free;
  o := GiveBase.Create;
  o.Free;
  WriteLn('ctor    ', built);
  WriteLn('METACLASS CALL RECEIVER OK');
end.

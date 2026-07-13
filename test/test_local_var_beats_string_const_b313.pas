{ A VARIABLE in scope must beat an untyped string CONSTANT of the same name.

  pxx's string-constant table is not scoped: a `const S = 'text';` declared inside one
  method stays visible to every later one. ParseFactor expanded any identifier naming a
  string constant straight into an AN_STR_LIT -- without first checking whether a
  variable of that name was in scope. So a later method's local `var S : TSomeClass` was
  silently replaced by the CONSTANT'S TEXT: the identifier was consumed, a string literal
  was handed back, and the following `.Method` was left unconsumed. The error then landed
  on the selector ("expected ,") rather than on the name that had just been mis-resolved,
  which is what made it look like a member-access bug.

  DECL-ORDER dependent by construction, so it only bites in a real unit: the const must be
  declared before the method that uses the variable. Found in fcl-json's testjsondata.pp
  (feature-pascal-corpus-fpjson), which does exactly this with `S`.

  Pascal scoping says the innermost declaration wins, and the local var IS innermost. }
program test_local_var_beats_string_const_b313;
{$mode objfpc}{$H+}

type
  TBox = class
  private
    FText: string;
  public
    constructor Create(const AText: string);
    function Describe: string;
    property Text: string read FText;
  end;

constructor TBox.Create(const AText: string);
begin
  FText := AText;
end;

function TBox.Describe: string;
begin
  Describe := '[' + FText + ']';
end;

{ Declares a local CONST named S. Nothing here is wrong; it is the leak that was. }
function UsesConstS: string;
const
  S = 'from the const';
begin
  UsesConstS := S;
end;

{ ...and now a LOCAL VAR with the same name, in a LATER routine. This must be the
  variable, and a selector on it must parse. }
function UsesVarS: string;
var
  S: TBox;
begin
  S := TBox.Create('from the var');
  UsesVarS := S.Describe + ' / ' + S.Text;
  S.Free;
end;

{ the same shape, with the var passed as an argument (the path that first showed it:
  the selector was left unconsumed and the arg list reported "expected ,") }
function Join(const A, B: string): string;
begin
  Join := A + '|' + B;
end;

function UsesVarSAsArg: string;
var
  S: TBox;
begin
  S := TBox.Create('arg');
  UsesVarSAsArg := Join(S.Describe, S.Text);
  S.Free;
end;

var
  S: TBox;   { and at program scope, too }
begin
  writeln(UsesConstS);
  writeln(UsesVarS);
  writeln(UsesVarSAsArg);
  S := TBox.Create('global');
  writeln(S.Describe);
  S.Free;
end.

program test_class_name_receiver_chain;
{ A selector chained onto a class function reached through a bare CLASS NAME
  must be applied, not dropped. `TFactory.MakeC.Tag` used to evaluate to the
  INTERMEDIATE result — the object pointer — because both arms that build a
  `TClassName.ClassMethod(...)` call returned it without applying the tail, and
  the leftover `.Tag` was then eaten by ParseStatementAST's catch-all
  skip-to-';'. The call ran, the chained call vanished, exit 0.

  Two arms, two entries, one bug: ParseFactorCore (pasparser_expr.inc) serves
  EXPRESSION position and ParseLValueAST (pasparser_lval.inc) serves STATEMENT
  position. Fixing either alone leaves the other silently wrong, which is why
  both spellings are exercised here.
  bug-p-a-call-chained-onto-a-class-method-result-is-dropped
  Sibling of bug-p-a-class-method-call-keeps-the-receivers-class. }
{$MODE OBJFPC}
type
  TRec = record a, b: Integer; end;
  TSvc = class
    Tag: Integer;                       { a FIELD tail                    }
    function Inst(x: Integer): Integer; { a method tail with an argument  }
    function NoArg: Integer;            { a parameterless method tail     }
    function Self2: TSvc;               { to chain a second step onto     }
    procedure Bump;                     { for STATEMENT position          }
  end;
  TFactory = class
    class var Seen: Integer;
    class function MakeC: TSvc;         { CLASS function returning TSvc   }
    class function MakeR: TRec;         { ...and one returning a RECORD   }
    class function Plain: Integer;      { no tail at all — must not break }
  end;

function TSvc.Inst(x: Integer): Integer;
begin Inst := x * 3; end;

function TSvc.NoArg: Integer;
begin NoArg := 7; end;

function TSvc.Self2: TSvc;
begin Self2 := Self; end;

procedure TSvc.Bump;
begin TFactory.Seen := TFactory.Seen + 1; end;

class function TFactory.MakeC: TSvc;
begin MakeC := TSvc.Create; MakeC.Tag := 99; end;

class function TFactory.MakeR: TRec;
begin MakeR.a := 11; MakeR.b := 22; end;

class function TFactory.Plain: Integer;
begin Plain := 5; end;

var
  s: TSvc;
begin
  { EXPRESSION position — ParseFactorCore's arm }
  Writeln('meth(arg) : ', TFactory.MakeC.Inst(14));
  Writeln('meth      : ', TFactory.MakeC.NoArg);
  Writeln('field     : ', TFactory.MakeC.Tag);
  Writeln('deep      : ', TFactory.MakeC.Self2.Inst(4));
  Writeln('record    : ', TFactory.MakeR.b);
  Writeln('in expr   : ', TFactory.MakeC.Inst(2) + TFactory.MakeC.Inst(3));

  { no tail at all, and the parenthesised spelling that always worked — a fix
    must not trade one for the other }
  Writeln('no tail   : ', TFactory.Plain);
  Writeln('parens    : ', (TFactory.MakeC).Inst(14));

  { the split spelling through a temp var, correct all along }
  s := TFactory.MakeC;
  Writeln('split     : ', s.Inst(14));

  { STATEMENT position — ParseLValueAST's arm. The call must actually RUN;
    when it was dropped this printed 0 with no diagnostic. }
  TFactory.Seen := 0;
  TFactory.MakeC.Bump;
  Writeln('statement : ', TFactory.Seen);
end.

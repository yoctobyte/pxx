{ A `[...]` argument used to turn off type-aware method overload selection
  altogether: FindUMethOverloadAhead cannot PARSE a bracket argument in its
  speculative probe, so it fell back to arity alone and the first-declared
  candidate won.

  DoLog is the shape that makes that silent rather than loud. Both overloads
  accept three explicit arguments -- the plain one because `Skip` has a
  default, the array-of-const one because `Skip` has a default too -- so arity
  cannot separate them, and `['']` bound to `Skip: Boolean` as TRUE. A wrong
  value, no diagnostic. (fcl-passrc's pscanner.pp:3523 is this call.)

  Q is the same question where the sibling parameter is not an array at all,
  and the last row is a NON-bracket call into the same overload set: selection
  there must be exactly what it was.
  bug-p-a-bracket-argument-turns-off-method-overload-selection }
{$mode objfpc}
program test_a_bracket_argument_still_selects_a_method_overload;
type
  TC = class
    procedure DoLog(N: Integer; const Msg: String; Skip: Boolean = False); overload;
    procedure DoLog(N: Integer; const Fmt: String; Args: array of const;
                    Skip: Boolean = False); overload;
    procedure Q(N: Integer; S: String); overload;
    procedure Q(N: Integer; A: array of const); overload;
    procedure Work;
  end;

procedure TC.DoLog(N: Integer; const Msg: String; Skip: Boolean = False);
begin WriteLn('plain n=', N, ' ', Msg, ' skip=', Skip); end;

procedure TC.DoLog(N: Integer; const Fmt: String; Args: array of const;
                   Skip: Boolean = False);
begin WriteLn('varrec n=', N, ' ', Fmt, ' cnt=', Length(Args), ' skip=', Skip); end;

procedure TC.Q(N: Integer; S: String);
begin WriteLn('str n=', N, ' s=', S); end;

procedure TC.Q(N: Integer; A: array of const);
begin WriteLn('qvr n=', N, ' cnt=', Length(A)); end;

{ ...and through the implicit-Self spelling, which reaches the same selector by
  a different door. }
procedure TC.Work;
begin
  DoLog(5, 'selfform', ['a', 'b', 'c']);
  Q(6, ['z']);
end;

var c: TC;
begin
  c := TC.Create;
  c.DoLog(1, 'plainform');
  c.DoLog(2, 'withargs', ['']);
  c.DoLog(3, 'withargs2', ['ab', 'cd']);
  c.Q(4, 'plain');
  c.Work;
end.

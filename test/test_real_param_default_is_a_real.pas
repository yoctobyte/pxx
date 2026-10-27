{ bug-p-a-negative-default-on-a-real-parameter-is-nan

  A real parameter's default went through the ORDINAL constant evaluator unless
  it was written as a real literal, and the call site reads the stored value as
  IEEE bits: `w: Double = -1` arrived as NaN (all-ones bits), `= 3` as a
  denormal, and `= -1.5` did not parse. tkinter.pas's `width: Double = -1`
  sentinel then sent Tk `-width nan` and every canvas outline was invisible.
  Every row below is what fpc 3.2.2 prints. }
program test_real_param_default_is_a_real;

{$mode objfpc}

const C = 2.5;

type
  TK = class(TObject)
  public
    constructor Create;
    function m(const a: AnsiString = ''; w: Double = -1): Double;
  end;

constructor TK.Create; begin end;
function TK.m(const a: AnsiString; w: Double): Double; begin m := w; end;

function g(w: Double = -1): Double; begin g := w; end;
function h(w: Double = -1.5): Double; begin h := w; end;
function i(w: Double = 3): Double; begin i := w; end;
function j(w: Single = -2): Single; begin j := w; end;
function k(w: Double = C * 2): Double; begin k := w; end;
function n(w: Double = -1): Boolean; begin n := w < 0; end;

var o: TK;
begin
  WriteLn(g():0:2, ' ', h():0:2, ' ', i():0:2, ' ', j():0:2, ' ', k():0:2);
  WriteLn(n(), ' ', g(7):0:2);
  o := TK.Create;
  WriteLn(o.m():0:2, ' ', o.m('x', 4):0:2);
  o.Free;
end.

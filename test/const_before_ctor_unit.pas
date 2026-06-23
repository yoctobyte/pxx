unit const_before_ctor_unit;

{ Regression for bug-const-section-before-constructor: a const section in the
  implementation, directly followed by a constructor body, must terminate on
  `constructor` (a plain identifier in this dialect, not a keyword token) rather
  than consume it as the next const name. Also covers a const ending the
  interface section before `implementation`. }

interface

const
  IBASE = 5;

type
  TThing = class
    V: Integer;
    constructor Create;
    procedure Bump;
  end;

implementation

const
  K = 7;

constructor TThing.Create;
begin
  V := K + IBASE;
end;

procedure TThing.Bump;
const STEP = 100;
begin
  V := V + STEP;
end;

end.

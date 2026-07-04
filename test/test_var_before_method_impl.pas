{ bug-var-section-eats-constructor-destructor: a `var` section before a
  constructor/destructor method implementation used to fail — ctor/dtor are soft
  identifiers in this dialect, and ParseVarSection consumed the `destructor`
  token as a variable name. This exercises a var section BEFORE the method impls
  (and a second var section after them), plus a shared global the impls touch —
  the ordering FPC allows and that a `destructor Destroy; override;` body needs
  when it references a program global declared before it. }
program test_var_before_method_impl;

type
  TCounter = class
    constructor Create; override;
    destructor Destroy; override;
  end;

var
  ctorHits, dtorHits: Integer;   { globals declared BEFORE the impls that use them }

constructor TCounter.Create;
begin
  inherited Create;
  ctorHits := ctorHits + 1;
end;

destructor TCounter.Destroy;
begin
  dtorHits := dtorHits + 1;
  inherited Destroy;
end;

var                              { a second var section AFTER the method impls }
  c: TCounter;
begin
  ctorHits := 0; dtorHits := 0;
  c := TCounter.Create;
  c.Free;
  writeln('ctor=', ctorHits, ' dtor=', dtorHits);
end.

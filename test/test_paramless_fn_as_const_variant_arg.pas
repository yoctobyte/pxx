program test_paramless_fn_as_const_variant_arg;
{ A parameterless function called BY NAME as an argument to a `const Variant`
  parameter. `freetwo('a', zero)` compiled; `obj.two('a', zero)` reported
  `undefined variable (zero)` — a diagnostic pointing at the argument, for a
  name that is a perfectly good function.

  Boundary, measured before fixing: only METHOD + `const Variant` + a BARE name
  failed. By-value `Variant` compiled, `const AnsiString` compiled, an explicit
  `zero()` compiled (the `(` reached a different clause), and a genuine `var`
  parameter correctly answered "by-reference argument must be a variable".

  A `const Variant` parameter is by-ref internally but is never a var-binding
  target, so a call producing a value is a legal argument and there is nothing
  to bind. ByRefArgStartsExpression now says so.

  Covers the siblings too, because the fix is in the shared predicate: an
  overloaded method (which takes the arity-probe path), a static class method,
  a record method, and an ALL-DEFAULTED function, which is paramless at the
  call site.

  bug-p-a-parameterless-function-is-undefined-as-a-method-call-argument
  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
{$modeswitch advancedrecords}
type
  R = record function rf(const b: Variant): Variant; end;
  K = class
    function f(const b: Variant): Variant;
    function g(const b: Variant): Variant; overload;
    function g(const a: AnsiString; const b: Variant): Variant; overload;
    function byval(b: Variant): Variant;
    function astr(const b: AnsiString): AnsiString;
    class function cf(const b: Variant): Variant; static;
  end;
function R.rf(const b: Variant): Variant; begin rf := b; end;
function K.f(const b: Variant): Variant; begin f := b; end;
function K.g(const b: Variant): Variant; begin g := b; end;
function K.g(const a: AnsiString; const b: Variant): Variant; begin g := b; end;
function K.byval(b: Variant): Variant; begin byval := b; end;
function K.astr(const b: AnsiString): AnsiString; begin astr := b; end;
class function K.cf(const b: Variant): Variant; begin cf := b; end;

function zero: Variant; begin zero := 7; end;
function zstr: AnsiString; begin zstr := 'str'; end;
function defd(a: Integer = 3): Variant; begin defd := a; end;
function freetwo(const a: AnsiString; const b: Variant): Variant; begin freetwo := b; end;

var o: K; rr: R; v: Variant; s: AnsiString;
begin
  o := K.Create;
  v := freetwo('a', zero);  WriteLn('free    : ', v);
  v := o.f(zero);           WriteLn('method  : ', v);
  v := o.g(zero);           WriteLn('ovl1    : ', v);
  v := o.g('a', zero);      WriteLn('ovl2    : ', v);
  v := K.cf(zero);          WriteLn('static  : ', v);
  v := rr.rf(zero);         WriteLn('record  : ', v);
  v := o.f(defd);           WriteLn('alldeflt: ', v);
  v := o.f(zero());         WriteLn('explicit: ', v);
  v := o.byval(zero);       WriteLn('byval   : ', v);
  s := o.astr(zstr);        WriteLn('constatr: ', s);
end.

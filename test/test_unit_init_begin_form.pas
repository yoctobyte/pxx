{$mode objfpc}
program test_unit_init_begin_form;

{ A unit's classic `begin ... end.` initialization section must execute, like
  `initialization` does, and unit inits must run in dependency order
  (bug-unit-init-begin-form-not-executed: the begin form was parsed, accepted,
  and silently dropped — variables kept plausible BSS zeros). }

uses uideriv, uibase, uikw;

begin
  writeln(BaseInit);    { 7   — begin-form ran }
  writeln(DerivInit);   { 8   — ran AFTER its dependency's init }
  writeln(KwInit);      { 222 — initialization keyword form }
end.

{$MODE DELPHI}
program test_forward_decl_case_insensitive;
{ Pascal is case-insensitive, so a forward declaration and its implementation
  spelled in different case are ONE routine. FindProcOverloadRec compared names
  with `=` only, so the body registered a SECOND proc and the declared one
  stayed bodiless.

  The symptom depends on how the name is later reached, which is why this was
  expensive to find:
    - a direct call reports `unresolved forward: Bar`;
    - `@Bar` captured in a TYPED CONST keeps the bodiless entry and survives to
      LINK, dying as "the address of a routine with no body was taken" — which
      accuses the address-of, not the case mismatch.
  Both are pinned below. rtl-generics reaches it through
  `TEquals.&Class` (declared) vs `TEquals.&class` (implemented); the `&` escape
  is incidental, so a plain name is tested alongside an escaped one.
  bug-p-a-forward-declaration-does-not-bind-a-differently-cased-body }

type
  TR = record F: Pointer; end;
  TF = function(a: Integer): Boolean;

  TE = class
    class function Foo(a: Integer): Boolean;
    class function Same(a: Integer): Boolean;
    class function &Class(a: Integer): Boolean;
  end;

{ plain forward routine, body in a DIFFERENT case }
function Bar(a: Integer): Boolean; forward;
function bar(a: Integer): Boolean;
begin Result := a > 0; end;

{ class methods: mismatched, matching (control), and an ESCAPED name }
class function TE.foo(a: Integer): Boolean;
begin Result := a > 10; end;

class function TE.Same(a: Integer): Boolean;
begin Result := a > 20; end;

class function TE.&class(a: Integer): Boolean;
begin Result := a > 30; end;

{ the address-in-a-typed-const shape — the one that reached LINK }
const
  V1: TR = (F: @Bar);
  V2: TR = (F: @TE.Foo);
  V3: TR = (F: @TE.Same);
  V4: TR = (F: @TE.&Class);

var f: TF;
begin
  { direct call through the forward name }
  WriteLn(Bar(1), ' ', Bar(-1));

  { the const-captured addresses must all be real }
  WriteLn(V1.F <> nil, ' ', V2.F <> nil, ' ', V3.F <> nil, ' ', V4.F <> nil);

  { and the plain routine's address must be CALLABLE — a non-nil pointer to the
    wrong entry still runs the wrong code. Only Bar is called through TF: a
    CLASS method carries a hidden Self, so invoking one through a plain
    `function(a: Integer)` pointer puts the argument in the Self slot and is
    undefined in both compilers. (Measured: FPC answers TRUE for a call that
    should be FALSE. The corpus does take these addresses, but calls them
    through a hand-built VMT with the right convention.) So the class rows
    assert the ADDRESS — which is exactly what this bug broke — and the
    BEHAVIOUR is checked by calling the methods normally. }
  f := V1.F; WriteLn(f(1), ' ', f(-1));

  { each method must be the one its own body defines, not a sibling's }
  WriteLn(TE.Foo(11), ' ', TE.Foo(1));
  WriteLn(TE.Same(21), ' ', TE.Same(1));
  WriteLn(TE.&Class(31), ' ', TE.&Class(1));
end.

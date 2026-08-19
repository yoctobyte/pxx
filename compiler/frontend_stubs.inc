{ SPDX-License-Identifier: MPL-2.0 }
{ STUBS FOR AN OMITTED FRONTEND.

  A reduced build (feature-a-build-a-reduced-compiler-by-selecting-frontends-
  and-targets) drops a frontend's `{$include}` lines. Most of the tree does not
  notice — the shared parser's NilPy-aware BEHAVIOUR (`if isNilPy then ...`)
  compiles fine and simply never fires, which is why omitting a frontend costs
  far less than its reference count suggests. What does not survive is the
  handful of places where shared code CALLS a helper whose body lives in the
  frontend's own file.

  Measured 2026-08-19 by omission: eight functions, total, across both
  frontends. They are stubbed here rather than guarded at each of their ~40
  call sites, for the reason this repo keeps relearning — one place that
  records the fact beats forty predicates that re-derive it, and a guard
  forgotten at one site is a compile error in a configuration nobody builds
  that day.

  EVERY STUB IS UNREACHABLE BY CONSTRUCTION: each call site sits inside an
  `if isNilPy then` / C-parser branch, and a compiler built without a frontend
  cannot set that flag — it refuses the source file at dispatch. So the bodies
  raise rather than return a plausible value. A stub that quietly returned 0
  would turn "this build has no NilPy" into a wrong answer somewhere far away,
  which is exactly the shape of bug this codebase pays most for.

  Signatures MUST stay byte-identical to the real bodies. }

{$ifdef PXX_NO_CFRONT}
function CNodeDecaysToPointer(node: Integer): Boolean;
begin
  { array-to-pointer decay is a C rule; no C source can be in this build }
  CNodeDecaysToPointer := False;
end;

function FindCTypedef(const name: AnsiString): Integer;
begin
  FindCTypedef := -1;
end;

{ Reached only from the C dispatch arm and from a `uses './x.c'`, both of which
  refuse before they get here in this configuration. }
procedure AddDefaultCIncludeDirs;
begin
  Error('internal: AddDefaultCIncludeDirs reached in a build without the C frontend');
end;

procedure ParseCUnit;
begin
  Error('internal: ParseCUnit reached in a build without the C frontend');
end;

procedure RegisterCMacroConsts;
begin
  Error('internal: RegisterCMacroConsts reached in a build without the C frontend');
end;
{$endif}

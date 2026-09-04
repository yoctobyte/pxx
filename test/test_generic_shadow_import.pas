{ A file declaring `TBox<T>` while ALSO importing units that declare `TBox<T>`.
  Ordinary Pascal scoping: the local declaration wins. It did not -- every use
  resolved to the IMPORT and `b.Local` answered `no such member`.

  TWO MECHANISMS, and each covers a case the other does not. The ablation is in
  the ticket; both were measured by removing one and re-running these rows.

  1. THE ALIAS WAS MINTED TOO EARLY. DesugarImportedDelphiGenericUses runs at the
     end of ParseUsesClause and mints `TBox$Integer = specialize TBox<Integer>;`
     right there -- DGenDeclAnchor returns the clause itself for that caller, by
     design and with the reason written down. So the alias was PARSED before this
     file's own type section existed, and the name resolved against the only
     template registered at that moment. Fixed by skipping the sweep for a
     template whose name this FILE also declares ahead of the clause; the local
     declaration's own sweep then mints it, where the by-name lookup already
     prefers the later declaration.

  2. THE MINTED NAME IS NOT AN IDENTITY. Once ugshadowa specializes TBox<Integer>
     ITSELF, `TBox$Integer` already exists, and ParseSpecialization's "an exact
     re-statement is a no-op" shortcut compared the two by TEMPLATE NAME -- which
     is equal for two different templates that share a spelling. The program's
     own declaration was consumed as a duplicate. Fixed by keying that check on
     the Templates[] INDEX (SpecTemplateIdx[]).

  WHY THE MEMBER NAMES ARE ALL DIFFERENT. `Local`, `FromA`, `FromB`: a wrong
  resolution is then a compile error that names the member, not a value that
  happens to agree. test_generic_shadow_decl deliberately does the opposite --
  same member name on both -- so that its result cannot depend on which template
  wins; this test is the one that asserts which one does.

  Oracle: FPC 3.2.2 prints `42 11 33 4`. }
program test_generic_shadow_import;
{$MODE DELPHI}

uses ugshadowa, ugshadowb;

type
  TBox<T> = record Local: T; end;

var
  b: TBox<Integer>;
begin
  b.Local := 42;
  { AUsesItsOwn and BUsesItsOwnAndA prove the two units still reach their OWN
    templates -- a fix that made the LAST declaration win everywhere would pass
    the first column and fail these two. SizeOf(b) is the fourth: the local
    record has one Integer field, so 4, and it is not a default anything. }
  writeln(b.Local, ' ', AUsesItsOwn, ' ', BUsesItsOwnAndA, ' ', SizeOf(b));
end.

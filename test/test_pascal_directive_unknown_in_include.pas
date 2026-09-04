{ The unknown-directive warning across pxx's TWO WALKS of every Pascal source.

  frankD's point while landing {$CLAIM} (d10527193): every source is walked
  twice — once by ExpandIncludes in elfwriter.inc, to decide which {$I} to
  follow, and again by the lexer over the expanded text. A directive with a
  DURABLE side effect taken on walk one is still in effect on walk two, which is
  a real bug he hit and fixed. The terminal unknown-directive arm has the
  mirror-image hazard: it lives in the LEXER's dispatch, and if ExpandIncludes'
  evaluator ever grows one too, every warning in the file DOUBLES.

  COUNT IS THE ASSERTION, and it is why this file exists rather than a grep:
  a second terminal arm would not change any message, only how many times each
  appears — invisible to any row that checks a warning is present.

  THREE POPULATIONS, one of which must stay silent:
    main-file directive   -> warns, naming the MAIN file's line
    include directive     -> warns, naming the INCLUDE's OWN line (2, not the
                             line it was pasted onto)
    inactive-branch one   -> silent, because the whole dispatch chain is under
                             PasDirectiveActive

  The program also PRINTS the include's const. That is the precondition, not
  decoration: "exactly 2 warnings" is satisfiable by a run where the include was
  never expanded at all, and then the include row is measuring nothing.
  bug-p-an-unknown-compiler-directive-is-silently-ignored }
program test_pascal_directive_unknown_in_include;
{$bogusinmain}
{$i directive_unknown_in_include.inc}
{$ifdef NEVER_DEFINED_ANYWHERE}
{$bogusinsideinactive}
{$endif}
begin
  WriteLn(FromInclude);
end.

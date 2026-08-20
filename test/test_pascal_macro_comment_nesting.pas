program test_pascal_macro_comment_nesting;
{$MODE DELPHI}
{$MACRO ON}
(* Comment nesting is MODE-dependent, and the macro pre-pass has to know it.

   ExpandPasMacros runs over the raw text BEFORE the lexer, so it scans comments
   itself. It always nested them -- but $MODE DELPHI turns nesting OFF, so a
   brace comment holding a stray opening brace (a banner rule, a commented-out
   field, ordinary prose) swallowed everything up to the NEXT closing brace and
   the declarations in between vanished. In rtl-generics that ate a whole
   $define block, and the build died 90 lines later on "undefined variable
   (HASH_FACTORY)", which points at nothing.

   The setting moves with $MODE, so the pre-pass tracks it: Delphi mode off,
   an FPC mode back on -- the FPC-mode half lives in unit macronest_fpcmode,
   because FPC allows a mode switch only at the top of a compilation unit. The comments below are the shapes that failed; if the
   pre-pass mis-scans any of them the macros after it are never defined and this
   file does not compile at all -- which is the assertion.

   The header you are reading is an old-style comment on purpose: in Delphi mode
   a brace comment ends at the first closing brace, so prose about braces cannot
   live in one. FPC agrees, and rejects this file identically if it does.
   feature-pascal-corpus-generics *)

uses macronest_fpcmode;

{$define TAG := 'delphi-mode'}

{ a comment with an unmatched brace: { and nothing closing it before here }
{$define AFTER_STRAY := 41}

(* an old-style comment holding a brace { too *)
{$define AFTER_OLDSTYLE := 1}

{ ...and once more, since nothing above may have changed the setting }
{$define AFTER_OFF := 'nested-off'}

begin
  writeln(TAG);
  writeln(AFTER_STRAY + AFTER_OLDSTYLE);
  writeln(NestedTag);
  writeln(AFTER_OFF);
  writeln('MACRO COMMENT NESTING OK');
end.

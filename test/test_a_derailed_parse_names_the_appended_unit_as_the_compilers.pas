{ MUST NOT COMPILE, and the point is WHERE the refusal says the mistake is.

  A close-brace inside QUOTES inside a comment still ends the comment -- a quote
  does not protect a brace. The rest of that line becomes code, the remaining
  source is swallowed by the unterminated string it opens, and the user's file
  runs out of tokens mid-statement.

  The builtin units are lexed into the SAME token array, AFTER the main source,
  with nothing between them. So the parse carries straight on into `unit
  builtinheap` and reports -- truthfully, at correct coordinates -- about a file
  the author never opened:

    in: ./compiler/builtin/builtinheap.pas

  A wrong line number is a slow read; a real file in the compiler's own RTL
  invites the reader to go hunting for a compiler bug, and two agents did. The
  note now says that unit is appended to every program and names the file to
  check first.

  ASSERTED ON THE NOTE, NOT ON THE EXIT CODE. This file was always refused; the
  defect was entirely in where the refusal pointed, so an exit-code assertion
  passes on the bug. The note deliberately does NOT claim which of the two
  causes it is -- a genuine defect in a builtin unit prints the same coordinates
  -- it names both and says which to check first, which is the part the reader
  cannot work out.
  bug-p-a-brace-in-comment-prose-reports-the-wrong-line-and-sometimes-the-wrong-file }
program test_a_derailed_parse_names_the_appended_unit_as_the_compilers;
begin
  { the loop below steps past the '}' terminator }
  WriteLn('ok');
end.

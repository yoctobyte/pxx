{ MUST NOT COMPILE. A brace written as PROSE inside a comment opens a nested
  one, so the author's closing brace balances THAT and the outer comment runs to
  end of file.

  The diagnostic used to report `unterminated comment` at the OUTER brace and
  stop. That line is true -- it is the unclosed one -- and it is the one place
  guaranteed not to be the mistake, because it is what the author wrote
  correctly. On the ticket's own case the offender was 42 lines below it and
  four fix attempts were aimed at the reported line.

  So the error stays where it was and the NOTES name the nested opens. This
  fixture asserts the note, not the exit code: any refusal scores as a pass
  otherwise, and this file has always been refused -- the whole defect was that
  the refusal pointed somewhere useless.
  bug-p-a-brace-in-comment-prose-reports-the-wrong-line-and-sometimes-the-wrong-file }
program test_unterminated_comment_names_the_nested_brace;
{ line 17: this doc comment OPENS here and is otherwise fine.
  line 18
  line 19
  line 20: a shell placeholder written in prose, unterminated on purpose:
           $-open-brace-who   <-- THE OFFENDER is the brace on the next line
  line 22: ${who
  line 23
  line 24 }
begin
  WriteLn('never reached');
end.

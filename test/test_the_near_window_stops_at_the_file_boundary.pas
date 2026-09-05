{ MUST NOT COMPILE, and the assertion is on the `near:` WINDOW, not on the exit
  code -- this file has no `end.`, so it has always been refused and an
  exit-code row would score a pass on the bug itself.

  There is ONE token array. The main file goes in first, then any `uses`d unit,
  then the builtin units the compiler appends to every program, with nothing
  between them. A parse that runs out of the user's tokens carries straight on
  into `unit builtinheap` and reports there -- truthfully, at coordinates that
  belong to somebody else's file.

  The `in:` note (test_a_derailed_parse_names_the_appended_unit_as_the_compilers)
  covers WHOSE file that is. This covers the excerpt, which had no idea the
  array held more than one file and quoted across the seam:

    near: ( 'hi' ) ; unit builtinheap >>> ; interface type

  `( 'hi' ) ;` is from this file and `unit builtinheap` is from ours, spliced
  with nothing to say so. The line number and the message were right in every
  sighting of this -- only the excerpt was wrong, which is why it neither errors
  nor looks wrong.
  bug-p-error-context-near-quotes-an-unrelated-token-stream }
program test_the_near_window_stops_at_the_file_boundary;
begin
  WriteLn('hi');

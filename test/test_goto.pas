program TestGoto;
label
  loop_start, loop_done, skip_block, after_skip;
var
  i, sum: Integer;
begin
  { Backward jump: sum 1..5 using goto }
  i   := 1;
  sum := 0;
loop_start:
  sum := sum + i;
  i   := i + 1;
  if i <= 5 then goto loop_start;
  writeln(sum);          { 15 }

  { Forward jump: skip a block }
  goto skip_block;
  writeln('SHOULD NOT PRINT');
skip_block:
  writeln('skipped');    { skipped }

  { Nested: forward then backward }
  i := 0;
after_skip:
  i := i + 1;
  if i < 3 then goto after_skip;
  writeln(i);            { 3 }
end.

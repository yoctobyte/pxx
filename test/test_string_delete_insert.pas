program test_string_delete_insert;

{ Standard in-place string mutators Delete(s, index, count) and
  Insert(src, s, index), available with no `uses` (lowered to the
  __pxxStrDelete / __pxxStrInsert builtin helpers). Covers normal, over-long
  count (clamped to end), past-end insert (appends), and front insert. FPC
  oracle: ho / hellxo / abc / world! / abc. }

var s: string;
begin
  s := 'hello';  Delete(s, 2, 3);    WriteLn(s);   { ho }
  s := 'hexo';   Insert('ll', s, 3); WriteLn(s);   { hellxo }
  s := 'abcdef'; Delete(s, 4, 100);  WriteLn(s);   { abc }
  s := 'world';  Insert('!', s, 99); WriteLn(s);   { world! }
  s := 'bc';     Insert('a', s, 1);  WriteLn(s);   { abc }
end.

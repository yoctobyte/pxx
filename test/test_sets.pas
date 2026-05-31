program test_sets;

var
  s1, s2, s3: set of Byte;
  b: Byte;

begin
  { 1. Set literal assignment }
  s1 := [1, 2, 5..10];
  s2 := [2, 10..15];

  { 2. Inline literal 'in' membership checks }
  if 1 in s1 then
    writeln('1 in s1: OK')
  else
    writeln('1 in s1: FAIL');

  if 15 in s1 then
    writeln('15 in s1: FAIL')
  else
    writeln('15 in s1: OK');

  if 12 in s2 then
    writeln('12 in s2: OK')
  else
    writeln('12 in s2: FAIL');

  { 3. Dynamic variable 'in' membership checks }
  b := 10;
  if b in s1 then
    writeln('b (10) in s1: OK')
  else
    writeln('b (10) in s1: FAIL');

  b := 20;
  if b in s1 then
    writeln('b (20) in s1: FAIL')
  else
    writeln('b (20) in s1: OK');

  { 4. Set union (+) }
  s3 := s1 + s2; { expected elements: 1, 2, 5..10, 10..15 = 1, 2, 5..15 }
  if 1 in s3 then writeln('1 in s3 (union): OK') else writeln('1 in s3 (union): FAIL');
  if 12 in s3 then writeln('12 in s3 (union): OK') else writeln('12 in s3 (union): FAIL');
  if 4 in s3 then writeln('4 in s3 (union): FAIL') else writeln('4 in s3 (union): OK');

  { 5. Set intersection (*) }
  s3 := s1 * s2; { expected elements: 2, 10 }
  if 2 in s3 then writeln('2 in s3 (intersection): OK') else writeln('2 in s3 (intersection): FAIL');
  if 10 in s3 then writeln('10 in s3 (intersection): OK') else writeln('10 in s3 (intersection): FAIL');
  if 1 in s3 then writeln('1 in s3 (intersection): FAIL') else writeln('1 in s3 (intersection): OK');
  if 12 in s3 then writeln('12 in s3 (intersection): FAIL') else writeln('12 in s3 (intersection): OK');

  { 6. Set difference (-) }
  s3 := s1 - s2; { expected elements: s1 without s2 = 1, 5..9 }
  if 1 in s3 then writeln('1 in s3 (difference): OK') else writeln('1 in s3 (difference): FAIL');
  if 5 in s3 then writeln('5 in s3 (difference): OK') else writeln('5 in s3 (difference): FAIL');
  if 2 in s3 then writeln('2 in s3 (difference): FAIL') else writeln('2 in s3 (difference): OK');
  if 10 in s3 then writeln('10 in s3 (difference): FAIL') else writeln('10 in s3 (difference): OK');

  { 7. Set comparisons }
  s3 := [1, 2, 5..10];
  if s1 = s3 then
    writeln('s1 = s3: OK')
  else
    writeln('s1 = s3: FAIL');

  if s1 <> s2 then
    writeln('s1 <> s2: OK')
  else
    writeln('s1 <> s2: FAIL');

  s3 := [1, 2, 5..8];
  if s3 <= s1 then
    writeln('s3 <= s1: OK')
  else
    writeln('s3 <= s1: FAIL');

  if s1 >= s3 then
    writeln('s1 >= s3: OK')
  else
    writeln('s1 >= s3: FAIL');

  if s1 <= s2 then
    writeln('s1 <= s2: FAIL')
  else
    writeln('s1 <= s2: OK');

  if s3 < s1 then
    writeln('s3 < s1: OK')
  else
    writeln('s3 < s1: FAIL');

  if s1 > s3 then
    writeln('s1 > s3: OK')
  else
    writeln('s1 > s3: FAIL');

  { 8. Nested algebra keeps independent intermediate values }
  s3 := (s1 + s2) - [2, 12];
  if 1 in s3 then writeln('1 in nested result: OK') else writeln('1 in nested result: FAIL');
  if 2 in s3 then writeln('2 in nested result: FAIL') else writeln('2 in nested result: OK');
  if 12 in s3 then writeln('12 in nested result: FAIL') else writeln('12 in nested result: OK');
  if 15 in s3 then writeln('15 in nested result: OK') else writeln('15 in nested result: FAIL');

  writeln('all set tests completed!');
end.

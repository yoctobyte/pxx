{$define PXX_MANAGED_STRING}
program test_variant_string_ops;

var
  v1, v2, v3, v_res: Variant;
  c: Char;

begin
  { --- 1. Comparisons on string Variants --- }
  v1 := 'apple';
  v2 := 'banana';
  v3 := 'apple';

  writeln(v1 = v3);    { 1 }
  writeln(v1 <> v3);   { 0 }
  writeln(v1 = v2);    { 0 }
  writeln(v1 <> v2);   { 1 }

  writeln(v1 < v2);    { 1 }
  writeln(v1 <= v2);   { 1 }
  writeln(v1 > v2);    { 0 }
  writeln(v1 >= v2);   { 0 }

  writeln(v2 > v1);    { 1 }
  writeln(v2 >= v1);   { 1 }

  writeln(v1 <= v3);   { 1 }
  writeln(v1 >= v3);   { 1 }

  { --- 2. Mixed String and Char Comparisons --- }
  v1 := 'a';
  v2 := 'b';
  writeln(v1 = 'a');   { 1 }
  writeln(v1 = v2);    { 0 }
  writeln(v1 <> v2);   { 1 }
  writeln(v1 < v2);    { 1 }
  writeln(v1 > v2);    { 0 }

  { --- 3. Concatenation --- }
  v1 := 'hello ';
  v2 := 'world';
  v_res := v1 + v2;
  writeln(v_res);      { hello world }

  { Concatenating Char and String }
  v1 := 'a';
  v2 := 'b';
  v_res := v1 + v2;
  writeln(v_res);      { ab }

  { Concatenating with literal }
  v1 := 'sweet ';
  v_res := v1 + 'potato';
  writeln(v_res);      { sweet potato }

  v1 := 'tomato';
  v_res := 'green ' + v1;
  writeln(v_res);      { green tomato }

  { --- 4. Tag Mismatches --- }
  v1 := 'abc';
  v2 := 123;
  writeln(v1 = v2);    { 0 }
  writeln(v1 <> v2);   { 1 }
  writeln(v1 < v2);    { 0 }
  writeln(v1 > v2);    { 0 }
end.

program test_var_nd_array_string_init;
var
  { N-D var array initializers nest one paren level per dimension; the flat
    store fills in row-major order. Covers ordinal and String/AnsiString
    element types, and both single-char and multi-char string literals
    (bug-array-const-too-many-elements-synapse). }
  nums: array[0..1, 0..2] of Integer =
    (
    (1, 2, 3),
    (4, 5, 6)
    );
  months: array[0..1, 1..3] of String =
    (
    ('Jan', 'Feb', 'Mar'),
    ('Apr', 'May', 'Jun')
    );
  chars: array[1..3] of String = ('x', 'yy', 'zzz');
begin
  writeln(nums[0,0], ' ', nums[0,2], ' ', nums[1,0], ' ', nums[1,2]);
  writeln(months[0,1], ' ', months[0,3], ' ', months[1,1], ' ', months[1,3]);
  writeln(chars[1], ' ', chars[2], ' ', chars[3]);
end.

{ A second class of the same name in one unit must be REJECTED. Accepted, every
  use of the name binds to the FIRST declaration and the diagnostics land far
  away — pylib had ZeroDivisionError declared twice and nothing said so.
  bug-pascal-duplicate-class-name-silently-shadows }
program test_pascal_duplicate_class_fail;
type
  TFoo = class
    a: Integer;
  end;
  TFoo = class
    b: Integer;
  end;
begin
end.

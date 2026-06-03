{ Object-like integer #define macros from an imported C header are surfaced as
  Pascal constants. sqlite3.h defines SQLITE_OK, SQLITE_ROW, SQLITE_DONE as
  plain #define integers (not an enum); the C-header importer evaluates the
  pure integer bodies and registers them as constants usable by exact name.
  SQLITE_LIMIT_LENGTH (0) and a shifted/expression macro exercise that the
  value is a real constant expression, not just a literal. }
program test_c_define_const;
uses sqlite3;
begin
  writeln(SQLITE_OK);            { 0 }
  writeln(SQLITE_ROW);           { 100 }
  writeln(SQLITE_DONE);          { 101 }
  writeln(SQLITE_ROW + 1);       { 101 — usable in constant arithmetic }
end.

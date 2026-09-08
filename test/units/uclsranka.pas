{ Declares a CLASS named TShared, and TAlt for the other units to alias to.
  Support for test_an_alias_in_a_used_unit_ranks_with_the_class_rows.pas. }
unit uclsranka; {$mode objfpc}
interface
type
  TShared = class F: LongInt; end;
  TAlt    = class G: LongInt; end;
implementation
end.

{ ALIASES TShared to uclsranka's TAlt. A unit that renames a name another unit
  declares as a real class -- the shape the ranked scan could not see. }
unit uclsrankb; {$mode objfpc}
interface
uses uclsranka;
type
  TShared = TAlt;
implementation
end.

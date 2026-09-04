{ The template. Two units below reach it from DIFFERENT sections -- one from an
  interface `uses`, one from an implementation `uses` -- and the specialization
  alias each mints inherits the section of the clause that minted it.
  See test_generic_spec_unit_section.pas. }
unit ugsecta;
{$MODE DELPHI}

interface

type
  TBox<T> = record V: T; Tag: ShortInt; end;

implementation

end.

unit mimic_pkgprobe_sub;
{ Stands in for a dotted Python package (`pkgprobe.sub`) so the import resolver's
  two halves can be tested: the frontend mangles the dots to underscores, and a
  module we implement ourselves lives under OUR name, mimic_<module>, which the
  resolver falls back to when no real unit of that name exists.
  feature-nilpy-dotted-package-imports. }

interface

function greet(const who: AnsiString): AnsiString;

implementation

function greet(const who: AnsiString): AnsiString;
begin
  greet := 'hello ' + who;
end;

end.

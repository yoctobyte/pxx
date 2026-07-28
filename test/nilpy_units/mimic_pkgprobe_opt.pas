unit mimic_pkgprobe_opt;
{ Stands in for an optional dependency that IS present, so the try branch of a
  fallback import can be taken. feature-nilpy-fallback-import. }

interface

function optname: AnsiString;

implementation

function optname: AnsiString;
begin
  optname := 'present';
end;

end.

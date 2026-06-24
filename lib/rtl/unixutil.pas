unit unixutil;
{ Minimal FPC-compatible UnixUtil shim (feature-synapse-compile-check).

  Synapse's synautil lists `UnixUtil` in its FPC/UNIX uses clause but the symbols
  it actually consumes from that chain (Tzseconds, the timeval family,
  fpgettimeofday) live in [[unix]] / [[baseunix]]. So this unit only needs to
  exist; symbols are added here only if a consumer is shown to need one from
  UnixUtil specifically. NOT a port of FPC's UnixUtil. }

interface

implementation

end.

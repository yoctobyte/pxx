unit termio;
{ Minimal FPC-compatible termio shim (feature-synapse-compile-check). Synapse's
  ssfpc.inc references only the three ioctl request constants below (for socket
  byte-count / non-blocking / async toggles). The full termios/serial surface is
  not provided — grow only as a consumer needs it. Linux ioctl values, shared
  across our LE targets. }

interface

const
  FIONREAD = $541B;   { bytes available to read }
  FIONBIO  = $5421;   { set/clear non-blocking }
  FIOASYNC = $5452;   { set/clear async (SIGIO) }

implementation

end.

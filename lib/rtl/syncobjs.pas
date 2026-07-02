{ SPDX-License-Identifier: Zlib }
unit syncobjs;

{ Minimal single-threaded stand-in for FPC's SyncObjs unit. Lock operations
  are no-ops: generated code has no preemptive threads unless --threadsafe,
  and statement-level locking is a separate arc (see
  feature-threadsafe-io-serialization). API shape matches FPC's
  TCriticalSection so units like Synapse's ssfpc.inc parse and link; give the
  methods real bodies when a thread runtime lands. }

interface

type
  TCriticalSection = class
  public
    procedure Acquire;
    procedure Release;
    procedure Enter;
    procedure Leave;
    function TryEnter: Boolean;
  end;

implementation

procedure TCriticalSection.Acquire;
begin
end;

procedure TCriticalSection.Release;
begin
end;

procedure TCriticalSection.Enter;
begin
end;

procedure TCriticalSection.Leave;
begin
end;

function TCriticalSection.TryEnter: Boolean;
begin
  Result := True;
end;

end.

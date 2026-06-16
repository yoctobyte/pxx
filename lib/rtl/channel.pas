unit channel;
{ Bounded coroutine-to-coroutine channel (PXX-only). A fixed-size ring of Int64
  items; ChanSend blocks (CoYield) while full, ChanRecv blocks while empty. Pure
  cooperative — no epoll — so it runs on every target the scheduler does.

  Single OS thread, so no locking: a blocked side just yields and the scheduler
  round-robins the other side, which makes progress and lets the first resume. }

interface

uses scheduler;

const
  CHAN_CAP = 4;   { ring capacity; small on purpose so blocking is exercised }

type
  TChannel = record
    buf   : array[0..3] of Int64;   { CHAN_CAP slots }
    head  : Integer;
    tail  : Integer;
    count : Integer;
  end;

procedure ChanInit(var ch: TChannel);
procedure ChanSend(var ch: TChannel; v: Int64);
function  ChanRecv(var ch: TChannel): Int64;

implementation

procedure ChanInit(var ch: TChannel);
begin
  ch.head := 0;
  ch.tail := 0;
  ch.count := 0;
end;

{ Block (yield) while the ring is full, then enqueue. }
procedure ChanSend(var ch: TChannel; v: Int64);
begin
  while ch.count >= CHAN_CAP do CoYield;
  ch.buf[ch.tail] := v;
  ch.tail := (ch.tail + 1) mod CHAN_CAP;
  ch.count := ch.count + 1;
end;

{ Block (yield) while the ring is empty, then dequeue. }
function ChanRecv(var ch: TChannel): Int64;
begin
  while ch.count = 0 do CoYield;
  Result := ch.buf[ch.head];
  ch.head := (ch.head + 1) mod CHAN_CAP;
  ch.count := ch.count - 1;
end;

end.

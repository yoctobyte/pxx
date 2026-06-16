program TestChannel;
{ Bounded channel between two coroutines. The producer sends 1..6 through a
  capacity-4 ring, so it must block (yield) when the ring fills and resume after
  the consumer drains; the consumer receives 6 items and prints them in FIFO
  order. Pure cooperative scheduling — runs on every target. Deterministic. }
uses scheduler, channel;

var
  ch: TChannel;

procedure Producer(arg: Pointer);
var i: Integer;
begin
  for i := 1 to 6 do
    ChanSend(ch, i);
end;

procedure Consumer(arg: Pointer);
var i: Integer; v: Int64;
begin
  for i := 1 to 6 do
  begin
    v := ChanRecv(ch);
    writeln('recv ', Integer(v));
  end;
end;

begin
  ChanInit(ch);
  Spawn(@Producer, nil);
  Spawn(@Consumer, nil);
  RunUntilDone;
  writeln('done');
end.

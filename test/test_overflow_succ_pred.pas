program succq;
uses sysutils;
var q: qword; i: int64; caught: Integer;
begin
  caught := 0;
  {$Q+}
  q := qword($ffffffff) or (qword($ffffffff) shl 32);
  try
    q := Succ(q);
    writeln('no-raise ', q);
  except
    on eintoverflow do inc(caught);
  end;
  q := 0;
  try
    q := Pred(q);
    writeln('no-raise-pred ', q);
  except
    on eintoverflow do inc(caught);
  end;
  i := 9223372036854775807;
  try
    i := Succ(i);
    writeln('no-raise-si ', i);
  except
    on eintoverflow do inc(caught);
  end;
  {$Q-}
  q := 0;
  q := Pred(q);
  writeln('wrapped-hi ', q shr 32);
  writeln('caught=', caught);
end.

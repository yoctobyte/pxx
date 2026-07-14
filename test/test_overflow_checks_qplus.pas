program qplus;
uses sysutils;
var q1, q2, q3: qword; i: int64; caught: Integer;
begin
  caught := 0;
  {$Q+}
  q1 := qword($ffffffff) or (qword($ffffffff) shl 32);
  q2 := 1;
  try
    q3 := q1 + q2;
    writeln('no-raise ', q3);
  except
    on eintoverflow do inc(caught);
  end;
  try
    q3 := q2 - 2;
    writeln('no-raise-sub ', q3);
  except
    on eintoverflow do inc(caught);
  end;
  try
    q3 := q1 * 3;
    writeln('no-raise-mul ', q3);
  except
    on eintoverflow do inc(caught);
  end;
  i := 9223372036854775807;
  try
    i := i + 1;
    writeln('no-raise-signed ', i);
  except
    on eintoverflow do inc(caught);
  end;
  {$Q-}
  q3 := q1 + q2;   { wraps quietly }
  writeln('wrapped ', q3);
  writeln('caught=', caught);
end.

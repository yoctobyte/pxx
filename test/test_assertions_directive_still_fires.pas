{ The other half of the gate, and the reason the file above cannot stand alone:
  a compiler that dropped EVERY Assert would pass every row of it. This one must
  still fail at runtime with FPC's 227, so "assertions can be switched off" is
  measured against "assertions still work".
  feature-p-assertions-directive-and-position }
program test_assertions_directive_still_fires;
begin
  WriteLn('before');
  Assert(1 = 2, 'boom');
  WriteLn('after');
end.

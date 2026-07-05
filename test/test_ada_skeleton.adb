procedure TestAdaSkeleton is
   X : Integer := 0;
   Total : Integer := 0;
   I : Integer;
begin
   for I in 1..5 loop
      Total := Total + I;
   end loop;
   if Total = 15 then
      Put_Line("sum correct");
   else
      Put_Line("sum WRONG");
   end if;

   X := 0;
   while X < 3 loop
      Put_Line("while iter");
      X := X + 1;
   end loop;

   X := 0;
   loop
      X := X + 1;
      exit when X = 4;
   end loop;
   if X = 4 then
      Put_Line("exit-when correct");
   else
      Put_Line("exit-when WRONG");
   end if;

   X := 7;
   if X = 1 then
      Put_Line("one");
   elsif X = 7 then
      Put_Line("seven correct");
   else
      Put_Line("other");
   end if;
end TestAdaSkeleton;

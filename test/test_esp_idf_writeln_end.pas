program test_esp_idf_writeln_end;
{ A plain Pascal program under ESP-IDF that prints with WriteLn and then ENDS
  -- the shape every IDF example here avoids, because they print with
  esp_rom_printf and park in a vTaskDelay loop. The x86-64 run is the oracle.

  Two things used to go wrong, and both are invisible to a program shaped like
  the examples. WriteLn lowered to NOTHING on the ESP platform, so the serial
  log held only IDF's own lines. And the end of the program was a busy `j 0`,
  which starves FreeRTOS's idle task until the watchdogs reboot the chip and
  the whole program runs again -- a reboot that the diff below sees as a
  second copy of the output. On IDF, Write goes to PXXSysWrite (the libc stdout
  stream) and the end is vTaskDelete(NULL): see EmitIdfTaskEndCall.
  Every line ends in a newline: stdout is line-buffered and a task that ends
  does not flush a partial line. }
var i: Integer; big: Int64; s: AnsiString;
begin
  WriteLn('start');
  big := 1;
  for i := 1 to 40 do big := big * 3 div 2 + i;
  s := 'sum';
  WriteLn(s, ' ', big);
  for i := 1 to 3 do Write(i, ' ');
  WriteLn;
  WriteLn('end');
end.

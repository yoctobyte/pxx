{ An ESP Text record carries a 128-byte buffer, not 4096 (textfile.pas TF_BUFSIZE):
  the unit declares five standard Text files, which were 20.6 KB of .bss on
  every ESP program that pulled the unit in. The Makefile row reads the
  record size off PXXDBG=a.datamap. }
program esptext;
uses textfile;
begin
  WriteLn(Output, 1);
end.

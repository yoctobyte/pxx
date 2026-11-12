{ --rtl-libc must be output-identical to the raw-syscall build.
  The Makefile builds this twice (default and --rtl-libc) and compares stdout;
  it also checks the libc build has at most one raw kernel entry (rt_sigreturn).
  Regression for the DCE pass not remapping LibcSyscallCallPos (2026-11-12):
  hello-world segfaulted on its first WriteLn under --rtl-libc.
  feature-port-libc-family-openbsd-netbsd-minix }
program test_rtl_libc_torture;

uses SysUtils;

type
  TCounter = class
    N: Integer;
    constructor Create(start: Integer);
    procedure Bump;
  end;

constructor TCounter.Create(start: Integer);
begin
  N := start;
end;

procedure TCounter.Bump;
begin
  Inc(N);
end;

var
  i, sum: Integer;
  a: array of Integer;
  s, t: AnsiString;
  c: TCounter;
  f: TextFile;
  path: AnsiString;
begin
  sum := 0;
  for i := 1 to 1000 do sum := sum + i * 3;
  WriteLn('sum ', sum);

  SetLength(a, 64);
  for i := 0 to High(a) do a[i] := i * i;
  WriteLn('a[63] ', a[63], ' len ', Length(a));

  s := '';
  for i := 1 to 50 do s := s + IntToStr(i) + ',';
  t := Copy(s, 10, 12);
  WriteLn('len ', Length(s), ' copy ', t);

  c := TCounter.Create(40);
  c.Bump; c.Bump;
  WriteLn('counter ', c.N);
  c.Free;

  try
    raise Exception.Create('boom');
  except
    on E: Exception do WriteLn('caught ', E.Message);
  end;

  path := GetEnvironmentVariable('PXX_RTL_LIBC_TMP');
  if path = '' then path := '/tmp';
  path := path + '/rtl_libc_torture.txt';
  AssignFile(f, path);
  Rewrite(f);
  WriteLn(f, 'line one');
  WriteLn(f, 'line two');
  CloseFile(f);
  AssignFile(f, path);
  Reset(f);
  ReadLn(f, s);
  ReadLn(f, t);
  CloseFile(f);
  DeleteFile(path);
  WriteLn('file ', s, ' / ', t);
end.

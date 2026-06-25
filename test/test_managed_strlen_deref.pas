program test_managed_strlen_deref;

{ Managed-string (default) Length() through a pointer deref / pointer field.
  `@s` of a managed string is the address of its HANDLE slot, so `ps^` denotes
  that slot. Length(ps^) must deref the slot to the handle and read [handle-8],
  exactly like a managed-string record field. Before bug-managed-length-via-
  pointer-deref this returned the raw handle value (garbage; word-size dependent).
  No flag = managed default. Re-pointing must not leak/double-free. }

type
  PStr = ^string;
  TRec = record np: PStr; end;

var
  s, t: string;
  ps: PStr;
  r: TRec;
  i: Integer;
begin
  s := 'TRoot';
  t := 'hi';
  ps := @s;
  r.np := @s;

  writeln(Length(s));        { 5  — baseline direct }
  writeln(Length(ps^));      { 5  — local pointer deref }
  writeln(Length(r.np^));    { 5  — pointer field deref }

  ps := @t;
  r.np := @t;
  writeln(Length(ps^));      { 2  — re-pointed local }
  writeln(Length(r.np^));    { 2  — re-pointed field }

  { Loop the deref read to surface any double-free / use-after-free. }
  ps := @s;
  for i := 1 to 1000 do
    if Length(ps^) <> 5 then
    begin
      writeln('FAIL');
      Halt(1);
    end;
  writeln('OK');
end.

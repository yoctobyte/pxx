program test_a_record_field_named_like_a_class_operation;
{ A RECORD field whose name collides with a TObject class-reference operation
  must stay a field read. The `obj.ClassName / obj.InheritsFrom(C)` arm asked
  only "is the name one of the operations and does the receiver have no METHOD
  of that name" — never whether the receiver was a record, nor whether it had a
  FIELD of that name. That was invisible while the set was ClassName /
  ClassType / InheritsFrom / ClassParent; `InstanceSize` joined it and IS a
  field of typinfo's TClassRTTI, so `cls^.InstanceSize` became
  __pxxRttiOf(cls^) — the record's first word read as an object's class
  pointer — and every RTTI program segfaulted.

  A class with no such member still reaches the operation, which is the row
  that proves the guard did not simply switch the arm off. (A CLASS field of
  one of these names is not asserted here: FPC rejects it outright — `Duplicate
  identifier "InstanceSize"` — because they are real TObject methods there, so
  there is no oracle for that row.) }

type
  TR = record
    ClassName:    Integer;
    InstanceSize: Int64;
    ClassParent:  Integer;
    ClassNameIs:  Integer;
  end;
  PR = ^TR;

  TPlain = class
  end;

var
  fails: Integer;

procedure Chk(const what: AnsiString; got, want: Int64);
begin
  if got = want then Writeln(what, ' ok')
  else begin Writeln(what, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

procedure ChkS(const what, got, want: AnsiString);
begin
  if got = want then Writeln(what, ' ok')
  else begin Writeln(what, ' FAIL got=[', got, '] want=[', want, ']'); Inc(fails); end;
end;

var
  r: TR;
  p: PR;
  pl: TPlain;

begin
  fails := 0;

  r.ClassName    := 1;
  r.InstanceSize := 2;
  r.ClassParent  := 3;
  r.ClassNameIs  := 4;

  { through the record variable }
  Chk('rec.classname',  r.ClassName,    1);
  Chk('rec.instsize',   r.InstanceSize, 2);
  Chk('rec.classparent',r.ClassParent,  3);
  Chk('rec.classnameis',r.ClassNameIs,  4);

  { through a POINTER to it — the spelling that crashed }
  p := @r;
  Chk('ptr.classname',  p^.ClassName,    1);
  Chk('ptr.instsize',   p^.InstanceSize, 2);
  Chk('ptr.classparent',p^.ClassParent,  3);
  Chk('ptr.classnameis',p^.ClassNameIs,  4);

  { writing through the pointer still reaches the field }
  p^.InstanceSize := 42;
  Chk('ptr.write',      r.InstanceSize, 42);

  { a class with NO member of the name still gets the operation }
  pl := TPlain.Create;
  ChkS('cls.op.name',   pl.ClassName,    'TPlain');
  Chk ('cls.op.size',   Ord(pl.InstanceSize > 0), 1);
  Chk ('cls.op.nameis', Ord(pl.ClassNameIs('TPlain')), 1);
  Chk ('cls.op.nameis2',Ord(pl.ClassNameIs('TR')),     0);
  pl.Free;

  if fails = 0 then Writeln('ALL OK') else Writeln('FAILURES: ', fails);
end.

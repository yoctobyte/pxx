program test_exceptobject_intrinsic;
{$mode objfpc}{$H+}
uses SysUtils;

type
  EMy = class(Exception) end;

procedure Report;
begin
  { Reached from inside a handler two frames down: the slot is process-wide,
    so the object is visible without threading it through a parameter. }
  if ExceptObject = nil then
    WriteLn('report: nil')
  else
    WriteLn('report: ' + ExceptObject.ClassName + '/' +
            Exception(ExceptObject).Message);
end;

begin
  if ExceptObject = nil then WriteLn('idle: nil') else WriteLn('idle: set');

  try
    raise EConvertError.Create('m1');
  except
    WriteLn('bare: ' + ExceptObject.ClassName + '/' +
            Exception(ExceptObject).Message);
  end;

  try
    raise EMy.Create('m2');
  except
    on e: Exception do
    begin
      WriteLn('bound: ' + e.ClassName + '/' + e.Message);
      WriteLn('same: ' + BoolToStr(ExceptObject = e, True));
    end;
  end;

  try
    raise EMy.Create('m3');
  except
    Report;
  end;

  try
    try
      raise EConvertError.Create('inner');
    except
      WriteLn('in: ' + ExceptObject.ClassName + '/' +
              Exception(ExceptObject).Message);
      raise EMy.Create('outer');
    end;
  except
    WriteLn('out: ' + ExceptObject.ClassName + '/' +
            Exception(ExceptObject).Message);
  end;

  WriteLn('end');
end.

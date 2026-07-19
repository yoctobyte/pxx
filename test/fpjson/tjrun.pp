{ pxx driver for fcl-json's testjsondata suite (OOP corpus rung 2).
  Walks the registry tree itself and runs one test at a time, printing the
  name BEFORE running it, so a crash names its test. No ITestListener — the
  interface-listener dispatch has its own bug (tracked separately). }
{$mode objfpc}
{$h+}
program tjrun;

uses
  Classes, SysUtils, fpcunit, testregistry, testjsondata;

var
  Res: TTestResult;

procedure RunTree(T: TTest);
var
  I: Integer;
  S: TTestSuite;
begin
  if T is TTestSuite then
  begin
    S := TTestSuite(T);
    Writeln('== suite ', S.TestName, ' (', S.Tests.Count, ')');
    for I := 0 to S.Tests.Count - 1 do
      RunTree(S.Test[I]);
  end
  else
  begin
    Writeln('> ', T.TestSuiteName, '.', T.TestName);
    T.Run(Res);
  end;
end;

var
  I: Integer;
  F: TTestFailure;
begin
  Writeln('registered tests: ', GetTestRegistry.CountTestCases);
  Res := TTestResult.Create;
  RunTree(GetTestRegistry);
  Writeln('run: ', Res.RunTests,
          '  failures: ', Res.NumberOfFailures,
          '  errors: ', Res.NumberOfErrors,
          '  ignored: ', Res.NumberOfIgnoredTests);
  for I := 0 to Res.Failures.Count - 1 do
  begin
    F := TTestFailure(Res.Failures[I]);
    Writeln('FAIL  ', F.AsString);
  end;
  for I := 0 to Res.Errors.Count - 1 do
  begin
    F := TTestFailure(Res.Errors[I]);
    Writeln('ERROR ', F.FailedMethodName, ' [', F.ExceptionClassName, ']: ',
            F.ExceptionMessage);
  end;
  Res.Free;
end.

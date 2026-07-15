program test_interface_com_default;
{$mode objfpc}{$H+}
{ Interfaces default to COM (FPC/Delphi parity): a plain objfpc interface is
  refcounted with NO {$interfaces com} directive, so dropping the last reference
  runs the destructor synchronously. Regression / anchor for
  bug-a-interface-release-on-last-ref-not-destroyed. `{$interfaces corba}` opts
  back into the lightweight non-refcounted flavour. }
type
  IThing = interface ['{B0000000-0000-0000-0000-000000000001}']
    procedure Go;
  end;
  TThing = class(TInterfacedObject, IThing)
    destructor Destroy; override;
    procedure Go;
  end;

destructor TThing.Destroy;
begin
  writeln('DTOR ran');
  inherited Destroy;
end;

procedure TThing.Go;
begin
end;

var
  it: IThing;
begin
  it := TThing.Create;
  writeln('before nil');
  it := nil;                { last reference dropped -> destructor MUST run here }
  writeln('after nil');
end.

unit uerrtmpl;
{ The TEMPLATE unit. Its method body names a type that does not exist, and the
  body is only ever type-checked when the template is SPECIALIZED — which
  happens in uerrinst.pas, a different file.

  The bad token is on line 22 of THIS file, and line 22 of uerrinst.pas is a
  comment that says so. That is the whole point of the pair. }
{$mode objfpc}
interface

type
  generic TBox<T> = class
  public
    Val: T;
    procedure Fill(n: Integer);
  end;

implementation

procedure TBox.Fill(n: Integer);
var
  q: TNoSuchTypeAnywhere;   { <-- line 22: the only real error site }
begin
  Val := n;
  q := n;
end;

end.

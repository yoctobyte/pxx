unit kwpadprobe;
{ A facade shaped exactly like tkinter's grid(): several OPTIONAL options, one
  of them a Variant that legitimately takes a tuple. The tkinter facade itself
  is correct and is not what this probes -- this is the smallest unit carrying
  the shape, so the test does not depend on lib/pcl.

  Deliberately ordered ordinal, then STRING, then Variant: a keyword call that
  skips `sticky` lands the Variant argument on the string's slot if the
  speculative overload probe indexes its arguments positionally.
  bug-n-a-methods-keyword-call-drops-a-tuple-argument-when-an-earlier-default-is-skipped }
interface

type
  TWidget = class
  public
    constructor Create;
    procedure grid(row: Integer = -1; const sticky: AnsiString = '';
                   const padx: Variant = 0; const pady: Variant = 0);
  end;

procedure freegrid(row: Integer = -1; const sticky: AnsiString = '';
                   const padx: Variant = 0; const pady: Variant = 0);

implementation

constructor TWidget.Create;
begin
end;

procedure TWidget.grid(row: Integer = -1; const sticky: AnsiString = '';
                       const padx: Variant = 0; const pady: Variant = 0);
begin
  writeln('grid  row=', row, ' sticky=[', sticky, '] padx=', padx, ' pady=', pady);
end;

procedure freegrid(row: Integer = -1; const sticky: AnsiString = '';
                   const padx: Variant = 0; const pady: Variant = 0);
begin
  writeln('free  row=', row, ' sticky=[', sticky, '] padx=', padx, ' pady=', pady);
end;

end.

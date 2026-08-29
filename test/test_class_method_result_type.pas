program test_class_method_result_type;
{ A CLASS method's call result must carry the RETURN type's record into the
  selector chain, not the receiver's. The instance-reached arm updated `node`
  and `tk` but not `recName`, so the receiver's class survived: `f.GetSvc.M`
  looked M up on f's class. When only the returned class had M that was a
  spurious "no such member"; when BOTH had one it silently called the WRONG
  method on the wrong object, which fpc rejects outright.
  bug-p-a-class-method-call-keeps-the-receivers-class }
{$MODE OBJFPC}
type
  TSvc = class
    function Tag: Integer;              { instance method on the RESULT   }
    class function CTag: Integer;       { class method on the RESULT      }
  end;
  TFactory = class
    class function MakeC: TSvc;         { CLASS function returning TSvc   }
    function MakeI: TSvc;               { instance fn, the working sibling}
  end;

function TSvc.Tag: Integer;
begin Tag := 7; end;

class function TSvc.CTag: Integer;
begin CTag := 9; end;

class function TFactory.MakeC: TSvc;
begin MakeC := TSvc.Create; end;

function TFactory.MakeI: TSvc;
begin MakeI := TSvc.Create; end;

var
  f: TFactory;
  s: TSvc;
begin
  f := TFactory.Create;
  { the arm that was broken: CLASS function reached through an INSTANCE }
  Writeln('class fn  : ', f.MakeC.Tag);
  { a class method on that same result — the chain must keep walking }
  Writeln('class meth: ', f.MakeC.CTag);
  { the sibling that always worked; a fix must not trade one for the other }
  Writeln('inst fn   : ', f.MakeI.Tag);
  { and the split spelling stays correct }
  s := f.MakeC;
  Writeln('split     : ', s.Tag);
end.

unit varobj;
{$mode objfpc}
{ A Pascal routine that writes an object into a var/out parameter, called
  from NilPy. See test_nilpy_an_object_var_param_into_a_none_name_is_refused_fail.npy. }
interface
type
  TB = class
    v: Integer;
    constructor Create(av: Integer);
  end;
procedure NewInto(var o: TB; v: Integer);
procedure NewOut(out o: TB; v: Integer);
implementation
constructor TB.Create(av: Integer); begin v := av; end;
procedure NewInto(var o: TB; v: Integer); begin o := TB.Create(v); end;
procedure NewOut(out o: TB; v: Integer); begin o := TB.Create(v); end;
end.

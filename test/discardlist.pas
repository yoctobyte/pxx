{ Helper unit for test_a_discarded_class_result_from_a_pascal_call_is_released.npy:
  a Pascal function returning a FRESH TPyList, which the NilPy caller owns. }
unit discardlist; {$MODE PXX}
interface uses pylib; function read: TPyList;
implementation
function read: TPyList; var i: Integer; v: Variant;
begin Result := TPyList.Create; for i := 1 to 64 do begin v := i; Result.append(v); end; end;
end.

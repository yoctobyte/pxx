{ A unit whose only job is to declare a class-like type named `Text`, colliding
  with the RTL's Text FILE record. Paired with importordertextuse.pas by
  test_nilpy_import_order_does_not_rebind_a_type.npy.
  bug-nilpy-import-order-leaks-a-class-name-into-a-later-compiled-rtl-unit }
unit importordertextcls;
interface
type Text = class public y: Integer; end;
implementation
end.

unit classes;

{ RTL Classes compatibility stub. The streaming runtime lives in classes_lite
  (TComponent, TReader); the LCL widgetset builds on that. The minimal
  helloworld references no Classes symbol directly (TObject is built in), so
  this only needs to satisfy `uses`. Grow toward classes_lite parity as user
  code needs TStringList/TStream/etc. }

interface

implementation

end.

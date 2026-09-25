{ The json and calc library units leaked on paths the demos take every run.
  JSONParse on a rejected document dropped its reader and the partial tree
  (2, 7 and 1 blocks for the three shapes below), and calc's Eval never freed
  its reader (1 per call). Neither is visible in any output; the leak row that
  runs this (assert_no_leak, -dPXX_ALLOC_CENSUS) is what sees it. Found by the
  2026-09-25 leak sweep over docs/examples, where jsondemo and calcdemo grew
  by 10 and 24 live blocks per run. }
program test_b_json_calc_error_paths_free;
uses json, calc, sysutils;
var
  i, errs: Integer;
  v: TJSONValue;
  good: Boolean;
  sum: Int64;
begin
  errs := 0;
  sum := 0;
  for i := 1 to 300 do
  begin
    try
      v := JSONParse('{"a":}');
    except
      on e: EJSONError do Inc(errs);
    end;
    try
      v := JSONParse('[1,2');
    except
      on e: EJSONError do Inc(errs);
    end;
    try
      v := JSONParse('{} junk');
    except
      on e: EJSONError do Inc(errs);
    end;
    v := JSONParse('{"k":[1,{"z":2}]}');
    v.FreeTree;
    sum := sum + Eval('2*(3+4)', good);
    Eval('2+', good);
  end;
  WriteLn(errs, ' ', sum);
end.

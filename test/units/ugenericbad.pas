{ A generic whose body does not compile, used only by
  test_diag_in_specialized_body_names_the_template_file_fail.pas: the error is
  inside the TEMPLATE, so it surfaces at the point the SPECIALIZATION is spliced
  into the using file. That splice is the whole subject -- the pasted tokens
  keep this file's line numbers, and used to inherit the other file's name.
  bug-p-a-diagnostic-in-a-used-unit-names-the-wrong-source-file }
unit ugenericbad;

interface

type
  generic TCell<T> = class
    V: T;
    function Get: T;
  end;

implementation

function TCell.Get: T;
begin
  Get := V + no_such_name_in_the_template;
end;

end.

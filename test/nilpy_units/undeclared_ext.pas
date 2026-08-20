{ THE NEGATIVE HALF of the extension-module carve-out. This unit binds the cpyext
  runtime exactly as the six real extension modules do — and carries no
  extension-module directive. A bare `import undeclared_ext` must therefore
  still be refused:
  the DECLARATION is what makes a unit a Python module, and the runtime is only
  the check on that declaration. Without this, the carve-out could quietly widen
  to "anything under a -Fu root that touches CPython", which is the rule it was
  carved out of.
  feature-n-a-cpyext-extension-module-is-bare-importable-not-a-pascal-unit }
unit undeclared_ext;

interface

uses pxxcio, '../../lib/cpyext/src/pyruntime.c';

function nine: Integer;

implementation

function nine: Integer;
begin
  nine := 9;
end;

end.

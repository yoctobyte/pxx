program lib_paths;
{ Smoke for the SysUtils path helpers. }
uses sysutils;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

begin
  SayBool('name',        ExtractFileName('/a/b/c.txt') = 'c.txt');
  SayBool('name-nodir',  ExtractFileName('file.x') = 'file.x');
  SayBool('path',        ExtractFilePath('/a/b/c.txt') = '/a/b/');
  SayBool('path-none',   ExtractFilePath('file.x') = '');
  SayBool('dir',         ExtractFileDir('/a/b/c.txt') = '/a/b');
  SayBool('ext',         ExtractFileExt('/a/b/c.txt') = '.txt');
  SayBool('ext-none',    ExtractFileExt('/a/b/c') = '');
  SayBool('ext-dotdir',  ExtractFileExt('/a.b/c') = '');
  SayBool('change',      ChangeFileExt('/a/b.txt', '.md') = '/a/b.md');
  SayBool('change-add',  ChangeFileExt('/a/b', '.md') = '/a/b.md');
  SayBool('incl',        IncludeTrailingPathDelimiter('/a/b') = '/a/b/');
  SayBool('incl-noop',   IncludeTrailingPathDelimiter('/a/b/') = '/a/b/');
  SayBool('excl',        ExcludeTrailingPathDelimiter('/a/b/') = '/a/b');
  SayBool('excl-noop',   ExcludeTrailingPathDelimiter('/a/b') = '/a/b');
end.

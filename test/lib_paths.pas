program lib_paths;
{ Smoke for the SysUtils path helpers.

  This file compiles under FPC too, and the dotfile rows below were read off an
  FPC build of it (bug-b-dotfile-treated-as-extension). }
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

  { DOTFILES: a dot that is the first character of the BASENAME starts a hidden
    file, it does not introduce an extension. Nothing here had a dotfile case,
    which is how both functions carried the same wrong rule. }
  SayBool('ext-dotfile',      ExtractFileExt('.hidden') = '');
  SayBool('ext-dotfile-dir',  ExtractFileExt('/a/.hidden') = '');
  { a dotfile that really does have an extension keeps it }
  SayBool('ext-dotfile-ext',  ExtractFileExt('/a/.hidden.txt') = '.txt');
  { a trailing dot IS an (empty) extension, per FPC }
  SayBool('ext-trailing-dot', ExtractFileExt('trailing.') = '.');
  { the destructive one: this returned '.bak', losing the filename entirely }
  SayBool('change-dotfile',   ChangeFileExt('.hidden', '.bak') = '.hidden.bak');
  SayBool('change-dotfile-d', ChangeFileExt('/a/.hidden', '.bak') = '/a/.hidden.bak');
  SayBool('incl',        IncludeTrailingPathDelimiter('/a/b') = '/a/b/');
  SayBool('incl-noop',   IncludeTrailingPathDelimiter('/a/b/') = '/a/b/');
  SayBool('excl',        ExcludeTrailingPathDelimiter('/a/b/') = '/a/b');
  SayBool('excl-noop',   ExcludeTrailingPathDelimiter('/a/b') = '/a/b');
end.

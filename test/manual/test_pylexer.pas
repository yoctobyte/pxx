program test_pylexer;
{$mode objfpc}{$H+}
{$CASESENSITIVE ON}
{$NESTEDCOMMENTS ON}

uses SysUtils, BaseUnix;

{ Inclusions to pull in existing compiler infrastructure }
{$include compiler/defs.inc}
{$include compiler/lexer.inc}
{$include compiler/pylexer.inc}

procedure DumpTokens;
var
  i, off, len, j: Integer;
  k: TTokenKind;
  s: AnsiString;
begin
  writeln('--- Token Dump (Count: ', TokCount, ') ---');
  for i := 0 to TokCount - 1 do
  begin
    k := Tokens[i].Kind;
    write('Token ', i, ': Kind=');
    case k of
      tkEOF: write('tkEOF');
      tkIdent: write('tkIdent');
      tkInteger: write('tkInteger');
      tkString: write('tkString');
      tkIndent: write('tkIndent');
      tkDedent: write('tkDedent');
      tkNewline: write('tkNewline');
      tkIf: write('tkIf');
      tkElse: write('tkElse');
      tkTrue: write('tkTrue');
      tkFalse: write('tkFalse');
      tkNil: write('tkNil');
      tkFunction: write('tkFunction');
      tkExit: write('tkExit');
      tkWhile: write('tkWhile');
      tkClass: write('tkClass');
      tkBreak: write('tkBreak');
      tkTry: write('tkTry');
      tkExcept: write('tkExcept');
      tkFinally: write('tkFinally');
      tkRaise: write('tkRaise');
      tkPlus: write('tkPlus');
      tkMinus: write('tkMinus');
      tkStar: write('tkStar');
      tkSlash: write('tkSlash');
      tkDiv: write('tkDiv');
      tkMod: write('tkMod');
      tkLParen: write('tkLParen');
      tkRParen: write('tkRParen');
      tkLBrack: write('tkLBrack');
      tkRBrack: write('tkRBrack');
      tkColon: write('tkColon');
      tkComma: write('tkComma');
      tkDot: write('tkDot');
      tkSemicolon: write('tkSemicolon');
      tkAssign: write('tkAssign');
      tkEq: write('tkEq');
      tkNeq: write('tkNeq');
      tkLt: write('tkLt');
      tkLe: write('tkLe');
      tkGt: write('tkGt');
      tkGe: write('tkGe');
      tkwriteln: write('tkPrint');
      tkFloat: write('tkFloat');
      else write('other (', Ord(k), ')');
    end;
    write(', Line=', Tokens[i].Line, ', IVal=', Tokens[i].IVal);
    if (k = tkIdent) or (k = tkString) then
    begin
      s := '';
      off := Tokens[i].SOffset;
      len := Tokens[i].SLen;
      for j := 0 to len - 1 do
        AppendChar(s, TokChars[off + j]);
      write(', SVal="', s, '"');
    end;
    writeln;
  end;
  writeln('--------------------------------------');
end;

procedure TestNestedBlocks;
begin
  writeln('=== Test 1: Nested Blocks ===');
  Source := 
    'if True:'#10 +
    '    x = 1'#10 +
    '    if False:'#10 +
    '        y = 2'#10 +
    '    z = 3'#10;
  PyLexAll(True);
  DumpTokens;
end;

procedure TestBlankAndCommentLines;
begin
  writeln('=== Test 2: Blank and Comment Lines ===');
  Source := 
    'x = 1'#10 +
    '# this is a comment'#10 +
    ''#10 +
    'y = 2'#10;
  PyLexAll(True);
  DumpTokens;
end;

procedure TestMultiLineList;
begin
  writeln('=== Test 3: Multi-Line List Literal ===');
  Source := 
    'x = ['#10 +
    '    1,'#10 +
    '    2,'#10 +
    '    3'#10 +
    ']'#10;
  PyLexAll(True);
  DumpTokens;
end;

procedure TestTabSpaceMix;
begin
  writeln('=== Test 4: Tab/Space Mix (Expected: Error) ===');
  Source := 
    'def foo():'#10 +
    '    x = 1'#10 +
    #9'y = 2'#10;
  PyLexAll(True);
  DumpTokens;
end;

var
  testNum: Integer;
begin
  if ParamCount < 1 then
  begin
    writeln('Usage: test_pylexer <test-number>');
    Halt(1);
  end;
  testNum := StrToInt(ParamStr(1));
  case testNum of
    1: TestNestedBlocks;
    2: TestBlankAndCommentLines;
    3: TestMultiLineList;
    4: TestTabSpaceMix;
    else writeln('Invalid test number');
  end;
end.

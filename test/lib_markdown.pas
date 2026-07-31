{ markdown.pas against the CommonMark reference. Every expectation below is
  markdown-it-py's `commonmark` output for the same source, normalised only by
  collapsing whitespace BETWEEN tags — not this unit's own output read back.
  python-markdown agrees on all of them but one, where it merges an ordered
  list into a preceding unordered one and CommonMark does not; that case is
  kept, with CommonMark's answer.

  The corpus covers exactly what lib/rtl/markdown.pas claims to implement.
  Anything outside the claimed subset is not tested here because the unit
  documents that it renders such markup literally. }
program lib_markdown;
uses sysutils, markdown;

var fails: Integer;

{ collapse whitespace between tags, so a difference in layout is not a failure }
function Norm(const s: AnsiString): AnsiString;
var i, n: Integer; r: AnsiString; sp: Boolean;
begin
  r := ''; i := 1; n := Length(s);
  while (i <= n) and (s[i] in [' ', #9, #10, #13]) do Inc(i);
  while (n >= i) and (s[n] in [' ', #9, #10, #13]) do Dec(n);
  while i <= n do
  begin
    if (s[i] = '>') then
    begin
      r := r + '>'; Inc(i);
      sp := False;
      while (i <= n) and (s[i] in [' ', #9, #10, #13]) do begin sp := True; Inc(i); end;
      if sp and (i <= n) and (s[i] <> '<') then r := r + ' ';
    end
    else begin r := r + s[i]; Inc(i); end;
  end;
  Norm := r;
end;

procedure Chk(const what, src, want: AnsiString);
var got: AnsiString;
begin
  got := Norm(MarkdownToHtml(src));
  if got = Norm(want) then WriteLn(what, '=ok')
  else begin
    WriteLn(what, ' FAIL');
    WriteLn('  got  ', got);
    WriteLn('  want ', Norm(want));
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  Chk('h',
      '# H1' + #10 + '## H2' + #10 + '### H3' + #10 + '#### H4' + #10 + '##### H5' + #10 + '###### H6' + #10,
      '<h1>H1</h1><h2>H2</h2><h3>H3</h3><h4>H4</h4><h5>H5</h5><h6>H6</h6>');
  Chk('p',
      'First paragraph' + #10 + 'continued on a second line.' + #10 + #10 + 'Second paragraph.' + #10,
      '<p>First paragraph' + #10 + 'continued on a second line.</p><p>Second paragraph.</p>');
  Chk('inline',
      'Some **bold**, some *italic*, some `code`, a [link](https://example.com/a_b) and' + #10 + 'a bare https://example.com/x URL.' + #10 + #10 + 'Escapes: 5 < 6 & 7 > 2.' + #10,
      '<p>Some <strong>bold</strong>, some <em>italic</em>, some <code>code</code>, a <a href="https://example.com/a_b">link</a> and' + #10 + 'a bare https://example.com/x URL.</p><p>Escapes: 5 &lt; 6 &amp; 7 &gt; 2.</p>');
  Chk('list',
      '- alpha' + #10 + '- beta' + #10 + '- gamma' + #10,
      '<ul><li>alpha</li><li>beta</li><li>gamma</li></ul>');
  Chk('olist',
      '1. one' + #10 + '2. two' + #10 + '3. three' + #10,
      '<ol><li>one</li><li>two</li><li>three</li></ol>');
  Chk('quote',
      '> quoted line one' + #10 + '> quoted line two' + #10,
      '<blockquote><p>quoted line one' + #10 + 'quoted line two</p></blockquote>');
  Chk('fence',
      '```' + #10 + 'int main(void) { return 0; }' + #10 + '```' + #10,
      '<pre><code>int main(void) { return 0; }' + #10 + '</code></pre>');
  Chk('indent',
      '    indented code' + #10 + '    second line' + #10,
      '<pre><code>indented code' + #10 + 'second line' + #10 + '</code></pre>');
  Chk('rule',
      'before' + #10 + #10 + '---' + #10 + #10 + 'after' + #10,
      '<p>before</p><hr /><p>after</p>');
  Chk('x1',
      '# Heading with `code` and **bold**' + #10 + #10 + 'Text with a [link](http://a.b/c) and *em* mid-sentence.' + #10,
      '<h1>Heading with <code>code</code> and <strong>bold</strong></h1><p>Text with a <a href="http://a.b/c">link</a> and <em>em</em> mid-sentence.</p>');
  Chk('x2',
      '- item with **bold**' + #10 + '- item with `code`' + #10 + '- item with [link](http://x.y)' + #10,
      '<ul><li>item with <strong>bold</strong></li><li>item with <code>code</code></li><li>item with <a href="http://x.y">link</a></li></ul>');
  Chk('x3',
      '1. first item' + #10 + '1. second item' + #10 + '1. third item' + #10,
      '<ol><li>first item</li><li>second item</li><li>third item</li></ol>');
  Chk('x4',
      '```' + #10 + 'a & b < c > d' + #10 + '```' + #10,
      '<pre><code>a &amp; b &lt; c &gt; d' + #10 + '</code></pre>');
  Chk('x5',
      'Para one.' + #10 + #10 + '> quote' + #10 + #10 + 'Para two.' + #10,
      '<p>Para one.</p><blockquote><p>quote</p></blockquote><p>Para two.</p>');
  Chk('x6',
      '***' + #10 + #10 + '___' + #10 + #10 + '- - -' + #10,
      '<hr /><hr /><hr />');
  Chk('x7',
      'A line with a literal asterisk 2 * 3 * 4 and an underscore a_b_c.' + #10,
      '<p>A line with a literal asterisk 2 * 3 * 4 and an underscore a_b_c.</p>');
  Chk('doc1',
      '# Title' + #10 + #10 + 'A paragraph with **strong** and *emphasis* and `code` and a [link](http://example.com).' + #10 + #10 + '## Section' + #10 + #10 + '- one' + #10 + '- two' + #10 + '- three' + #10 + #10 + '1. first' + #10 + '2. second' + #10 + #10 + '> a quote' + #10 + #10 + '```' + #10 + 'fenced code' + #10 + '```' + #10 + #10 + '---' + #10 + #10 + 'Another paragraph.' + #10,
      '<h1>Title</h1><p>A paragraph with <strong>strong</strong> and <em>emphasis</em> and <code>code</code> and a <a href="http://example.com">link</a>.</p><h2>Section</h2><ul><li>one</li><li>two</li><li>three</li></ul><ol><li>first</li><li>second</li></ol><blockquote><p>a quote</p></blockquote><pre><code>fenced code' + #10 + '</code></pre><hr /><p>Another paragraph.</p>');
  if fails = 0 then WriteLn('MARKDOWN OK')
  else WriteLn('MARKDOWN FAILED ', fails);
end.

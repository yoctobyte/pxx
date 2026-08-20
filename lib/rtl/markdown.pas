{ SPDX-License-Identifier: Zlib }
unit markdown;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Markdown -> HTML, named so that Python's `import markdown` resolves here and
  `markdown.markdown(text)` is the call an application writes.

  THE SUBSET, stated plainly: ATX headings, paragraphs, fenced and indented
  code, unordered and ordered lists, blockquotes, horizontal rules, and the
  inline forms `code`, **strong**, *emphasis*, [text](url) and bare URLs. That
  is what a README-shaped document uses, and it is what songformatter's help
  window feeds to tkhtmlview.

  It is NOT CommonMark. Setext headings, reference links, nested lists, HTML
  blocks, tables and the rest of the spec are not implemented, and a document
  using them renders as if the markup were literal text rather than silently
  dropping content. The ticket that asked for this (feature-lib-markdown)
  recommends vendoring md4c and compiling it with the C frontend for a real
  implementation; this is the fallback that ticket names, and it says so here
  rather than pretending to be complete.

  Extensions are ACCEPTED and mostly ignored — the list an application passes
  (`extensions=["markdown.extensions.nl2br", ...]`) is scanned for `nl2br`,
  which is honoured; anything else is a no-op, because the output of a subset
  renderer is already an approximation and a silently-missing extension would
  be no worse than the subset itself. `toc` emits heading `id` attributes,
  which is the part of it a help window can actually use. }

interface

uses pylib;   { the extensions list arrives as a Python list }

{ The Python entry point. `extensions` is a Python list of names; omitted
  means none. }
function markdown(const text: AnsiString; const extensions: Variant = 0): AnsiString;

{ The Pascal spelling, with the two options named. }
function MarkdownToHtml(const text: AnsiString; nl2br: Boolean = False;
                        headingIds: Boolean = False): AnsiString;

{ Escape a string for HTML text content (&, <, >). Exposed because a caller
  building HTML around the rendered fragment needs the same rule. }
function HtmlEscape(const s: AnsiString): AnsiString;

implementation

function HtmlEscape(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if c = '&' then r := r + '&amp;'
    else if c = '<' then r := r + '&lt;'
    else if c = '>' then r := r + '&gt;'
    else r := r + c;
  end;
  HtmlEscape := r;
end;

{ ---- line helpers ------------------------------------------------------- }

function MdTrimRight(const s: AnsiString): AnsiString;
var n: Integer;
begin
  n := Length(s);
  while (n > 0) and ((s[n] = ' ') or (s[n] = #9) or (s[n] = #13)) do Dec(n);
  MdTrimRight := Copy(s, 1, n);
end;

function MdTrimLeft(const s: AnsiString): AnsiString;
var i: Integer;
begin
  i := 1;
  while (i <= Length(s)) and ((s[i] = ' ') or (s[i] = #9)) do Inc(i);
  MdTrimLeft := Copy(s, i, Length(s) - i + 1);
end;

function MdTrim(const s: AnsiString): AnsiString;
begin
  MdTrim := MdTrimLeft(MdTrimRight(s));
end;

{ leading spaces, tabs counted as 4 }
function MdIndent(const s: AnsiString): Integer;
var i, n: Integer;
begin
  n := 0;
  i := 1;
  while i <= Length(s) do
  begin
    if s[i] = ' ' then Inc(n)
    else if s[i] = #9 then n := n + 4
    else break;
    Inc(i);
  end;
  MdIndent := n;
end;

function MdIsBlank(const s: AnsiString): Boolean;
begin
  MdIsBlank := MdTrim(s) = '';
end;

{ `---`, `***` or `___`, three or more, nothing else on the line }
function MdIsRule(const s: AnsiString): Boolean;
var t: AnsiString; i, n: Integer; c: Char;
begin
  MdIsRule := False;
  t := MdTrim(s);
  if Length(t) < 3 then Exit;
  c := t[1];
  if (c <> '-') and (c <> '*') and (c <> '_') then Exit;
  n := 0;
  for i := 1 to Length(t) do
  begin
    if t[i] = c then Inc(n)
    else if t[i] <> ' ' then Exit;
  end;
  MdIsRule := n >= 3;
end;

{ ```lang or ~~~ }
function MdIsFence(const s: AnsiString): Boolean;
var t: AnsiString;
begin
  t := MdTrimLeft(s);
  MdIsFence := (Copy(t, 1, 3) = '```') or (Copy(t, 1, 3) = '~~~');
end;

{ `# ` .. `###### `; 0 when the line is not a heading }
function MdHeadingLevel(const s: AnsiString): Integer;
var t: AnsiString; n: Integer;
begin
  MdHeadingLevel := 0;
  t := MdTrimLeft(s);
  n := 0;
  while (n < Length(t)) and (t[n + 1] = '#') do Inc(n);
  if (n < 1) or (n > 6) then Exit;
  if (Length(t) > n) and (t[n + 1] <> ' ') then Exit;
  MdHeadingLevel := n;
end;

{ `- `, `* ` or `+ ` after optional indent }
function MdIsBullet(const s: AnsiString): Boolean;
var t: AnsiString;
begin
  MdIsBullet := False;
  t := MdTrimLeft(s);
  if Length(t) < 2 then Exit;
  if (t[1] = '-') or (t[1] = '*') or (t[1] = '+') then
    MdIsBullet := t[2] = ' ';
end;

{ `1. ` / `12) ` — returns the length of the marker, or 0 }
function MdOrderedMarker(const s: AnsiString): Integer;
var t: AnsiString; i: Integer;
begin
  MdOrderedMarker := 0;
  t := MdTrimLeft(s);
  i := 1;
  while (i <= Length(t)) and (t[i] >= '0') and (t[i] <= '9') do Inc(i);
  if i = 1 then Exit;                          { no digits }
  if i > Length(t) then Exit;
  if (t[i] <> '.') and (t[i] <> ')') then Exit;
  if (i + 1 > Length(t)) or (t[i + 1] <> ' ') then Exit;
  MdOrderedMarker := i + 1;
end;

{ the text of a list item, marker removed }
function MdItemText(const s: AnsiString): AnsiString;
var t: AnsiString; n: Integer;
begin
  t := MdTrimLeft(s);
  n := MdOrderedMarker(s);
  if n > 0 then MdItemText := MdTrim(Copy(t, n + 1, Length(t) - n))
  else MdItemText := MdTrim(Copy(t, 3, Length(t) - 2));
end;

{ ---- inline ------------------------------------------------------------- }

{ A heading's `id`, the way python-markdown's toc extension builds one:
  lowercased, non-alphanumerics to '-', runs collapsed. }
function MdSlug(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char; lastDash: Boolean;
begin
  r := '';
  lastDash := True;                 { suppress a leading dash }
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if ((c >= 'a') and (c <= 'z')) or ((c >= '0') and (c <= '9')) then
    begin
      r := r + c;
      lastDash := False;
    end
    else if (c >= 'A') and (c <= 'Z') then
    begin
      r := r + Chr(Ord(c) + 32);
      lastDash := False;
    end
    else if not lastDash then
    begin
      r := r + '-';
      lastDash := True;
    end;
  end;
  while (Length(r) > 0) and (r[Length(r)] = '-') do r := Copy(r, 1, Length(r) - 1);
  MdSlug := r;
end;

{ `[text](url)` starting at i (s[i] = '['). Returns the length consumed, or 0.
  The rendered anchor goes into `out`. }
function MdInlineLink(const s: AnsiString; i: Integer; var outHtml: AnsiString): Integer;
var j, k, depth: Integer; label_, url: AnsiString;
begin
  MdInlineLink := 0;
  j := i + 1;
  depth := 1;
  while (j <= Length(s)) and (depth > 0) do
  begin
    if s[j] = '[' then Inc(depth)
    else if s[j] = ']' then Dec(depth);
    if depth > 0 then Inc(j);
  end;
  if (j > Length(s)) or (depth > 0) then Exit;
  if (j + 1 > Length(s)) or (s[j + 1] <> '(') then Exit;
  label_ := Copy(s, i + 1, j - i - 1);
  k := j + 2;
  while (k <= Length(s)) and (s[k] <> ')') do Inc(k);
  if k > Length(s) then Exit;
  url := Copy(s, j + 2, k - j - 2);
  outHtml := '<a href="' + HtmlEscape(url) + '">' + HtmlEscape(label_) + '</a>';
  MdInlineLink := k - i + 1;
end;

{ CommonMark's flanking rules, in the only two forms this subset needs: a
  delimiter run OPENS emphasis only when the character after it is not
  whitespace, and CLOSES only when the character before it is not whitespace.
  `_` additionally never works INSIDE a word, so `a_b_c` is a name and not
  emphasis. Without these, ordinary prose was mangled: `2 * 3 * 4` came back as
  `2 <em> 3 </em> 4`. }
function MdIsSpaceCh(c: Char): Boolean;
begin
  MdIsSpaceCh := (c = ' ') or (c = #9);
end;

function MdIsWordCh(c: Char): Boolean;
begin
  MdIsWordCh := (c in ['A'..'Z', 'a'..'z', '0'..'9', '_']);
end;

{ Inline markup inside one already-block-classified run of text. Emphasis is
  handled by pairing: an opener with no closer stays literal, which is what
  keeps a lone `*` in prose from eating the rest of the paragraph. }
function MdInline(const s: AnsiString): AnsiString;
var i, j, n: Integer; r, piece: AnsiString; c: Char; canOpen: Boolean;
begin
  r := '';
  i := 1;
  while i <= Length(s) do
  begin
    c := s[i];
    if c = '\' then
    begin
      { a backslash escape: the next character is literal }
      if i < Length(s) then
      begin
        r := r + HtmlEscape(Copy(s, i + 1, 1));
        Inc(i, 2);
      end
      else
      begin
        r := r + '\';
        Inc(i);
      end;
    end
    else if c = '`' then
    begin
      j := i + 1;
      while (j <= Length(s)) and (s[j] <> '`') do Inc(j);
      if j > Length(s) then
      begin
        r := r + HtmlEscape('`');
        Inc(i);
      end
      else
      begin
        r := r + '<code>' + HtmlEscape(Copy(s, i + 1, j - i - 1)) + '</code>';
        i := j + 1;
      end;
    end
    else if (c = '*') and (i < Length(s)) and (s[i + 1] = '*') then
    begin
      { `2 ** 3` is arithmetic: an opener followed by a space opens nothing }
      if (i + 1 >= Length(s)) or MdIsSpaceCh(s[i + 2]) then j := 0
      else
      begin
        j := i + 2;
        while (j < Length(s)) and
              not ((s[j] = '*') and (s[j + 1] = '*') and (not MdIsSpaceCh(s[j - 1]))) do
          Inc(j);
        if j >= Length(s) then j := 0;
      end;
      if j = 0 then
      begin
        r := r + HtmlEscape('*');
        Inc(i);
      end
      else
      begin
        r := r + '<strong>' + MdInline(Copy(s, i + 2, j - i - 2)) + '</strong>';
        i := j + 2;
      end;
    end
    else if (c = '*') or (c = '_') then
    begin
      canOpen := (i < Length(s)) and (not MdIsSpaceCh(s[i + 1]));
      if (c = '_') and (i > 1) and MdIsWordCh(s[i - 1]) then canOpen := False;
      j := 0;
      if canOpen then
      begin
        j := i + 2;   { an empty span (`**` handled above, `__` / `*` `*`) never closes }
        while j <= Length(s) do
        begin
          if (s[j] = c) and (not MdIsSpaceCh(s[j - 1])) and
             not ((c = '_') and (j < Length(s)) and MdIsWordCh(s[j + 1])) then Break;
          Inc(j);
        end;
        if j > Length(s) then j := 0;
      end;
      if j = 0 then
      begin
        r := r + HtmlEscape(Copy(s, i, 1));
        Inc(i);
      end
      else
      begin
        r := r + '<em>' + MdInline(Copy(s, i + 1, j - i - 1)) + '</em>';
        i := j + 1;
      end;
    end
    else if c = '[' then
    begin
      piece := '';
      n := MdInlineLink(s, i, piece);
      if n > 0 then
      begin
        r := r + piece;
        i := i + n;
      end
      else
      begin
        r := r + HtmlEscape('[');
        Inc(i);
      end;
    end
    else
    begin
      r := r + HtmlEscape(Copy(s, i, 1));
      Inc(i);
    end;
  end;
  MdInline := r;
end;

{ ---- blocks ------------------------------------------------------------- }

function MarkdownToHtml(const text: AnsiString; nl2br: Boolean;
                        headingIds: Boolean): AnsiString;
var lines: array of AnsiString;
    nLines, i, start, lvl, mk: Integer;
    r, cur, body, para, fenceLang: AnsiString;
    inPara: Boolean;
begin
  { split into lines, keeping empty ones (they end paragraphs) }
  nLines := 0;
  SetLength(lines, 0);
  start := 1;
  for i := 1 to Length(text) do
    if text[i] = #10 then
    begin
      SetLength(lines, nLines + 1);
      lines[nLines] := MdTrimRight(Copy(text, start, i - start));
      Inc(nLines);
      start := i + 1;
    end;
  if start <= Length(text) then
  begin
    SetLength(lines, nLines + 1);
    lines[nLines] := MdTrimRight(Copy(text, start, Length(text) - start + 1));
    Inc(nLines);
  end;

  r := '';
  para := '';
  inPara := False;
  i := 0;
  while i < nLines do
  begin
    cur := lines[i];

    { a blank line closes an open paragraph }
    if MdIsBlank(cur) then
    begin
      if inPara then
      begin
        r := r + '<p>' + para + '</p>' + #10;
        para := '';
        inPara := False;
      end;
      Inc(i);
      Continue;
    end;

    { fenced code — verbatim until the closing fence or the end }
    if MdIsFence(cur) then
    begin
      if inPara then
      begin
        r := r + '<p>' + para + '</p>' + #10;
        para := '';
        inPara := False;
      end;
      fenceLang := MdTrim(Copy(MdTrimLeft(cur), 4, Length(cur)));
      body := '';
      Inc(i);
      while (i < nLines) and not MdIsFence(lines[i]) do
      begin
        body := body + HtmlEscape(lines[i]) + #10;
        Inc(i);
      end;
      if i < nLines then Inc(i);            { the closing fence }
      if fenceLang <> '' then
        r := r + '<pre><code class="language-' + HtmlEscape(fenceLang) + '">'
             + body + '</code></pre>' + #10
      else
        r := r + '<pre><code>' + body + '</code></pre>' + #10;
      Continue;
    end;

    { heading }
    lvl := MdHeadingLevel(cur);
    if lvl > 0 then
    begin
      if inPara then
      begin
        r := r + '<p>' + para + '</p>' + #10;
        para := '';
        inPara := False;
      end;
      body := MdTrim(Copy(MdTrimLeft(cur), lvl + 1, Length(cur)));
      { a closing run of #s is decoration }
      while (Length(body) > 0) and (body[Length(body)] = '#') do
        body := MdTrimRight(Copy(body, 1, Length(body) - 1));
      if headingIds then
        r := r + '<h' + Chr(Ord('0') + lvl) + ' id="' + MdSlug(body) + '">'
             + MdInline(body) + '</h' + Chr(Ord('0') + lvl) + '>' + #10
      else
        r := r + '<h' + Chr(Ord('0') + lvl) + '>' + MdInline(body)
             + '</h' + Chr(Ord('0') + lvl) + '>' + #10;
      Inc(i);
      Continue;
    end;

    { horizontal rule — tested BEFORE bullets, since `---` is also `-` }
    if MdIsRule(cur) then
    begin
      if inPara then
      begin
        r := r + '<p>' + para + '</p>' + #10;
        para := '';
        inPara := False;
      end;
      r := r + '<hr />' + #10;
      Inc(i);
      Continue;
    end;

    { unordered list — every consecutive item, at any indent (nesting is not
      modelled; an indented item is an item of the same list) }
    if MdIsBullet(cur) then
    begin
      if inPara then
      begin
        r := r + '<p>' + para + '</p>' + #10;
        para := '';
        inPara := False;
      end;
      r := r + '<ul>' + #10;
      while (i < nLines) and MdIsBullet(lines[i]) do
      begin
        r := r + '<li>' + MdInline(MdItemText(lines[i])) + '</li>' + #10;
        Inc(i);
      end;
      r := r + '</ul>' + #10;
      Continue;
    end;

    { ordered list }
    mk := MdOrderedMarker(cur);
    if mk > 0 then
    begin
      if inPara then
      begin
        r := r + '<p>' + para + '</p>' + #10;
        para := '';
        inPara := False;
      end;
      r := r + '<ol>' + #10;
      while (i < nLines) and (MdOrderedMarker(lines[i]) > 0) do
      begin
        r := r + '<li>' + MdInline(MdItemText(lines[i])) + '</li>' + #10;
        Inc(i);
      end;
      r := r + '</ol>' + #10;
      Continue;
    end;

    { blockquote }
    if Copy(MdTrimLeft(cur), 1, 1) = '>' then
    begin
      if inPara then
      begin
        r := r + '<p>' + para + '</p>' + #10;
        para := '';
        inPara := False;
      end;
      body := '';
      while (i < nLines) and (Copy(MdTrimLeft(lines[i]), 1, 1) = '>') do
      begin
        cur := MdTrimLeft(lines[i]);
        { a soft line break inside a quote survives, exactly as it does inside
          a paragraph — joining with a space collapsed two source lines into
          one and diverged from python-markdown on the commonest quote shape }
        if body <> '' then
        begin
          if nl2br then body := body + '<br />' + #10 else body := body + #10;
        end;
        body := body + MdTrim(Copy(cur, 2, Length(cur) - 1));
        Inc(i);
      end;
      r := r + '<blockquote><p>' + MdInline(body) + '</p></blockquote>' + #10;
      Continue;
    end;

    { an indented block (4 spaces) that does NOT continue a paragraph is code }
    if (not inPara) and (MdIndent(cur) >= 4) then
    begin
      body := '';
      while (i < nLines) and ((MdIndent(lines[i]) >= 4) or MdIsBlank(lines[i])) do
      begin
        if MdIsBlank(lines[i]) then body := body + #10
        else body := body + HtmlEscape(Copy(lines[i], 5, Length(lines[i]) - 4)) + #10;
        Inc(i);
      end;
      r := r + '<pre><code>' + body + '</code></pre>' + #10;
      Continue;
    end;

    { paragraph text }
    if inPara then
    begin
      if nl2br then para := para + '<br />' + #10 else para := para + #10;
    end;
    para := para + MdInline(MdTrim(cur));
    inPara := True;
    Inc(i);
  end;
  if inPara then r := r + '<p>' + para + '</p>' + #10;

  { python-markdown returns the fragment with no trailing newline }
  while (Length(r) > 0) and (r[Length(r)] = #10) do r := Copy(r, 1, Length(r) - 1);
  MarkdownToHtml := r;
end;

function markdown(const text: AnsiString; const extensions: Variant): AnsiString;
var i, n: Integer; nl2br, ids: Boolean; name: AnsiString;
begin
  nl2br := False;
  ids := False;
  { a list of extension NAMES; anything not recognised is ignored, which is
    stated in the unit header rather than reported — the renderer is already a
    subset, and a missing extension is not a different kind of gap }
  if pyvartag(extensions) = 7 then
  begin
    n := pylen_v(extensions);
    for i := 0 to n - 1 do
    begin
      name := pystr_of(pyvar_getitem(extensions, i));
      if Pos('nl2br', name) > 0 then nl2br := True;
      if Pos('toc', name) > 0 then ids := True;
    end;
  end;
  markdown := MarkdownToHtml(text, nl2br, ids);
end;

end.

{ SPDX-License-Identifier: Zlib }
unit tkhtmlview;
{ `from tkhtmlview import HTMLScrolledText` — a Tk widget that displays HTML.

  THE SUBSET, stated plainly: this renders a document's STRUCTURE into a Text
  widget's tags — headings, paragraphs, lists, code, blockquotes, emphasis,
  links — and ignores everything else (CSS, tables, images, forms). Real
  tkhtmlview is not much wider, but it is wider, and a document leaning on what
  is missing here will look flat rather than wrong.

  It is built on lib/pcl/tkinter's Text and Scrollbar: no HTML engine, no
  images, one pass over the markup. Written for songformatter's help window,
  which feeds it the output of lib/rtl/markdown. }

interface

uses tk, tkinter, pylib;

type
  { A Text widget with a vertical scrollbar, packed inside a frame of its own.
    Geometry calls (`pack`, `grid`) go to the FRAME, so the application's
    `html_label.pack(fill="both", expand=True)` places the whole thing. }
  HTMLScrolledText = class(Widget)
  public
    { The render state lives on the instance rather than in locals: the emit
      helpers below are METHODS because a nested routine cannot capture a
      fixed-size array in this dialect. }
    styleStack: array[0..31] of AnsiString;
    styleTop: Integer;
    atLineStart: Boolean;
    { TkTextWidget, not Text: the RTL's `Text` is a FILE record and wins an
      unqualified lookup outside tkinter — the collision
      [[decide-class-namespace-scoping]] is about }
    text_: TkTextWidget;
    bar: Scrollbar;
    constructor Create(master: Widget; const html: AnsiString = '';
                       width: Integer = -1; height: Integer = -1;
                       const background: AnsiString = '');
    { tkhtmlview's own API. `set_html` replaces the document; `fit_height` is
      accepted and ignored (it exists to size the widget to its content, which
      needs a layout pass this renderer does not do). }
    procedure set_html(const html: AnsiString; const strip: Variant = 0);
    procedure fit_height;
    { render helpers }
    procedure HvEmit(const runText: AnsiString);
    procedure HvNewLine(count_: Integer);
    procedure HvPush(const nm: AnsiString);
    procedure HvPop;
  end;

  { The non-scrolling variant, same renderer. }
  HTMLLabel = class(HTMLScrolledText)
  public
  end;

implementation

{ ---- a tiny HTML reader -------------------------------------------------- }

{ &amp; &lt; &gt; &quot; &#39; &nbsp; — the entities a rendered Markdown
  fragment can contain. Anything else is left as written, which is visible
  rather than silently dropped. }
function HvUnescape(const s: AnsiString): AnsiString;
var i, j: Integer; r, ent: AnsiString;
begin
  r := '';
  i := 1;
  while i <= Length(s) do
  begin
    if s[i] = '&' then
    begin
      j := i + 1;
      while (j <= Length(s)) and (j - i <= 8) and (s[j] <> ';') do Inc(j);
      if (j <= Length(s)) and (s[j] = ';') then
      begin
        ent := Copy(s, i + 1, j - i - 1);
        if ent = 'amp' then r := r + '&'
        else if ent = 'lt' then r := r + '<'
        else if ent = 'gt' then r := r + '>'
        else if ent = 'quot' then r := r + '"'
        else if ent = 'apos' then r := r + ''''
        else if ent = '#39' then r := r + ''''
        else if ent = 'nbsp' then r := r + ' '
        else r := r + '&' + ent + ';';
        i := j + 1;
      end
      else
      begin
        r := r + '&';
        Inc(i);
      end;
    end
    else
    begin
      r := r + s[i];
      Inc(i);
    end;
  end;
  HvUnescape := r;
end;

{ Collapse runs of whitespace, as HTML does outside <pre>. }
function HvCollapse(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; sp: Boolean;
begin
  r := '';
  sp := False;
  for i := 1 to Length(s) do
  begin
    if (s[i] = ' ') or (s[i] = #9) or (s[i] = #10) or (s[i] = #13) then
      sp := True
    else
    begin
      if sp and (r <> '') then r := r + ' ';
      sp := False;
      r := r + s[i];
    end;
  end;
  if sp and (r <> '') then r := r + ' ';
  HvCollapse := r;
end;

function HvLower(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString; c: Char;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    c := s[i];
    if (c >= 'A') and (c <= 'Z') then c := Chr(Ord(c) + 32);
    r := r + c;
  end;
  HvLower := r;
end;

{ The tag NAME out of `<h2 id="x">` / `</h2>` — lowercased, without attributes.
  `closing` says which end it was. }
function HvTagName(const raw: AnsiString; var closing: Boolean): AnsiString;
var i, start: Integer; r: AnsiString;
begin
  closing := False;
  i := 1;
  if (i <= Length(raw)) and (raw[i] = '/') then
  begin
    closing := True;
    Inc(i);
  end;
  start := i;
  while (i <= Length(raw)) and (raw[i] <> ' ') and (raw[i] <> '>') and
        (raw[i] <> #9) and (raw[i] <> #10) and (raw[i] <> '/') do Inc(i);
  r := Copy(raw, start, i - start);
  HvTagName := HvLower(r);
end;

{ ---- the widget ---------------------------------------------------------- }

constructor HTMLScrolledText.Create(master: Widget; const html: AnsiString;
                                    width, height: Integer;
                                    const background: AnsiString);
var bg: AnsiString;
begin
  { the frame IS this widget, so pack/grid on it lays out the pair }
  path := TkiNextPath(master);
  kind := 'frame';
  TkEval('frame ' + path);

  bg := background;
  if bg = '' then bg := 'white';
  bar := Scrollbar.Create(Self, 'vertical');
  text_ := NewText(Self, 'word', width, height, bg);
  text_.configure(yscrollcommand := bar.set_);
  bar.config(command := text_.yview);
  bar.pack('right', 'y');
  text_.pack('left', 'both', True);

  { The styles the renderer uses. Sizes are relative to Tk's default so the
    document tracks the platform font rather than pinning pixels. }
  text_.tag_configure('h1', '{TkDefaultFont 20 bold}', '', '', '', 0, 12, 6);
  text_.tag_configure('h2', '{TkDefaultFont 16 bold}', '', '', '', 0, 10, 5);
  text_.tag_configure('h3', '{TkDefaultFont 13 bold}', '', '', '', 0, 8, 4);
  text_.tag_configure('h4', '{TkDefaultFont 11 bold}', '', '', '', 0, 6, 3);
  text_.tag_configure('strong', '{TkDefaultFont 10 bold}');
  text_.tag_configure('em', '{TkDefaultFont 10 italic}');
  text_.tag_configure('code', '{TkFixedFont 10}', '#7a0000', '#f2f2f2');
  text_.tag_configure('pre', '{TkFixedFont 10}', '', '#f2f2f2', '', 0, -1, -1, 24, 24);
  text_.tag_configure('li', '', '', '', '', 0, -1, -1, 16, 32);
  text_.tag_configure('quote', '{TkDefaultFont 10 italic}', '#444444', '',
                      '', 0, -1, -1, 24, 24);
  text_.tag_configure('a', '', '#0645ad', '', '', True);

  if html <> '' then set_html(html);
end;

procedure HTMLScrolledText.fit_height;
begin
  { accepted and ignored — see the class note }
end;

{ Insert one run of text under the styles currently open. Every open style is
  applied, so `<li><strong>x` gets both the list margin and the bold. }
procedure HTMLScrolledText.HvEmit(const runText: AnsiString);
var k: Integer; startAt: AnsiString;
begin
  if runText = '' then Exit;
  startAt := text_.index('end-1c');
  text_.insert('end', runText);
  for k := 0 to styleTop - 1 do
    if styleStack[k] <> '' then
      text_.tag_add(styleStack[k], startAt, text_.index('end-1c'));
  atLineStart := runText[Length(runText)] = #10;
end;

procedure HTMLScrolledText.HvNewLine(count_: Integer);
var k: Integer;
begin
  { collapse consecutive breaks: a paragraph after a heading gets ONE blank
    line, not one per closing tag }
  if atLineStart and (count_ > 1) then count_ := count_ - 1;
  for k := 1 to count_ do
  begin
    text_.insert('end', #10);
    atLineStart := True;
  end;
end;

procedure HTMLScrolledText.HvPush(const nm: AnsiString);
begin
  if styleTop <= High(styleStack) then
  begin
    styleStack[styleTop] := nm;
    Inc(styleTop);
  end;
end;

procedure HTMLScrolledText.HvPop;
begin
  if styleTop > 0 then Dec(styleTop);
end;

procedure HTMLScrolledText.set_html(const html: AnsiString; const strip: Variant);
var i, j, n: Integer;
    raw, tagName, pending: AnsiString;
    closing, inPre: Boolean;
    listDepth: Integer;
begin
  text_.configure('normal');
  text_.delete('1.0', 'end');
  styleTop := 0;
  listDepth := 0;
  inPre := False;
  atLineStart := True;
  pending := '';
  i := 1;
  n := Length(html);
  while i <= n do
  begin
    if html[i] = '<' then
    begin
      { flush the text before this tag }
      if pending <> '' then
      begin
        if inPre then HvEmit(HvUnescape(pending))
        else HvEmit(HvUnescape(HvCollapse(pending)));
        pending := '';
      end;
      j := i + 1;
      while (j <= n) and (html[j] <> '>') do Inc(j);
      if j > n then Break;                        { unterminated — stop }
      raw := Copy(html, i + 1, j - i - 1);
      i := j + 1;
      tagName := HvTagName(raw, closing);

      if (tagName = 'h1') or (tagName = 'h2') or (tagName = 'h3') or
         (tagName = 'h4') or (tagName = 'h5') or (tagName = 'h6') then
      begin
        if closing then
        begin
          HvPop;
          HvNewLine(2);
        end
        else
        begin
          if not atLineStart then HvNewLine(1);
          if tagName = 'h1' then HvPush('h1')
          else if tagName = 'h2' then HvPush('h2')
          else if tagName = 'h3' then HvPush('h3')
          else HvPush('h4');
        end;
      end
      else if tagName = 'p' then
      begin
        if closing then HvNewLine(2)
        else if not atLineStart then HvNewLine(1);
      end
      else if (tagName = 'strong') or (tagName = 'b') then
      begin
        if closing then HvPop else HvPush('strong');
      end
      else if (tagName = 'em') or (tagName = 'i') then
      begin
        if closing then HvPop else HvPush('em');
      end
      else if tagName = 'code' then
      begin
        { <code> inside <pre> is the fence's inner tag — the <pre> style is
          already open and doubling it would nest the background }
        if not inPre then
        begin
          if closing then HvPop else HvPush('code');
        end;
      end
      else if tagName = 'pre' then
      begin
        if closing then
        begin
          inPre := False;
          HvPop;
          HvNewLine(2);
        end
        else
        begin
          if not atLineStart then HvNewLine(1);
          inPre := True;
          HvPush('pre');
        end;
      end
      else if tagName = 'blockquote' then
      begin
        if closing then
        begin
          HvPop;
          HvNewLine(1);
        end
        else
        begin
          if not atLineStart then HvNewLine(1);
          HvPush('quote');
        end;
      end
      else if (tagName = 'ul') or (tagName = 'ol') then
      begin
        if closing then
        begin
          if listDepth > 0 then Dec(listDepth);
          HvNewLine(2);
        end
        else
        begin
          if not atLineStart then HvNewLine(1);
          Inc(listDepth);
        end;
      end
      else if tagName = 'li' then
      begin
        if closing then
        begin
          HvPop;
          HvNewLine(1);
        end
        else
        begin
          HvPush('li');
          HvEmit('• ');
        end;
      end
      else if tagName = 'a' then
      begin
        { the href is not followed — there is no browser to hand it to — so the
          link is shown as link-coloured text, which is what tkhtmlview does
          without a click handler }
        if closing then HvPop else HvPush('a');
      end
      else if tagName = 'br' then
        HvNewLine(1)
      else if tagName = 'hr' then
      begin
        if not atLineStart then HvNewLine(1);
        HvEmit('────────────────────────────────');
        HvNewLine(2);
      end;
      { any other tag: ignored, its TEXT still renders }
    end
    else
    begin
      pending := pending + html[i];
      Inc(i);
    end;
  end;
  if pending <> '' then
  begin
    if inPre then HvEmit(HvUnescape(pending))
    else HvEmit(HvUnescape(HvCollapse(pending)));
  end;
  { read-only, like tkhtmlview's own widget }
  text_.configure('disabled');
end;

end.

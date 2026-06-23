program bochan;

{ bochan (בוחן, "examiner") — headless test driver for the garin core.

  Exercises garin's render-agnostic models and hands every result to eduth for a
  verdict. Links NO GUI/TUI face (no lib/pcl) — building this at all is the proof
  that garin is render-agnostic. }

uses buffer, eduth, docmodel, lfmload;

var
  e: TEduth;
  b: TIdeBuffer;
  ok: Boolean;
  doc: TDocModel;
  iForm, iBtn: Integer;
  lfm: AnsiString;
  ldoc: TDocModel;

begin
  EduthInit(e);
  writeln('=== bochan: exercising garin ===');

  b := TIdeBuffer.Create;

  { scenario 1: load a known fixture }
  writeln('-- TIdeBuffer.LoadFromFile (existing) --');
  ok := b.LoadFromFile('apps/ide/bochan/fixtures/three.txt');
  CheckTrue(e, 'load existing file returns true', ok);
  CheckInt(e, 'line count = 3', b.LineCount, 3);
  CheckStr(e, 'joined text', b.Text, 'alpha' + #10 + 'beta' + #10 + 'gamma');

  { scenario 2: missing file is graceful }
  writeln('-- TIdeBuffer.LoadFromFile (missing) --');
  ok := b.LoadFromFile('apps/ide/bochan/fixtures/does-not-exist.txt');
  CheckTrue(e, 'missing file returns false', not ok);
  CheckInt(e, 'line count reset to 0', b.LineCount, 0);
  CheckStr(e, 'text reset to empty', b.Text, '');

  { scenario 3: docmodel widget tree (the design source of truth) }
  writeln('-- TDocModel --');
  doc := TDocModel.Create;
  iForm := doc.AddNode(wkForm, 'Form1', -1, 0, 0, 400, 300);
  iBtn := doc.AddNode(wkButton, 'OK', iForm, 20, 20, 80, 26);
  doc.AddNode(wkLabel, 'Name:', iForm, 20, 60, 60, 18);
  CheckInt(e, 'node count = 3', doc.Count, 3);
  CheckInt(e, 'form is root (parent -1)', doc.NodeParent(iForm), -1);
  CheckInt(e, 'button parented to form', doc.NodeParent(iBtn), iForm);
  CheckStr(e, 'button caption', doc.NodeCaption(iBtn), 'OK');
  CheckStr(e, 'kind name', doc.KindName(doc.NodeKind(iBtn)), 'Button');
  CheckInt(e, 'button width', doc.NodeW(iBtn), 80);

  doc.SetNodeBounds(iBtn, 30, 40, 100, 30);
  CheckInt(e, 'resized button x', doc.NodeX(iBtn), 30);
  CheckInt(e, 'resized button width', doc.NodeW(iBtn), 100);

  doc.SetNodeCaption(iBtn, 'Go');
  CheckStr(e, 'edited caption', doc.NodeCaption(iBtn), 'Go');

  { scenario 4: HitTest — topmost node at a point (designer mouse-select) }
  writeln('-- TDocModel.HitTest --');
  { layout now: Form1 (0,0,400,300); button (30,40,100,30); label (20,60,60,18) }
  CheckInt(e, 'hit inside button -> button', doc.HitTest(40, 50), iBtn);
  CheckInt(e, 'hit form-only area -> form', doc.HitTest(300, 200), iForm);
  CheckInt(e, 'hit outside all -> -1', doc.HitTest(500, 500), -1);
  CheckInt(e, 'topmost wins (label over form)', doc.HitTest(25, 65),
    doc.Count - 1);
  CheckInt(e, 'right edge is exclusive', doc.HitTest(130, 50), iForm);

  { scenario 5: load a .lfm text into a docmodel (box-emulation loader) }
  writeln('-- lfmload.LoadLfmText --');
  lfm :=
    'object Form1: TForm'        + #10 +
    '  Left = 0'                 + #10 +
    '  Top = 0'                  + #10 +
    '  Width = 400'              + #10 +
    '  Height = 300'             + #10 +
    '  Caption = ''My Form'''    + #10 +
    '  object Btn: TButton'      + #10 +
    '    Left = 20'              + #10 +
    '    Top = 30'               + #10 +
    '    Width = 80'             + #10 +
    '    Height = 26'            + #10 +
    '    Caption = ''OK'''       + #10 +
    '  end'                      + #10 +
    'end'                        + #10;
  ldoc := TDocModel.Create;
  ok := LoadLfmText(lfm, ldoc);
  CheckTrue(e, 'load returns true', ok);
  CheckInt(e, 'two nodes parsed', ldoc.Count, 2);
  CheckStr(e, 'root kind is Form', ldoc.KindName(ldoc.NodeKind(0)), 'Form');
  CheckStr(e, 'root caption', ldoc.NodeCaption(0), 'My Form');
  CheckInt(e, 'root width', ldoc.NodeW(0), 400);
  CheckInt(e, 'child parented to root', ldoc.NodeParent(1), 0);
  CheckStr(e, 'child kind is Button', ldoc.KindName(ldoc.NodeKind(1)), 'Button');
  CheckStr(e, 'child caption', ldoc.NodeCaption(1), 'OK');
  CheckInt(e, 'child abs Left (0+20)', ldoc.NodeX(1), 20);
  CheckInt(e, 'child abs Top (0+30)', ldoc.NodeY(1), 30);
  CheckInt(e, 'child height', ldoc.NodeH(1), 26);

  Halt(EduthReport(e));
end.

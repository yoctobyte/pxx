program bochan;

{ bochan (בוחן, "examiner") — headless test driver for the garin core.

  Exercises garin's render-agnostic models and hands every result to eduth for a
  verdict. Links NO GUI/TUI face (no lib/pcl) — building this at all is the proof
  that garin is render-agnostic. }

uses buffer, eduth, docmodel;

var
  e: TEduth;
  b: TIdeBuffer;
  ok: Boolean;
  doc: TDocModel;
  iForm, iBtn: Integer;

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

  Halt(EduthReport(e));
end.

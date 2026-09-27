program bochan;

{ bochan (בוחן, "examiner") — headless test driver for the garin core.

  Exercises garin's render-agnostic models and hands every result to eduth for a
  verdict. Links NO GUI/TUI face (no lib/pcl) — building this at all is the proof
  that garin is render-agnostic. }

uses buffer, eduth, docmodel, lfmload, builder, project, perspective, registry,
  typinfo, selection, runner, espproj;

type
  { Synthetic class hierarchy to exercise registry enumeration headlessly (no
    PCL): the registry walk + ancestor-chain test only need RTTI, which these
    published classes carry. Instantiated below so the linker keeps their RTTI. }
  TRegSampleBase = class
  private
    FTag: Integer;
  published
    property Tag: Integer read FTag write FTag;
  end;
  TRegSampleMid = class(TRegSampleBase)
  private
    FCaption: AnsiString;
  published
    property Caption: AnsiString read FCaption write FCaption;
  end;
  TRegSampleLeaf = class(TRegSampleMid)
  private
    FNote: AnsiString;
  published
    property Note: AnsiString read FNote write FNote;
  end;

function RegArrHas(const arr: TRegEntryArr; const nm: AnsiString): Boolean;
var i: Integer;
begin
  RegArrHas := False;
  for i := 0 to Length(arr) - 1 do
    if arr[i].Name = nm then begin RegArrHas := True; Exit; end;
end;

var
  e: TEduth;
  b: TIdeBuffer;
  ok: Boolean;
  doc: TDocModel;
  iForm, iBtn: Integer;
  lfm, saved, diagOut: AnsiString;
  ldoc, rdoc, ddoc: TDocModel;
  diags: TDiagList;
  proj, rproj: TProject;
  args: TStrArray;
  projTxt: AnsiString;
  persp, rpersp: TPerspective;
  perspTxt: AnsiString;
  regBase: TRegSampleBase;
  regMid: TRegSampleMid;
  regLeaf: TRegSampleLeaf;
  regArr: TRegEntryArr;
  sel: TSelectionModel;
  selLn: Integer;
  selTxt: AnsiString;
  sp: TStreamProc;
  spOut, why, chip: AnsiString;
  spTurns: Integer;
  tree: TStrArray;
  ents: TStrArray;
  boards: TEspBoardArr;
  twoBoards: TEspBoardArr;   { a narrowing case the three-board host cannot show }
  dport, dwhy: AnsiString;   { EspChooseDetectPort's answer and its refusal }
  idf: TEspIdf;
  cfg, cfg2: TEspLibCfg;
  cfgTxt: AnsiString;
  pin: TEspPin;

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

  { scenario 6: round-trip — Save then re-Load reproduces the model }
  writeln('-- lfmload SaveLfmText round-trip --');
  saved := SaveLfmText(ldoc);
  CheckTrue(e, 'save produced text', Length(saved) > 0);
  rdoc := TDocModel.Create;
  ok := LoadLfmText(saved, rdoc);
  CheckTrue(e, 'reload returns true', ok);
  CheckInt(e, 'same node count', rdoc.Count, ldoc.Count);
  CheckStr(e, 'rt root kind', rdoc.KindName(rdoc.NodeKind(0)), 'Form');
  CheckStr(e, 'rt root caption', rdoc.NodeCaption(0), 'My Form');
  CheckInt(e, 'rt root width', rdoc.NodeW(0), 400);
  CheckInt(e, 'rt child parent', rdoc.NodeParent(1), 0);
  CheckStr(e, 'rt child kind', rdoc.KindName(rdoc.NodeKind(1)), 'Button');
  CheckStr(e, 'rt child caption', rdoc.NodeCaption(1), 'OK');
  CheckInt(e, 'rt child abs Left', rdoc.NodeX(1), 20);
  CheckInt(e, 'rt child abs Top', rdoc.NodeY(1), 30);
  CheckInt(e, 'rt child width', rdoc.NodeW(1), 80);
  CheckInt(e, 'rt child height', rdoc.NodeH(1), 26);

  { scenario 8: DeleteNode — leaf removal + subtree removal + parent remap }
  writeln('-- TDocModel.DeleteNode --');
  ddoc := TDocModel.Create;
  { 0 Form; 1 Panel(child of 0); 2 Button(child of 1); 3 Label(child of 0) }
  ddoc.AddNode(wkForm,   'F', -1, 0, 0, 400, 300);
  ddoc.AddNode(wkPanel,  'P',  0, 10, 10, 200, 100);
  ddoc.AddNode(wkButton, 'B',  1, 20, 20, 80, 26);
  ddoc.AddNode(wkLabel,  'L',  0, 10, 200, 60, 18);
  { delete the Label (leaf, index 3) -> 3 nodes, others intact }
  ddoc.DeleteNode(3);
  CheckInt(e, 'leaf delete -> 3 nodes', ddoc.Count, 3);
  CheckStr(e, 'button survived', ddoc.NodeCaption(2), 'B');
  { delete the Panel (index 1) -> also removes its child Button; Form remains }
  ddoc.DeleteNode(1);
  CheckInt(e, 'subtree delete -> 1 node', ddoc.Count, 1);
  CheckStr(e, 'form remains', ddoc.NodeCaption(0), 'F');
  CheckInt(e, 'form still root', ddoc.NodeParent(0), -1);
  { out-of-range is a no-op }
  ddoc.DeleteNode(9);
  CheckInt(e, 'oob delete no-op', ddoc.Count, 1);

  { parent remap: delete a middle sibling, remaining child parent index stays valid }
  ddoc := TDocModel.Create;
  ddoc.AddNode(wkForm,  'F', -1, 0, 0, 400, 300);  { 0 }
  ddoc.AddNode(wkLabel, 'A',  0, 0, 0, 10, 10);     { 1 }
  ddoc.AddNode(wkLabel, 'B',  0, 0, 0, 10, 10);     { 2 }
  ddoc.DeleteNode(1);                               { remove A -> B shifts to index 1 }
  CheckInt(e, 'remap count', ddoc.Count, 2);
  CheckStr(e, 'B is now index 1', ddoc.NodeCaption(1), 'B');
  CheckInt(e, 'B parent remapped to 0', ddoc.NodeParent(1), 0);

  { scenario 7: WriteAllText -> LoadFromFile file round-trip }
  writeln('-- buffer.WriteAllText file round-trip --');
  ok := WriteAllText('/tmp/bochan_w.txt', 'alpha' + #10 + 'beta');
  CheckTrue(e, 'write returns true', ok);
  CheckTrue(e, 'reads back', b.LoadFromFile('/tmp/bochan_w.txt'));
  CheckStr(e, 'content matches', b.Text, 'alpha' + #10 + 'beta');

  { scenario 9: builder diagnostic parser }
  writeln('-- builder.TDiagList.Parse --');
  { The `in:`/`near:` continuations are copied from real pinned-compiler output
    (test_incdiag_inc_fail), not composed here, so the fixture cannot drift into
    a shape the compiler never emits. A diagnostic with no `in:` keeps file='',
    which is the main unit -- the compiler does not name it and neither do we. }
  diagOut :=
    'ok: ignore this line'                          + #10 +
    'pascal26:3: error: undefined variable (x)'     + #10 +
    'some banner without the shape'                 + #10 +
    'pascal26:24: error: unit source not found'     + #10 +
    'pascal26:63: error: expected expression'       + #10 +
    '  in: test/incdiag/badinc.inc'                 + #10 +
    '  near:  procedure Bogus  begin if >>> then  end' + #10;
  diags := TDiagList.Create;
  diags.Parse(diagOut);
  CheckInt(e, 'three diagnostics parsed', diags.Count, 3);
  CheckInt(e, 'first diag line', diags.DiagLine(0), 3);
  CheckStr(e, 'first diag msg', diags.DiagMsg(0), 'error: undefined variable (x)');
  CheckInt(e, 'second diag line', diags.DiagLine(1), 24);
  CheckStr(e, 'second diag msg', diags.DiagMsg(1), 'error: unit source not found');
  { the continuation must ATTACH, not become a diagnostic of its own: `in:` and
    `near:` both contain a colon and would be parsed as one by a looser reader }
  CheckInt(e, 'third diag line', diags.DiagLine(2), 63);
  CheckStr(e, 'third diag msg', diags.DiagMsg(2), 'error: expected expression');
  CheckStr(e, 'third diag file', diags.DiagFile(2), 'test/incdiag/badinc.inc');
  { and the ones without an `in:` must stay '' -- an inherited path would send
    the editor into the wrong file, which is the whole bug this fixes }
  CheckStr(e, 'first diag has no file', diags.DiagFile(0), '');
  CheckStr(e, 'second diag has no file', diags.DiagFile(1), '');
  diags.Clear;
  CheckInt(e, 'clear resets', diags.Count, 0);

  { a stray `in:` with no diagnostic above it is dropped, not turned into one }
  diags.Parse('  in: orphan.inc' + #10);
  CheckInt(e, 'orphan in: makes no diagnostic', diags.Count, 0);
  diags.Clear;

  { scenario 10: project model — build inputs -> compiler argv + text round-trip }
  writeln('-- project.TProject --');
  proj := TProject.Create;
  proj.SetName('Demo');
  proj.SetMain('src/main.pas');
  proj.SetOut('/tmp/demo');
  proj.AddUnitPath('lib/rtl');
  proj.AddUnitPath('lib/pcl');
  proj.AddFile('src/main.pas');
  proj.AddFile('src/util.pas');
  CheckStr(e, 'name', proj.Name, 'Demo');
  CheckStr(e, 'main unit', proj.MainUnit, 'src/main.pas');
  CheckStr(e, 'out path', proj.OutPath, '/tmp/demo');
  CheckInt(e, 'two unit paths', proj.UnitPathCount, 2);
  CheckStr(e, 'second unit path', proj.GetUnitPath(1), 'lib/pcl');
  CheckInt(e, 'two files', proj.FileCount, 2);
  CheckStr(e, 'second file', proj.GetFile(1), 'src/util.pas');

  { BuildArgs: [-Fulib/rtl, -Fulib/pcl, src/main.pas, /tmp/demo] }
  args := proj.BuildArgs;
  CheckInt(e, 'argv length', Length(args), 4);
  CheckStr(e, 'argv[0] -Fu rtl', args[0], '-Fulib/rtl');
  CheckStr(e, 'argv[1] -Fu pcl', args[1], '-Fulib/pcl');
  CheckStr(e, 'argv[2] main', args[2], 'src/main.pas');
  CheckStr(e, 'argv[3] out', args[3], '/tmp/demo');

  { no main unit -> empty argv. }
  rproj := TProject.Create;
  { WORKAROUND(bug-length-of-dynarray-call-result): bind BuildArgs to a var
    before Length(). The Platonic form is  Length(rproj.BuildArgs)  inline, but
    Length() of a dynarray call-result miscompiles (empty segfaults). Revert to
    the inline form once that ticket lands. }
  args := rproj.BuildArgs;
  CheckInt(e, 'no-main argv empty', Length(args), 0);

  { text round-trip: save then load reproduces the model }
  writeln('-- project save/load round-trip --');
  projTxt := proj.SaveToText;
  CheckTrue(e, 'save produced text', Length(projTxt) > 0);
  rproj := TProject.Create;
  CheckTrue(e, 'load returns true', rproj.LoadFromText(projTxt));
  CheckStr(e, 'rt name', rproj.Name, 'Demo');
  CheckStr(e, 'rt main', rproj.MainUnit, 'src/main.pas');
  CheckStr(e, 'rt out', rproj.OutPath, '/tmp/demo');
  CheckInt(e, 'rt unit path count', rproj.UnitPathCount, 2);
  CheckStr(e, 'rt unit path 0', rproj.GetUnitPath(0), 'lib/rtl');
  CheckInt(e, 'rt file count', rproj.FileCount, 2);
  CheckStr(e, 'rt file 1', rproj.GetFile(1), 'src/util.pas');

  { parser tolerates blanks and # comments }
  rproj := TProject.Create;
  rproj.LoadFromText('# a comment' + #10 + '' + #10 + 'name = X' + #10 +
    '  main = m.pas  ' + #10 + 'file = a' + #10);
  CheckStr(e, 'comment-tolerant name', rproj.Name, 'X');
  CheckStr(e, 'trimmed main value', rproj.MainUnit, 'm.pas');
  CheckInt(e, 'one file parsed', rproj.FileCount, 1);

  { file round-trip on disk }
  writeln('-- project SaveToFile/LoadFromFile --');
  CheckTrue(e, 'save to file', proj.SaveToFile('/tmp/bochan_proj.pxxproj'));
  rproj := TProject.Create;
  CheckTrue(e, 'load from file', rproj.LoadFromFile('/tmp/bochan_proj.pxxproj'));
  CheckStr(e, 'file rt name', rproj.Name, 'Demo');
  CheckInt(e, 'file rt path count', rproj.UnitPathCount, 2);
  CheckInt(e, 'file rt file count', rproj.FileCount, 2);

  { scenario 11: perspective model — visibility + priority compacting + round-trip }
  writeln('-- perspective.TPerspective --');
  persp := TPerspective.Create;
  persp.SetName('Split');
  { three columns along the horizontal axis: left | center | right }
  persp.AddPane('left',   120, 80, True);
  persp.AddPane('center', 200, 90, True);   { highest priority — editor }
  persp.AddPane('right',  160, 40, True);   { lowest priority — designer }
  CheckInt(e, 'pane count', persp.PaneCount, 3);
  CheckInt(e, 'center index', persp.IndexOf('center'), 1);
  CheckInt(e, 'right min', persp.PaneMin(2), 160);

  { plenty of width -> all three shown }
  persp.Compact(1000);
  CheckTrue(e, 'wide: left shown', persp.IsShown(0));
  CheckTrue(e, 'wide: center shown', persp.IsShown(1));
  CheckTrue(e, 'wide: right shown', persp.IsShown(2));

  { width below sum(mins=480) but >= 320 -> drop lowest priority (right) }
  persp.Compact(400);
  CheckTrue(e, 'tight: left shown', persp.IsShown(0));
  CheckTrue(e, 'tight: center shown', persp.IsShown(1));
  CheckTrue(e, 'tight: right collapsed', not persp.IsShown(2));
  CheckTrue(e, 'tight: right forced (not hidden by choice)', persp.IsForced(2));

  { tighter: below left+center mins (320) -> also drop left (next lowest, 80) }
  persp.Compact(250);
  CheckTrue(e, 'tighter: left collapsed', not persp.IsShown(0));
  CheckTrue(e, 'tighter: center survives (highest pri)', persp.IsShown(1));
  CheckTrue(e, 'tighter: right collapsed', not persp.IsShown(2));

  { a hidden-by-choice pane stays hidden but is not "forced" }
  persp.SetVisible(2, False);
  persp.Compact(1000);
  CheckTrue(e, 'choice-hidden: right not shown', not persp.IsShown(2));
  CheckTrue(e, 'choice-hidden: right not forced', not persp.IsForced(2));
  CheckTrue(e, 'choice-hidden: center still shown', persp.IsShown(1));

  { text round-trip }
  writeln('-- perspective save/load round-trip --');
  persp.SetVisible(2, True);
  perspTxt := persp.SaveToText;
  CheckTrue(e, 'persp text produced', Length(perspTxt) > 0);
  rpersp := TPerspective.Create;
  CheckTrue(e, 'persp load', rpersp.LoadFromText(perspTxt));
  CheckStr(e, 'rt persp name', rpersp.Name, 'Split');
  CheckInt(e, 'rt pane count', rpersp.PaneCount, 3);
  CheckStr(e, 'rt pane 1 id', rpersp.PaneId(1), 'center');
  CheckInt(e, 'rt pane 1 min', rpersp.PaneMin(1), 200);
  CheckInt(e, 'rt pane 2 priority', rpersp.PanePriority(2), 40);
  CheckTrue(e, 'rt pane 0 visible', rpersp.PaneVisible(0));

  { scenario: non-visual components (M4 tray) — classify + serialize round-trip }
  writeln('-- docmodel non-visual + tray round-trip --');
  ddoc := TDocModel.Create;
  CheckTrue(e, 'timer is non-visual', ddoc.IsNonVisual(wkTimer));
  CheckTrue(e, 'menu is non-visual', ddoc.IsNonVisual(wkMenu));
  CheckTrue(e, 'button is visual', not ddoc.IsNonVisual(wkButton));
  CheckTrue(e, 'form is visual', not ddoc.IsNonVisual(wkForm));
  CheckStr(e, 'timer kind name', ddoc.KindName(wkTimer), 'Timer');
  ddoc.AddNode(wkForm, 'Form1', -1, 0, 0, 400, 300);
  ddoc.AddNode(wkButton, 'OK', 0, 20, 20, 80, 26);
  ddoc.AddNode(wkTimer, 'Timer1', 0, 8, 252, 78, 40);
  saved := SaveLfmText(ddoc);
  rdoc := TDocModel.Create;
  CheckTrue(e, 'tray doc reloads', LoadLfmText(saved, rdoc));
  CheckInt(e, 'tray doc node count', rdoc.Count, 3);
  CheckStr(e, 'timer kind survives round-trip',
    rdoc.KindName(rdoc.NodeKind(2)), 'Timer');
  CheckTrue(e, 'reloaded timer still non-visual',
    rdoc.IsNonVisual(rdoc.NodeKind(2)));

  { scenario: the shipped eliah sample.lfm parses with its non-visual TTimer }
  writeln('-- eliah sample.lfm load --');
  if b.LoadFromFile('apps/ide/eliah/sample.lfm') then
  begin
    rdoc := TDocModel.Create;
    CheckTrue(e, 'sample.lfm parses', LoadLfmText(b.Text, rdoc));
    CheckInt(e, 'sample.lfm node count', rdoc.Count, 6);
    CheckStr(e, 'sample node 5 is a Timer', rdoc.KindName(rdoc.NodeKind(5)), 'Timer');
    CheckTrue(e, 'sample Timer is non-visual', rdoc.IsNonVisual(rdoc.NodeKind(5)));
    { the Timer's Interval is an extra published prop — kept verbatim, not dropped }
    CheckStr(e, 'sample Timer Interval prop', rdoc.NodePropByName(5, 'Interval'), '1000');
    { and it survives a save -> reload round-trip }
    ldoc := TDocModel.Create;
    CheckTrue(e, 'sample re-parses from save', LoadLfmText(SaveLfmText(rdoc), ldoc));
    CheckStr(e, 'rt Timer Interval prop', ldoc.NodePropByName(5, 'Interval'), '1000');
  end
  else
    CheckTrue(e, 'sample.lfm present', False);

  { scenario: registry — enumerate registered classes by ancestor (M4 palette).
    Keep the synthetic instances alive so their RTTI is linked + registered. }
  writeln('-- registry enumeration --');
  regBase := TRegSampleBase.Create;  regBase.Tag := 1;
  regMid  := TRegSampleMid.Create;   regMid.Caption := 'm';
  regLeaf := TRegSampleLeaf.Create;  regLeaf.Note := 'n';

  CheckTrue(e, 'registry non-empty', RegisteredClassCount > 0);
  CheckTrue(e, 'leaf descends from base',
    ClassDescendsFrom(GetClass('TRegSampleLeaf'), 'TRegSampleBase'));
  CheckTrue(e, 'mid descends from base',
    ClassDescendsFrom(GetClass('TRegSampleMid'), 'TRegSampleBase'));
  CheckTrue(e, 'class descends from itself',
    ClassDescendsFrom(GetClass('TRegSampleBase'), 'TRegSampleBase'));
  CheckTrue(e, 'base does not descend from leaf',
    not ClassDescendsFrom(GetClass('TRegSampleBase'), 'TRegSampleLeaf'));
  CheckTrue(e, 'unrelated ancestor name is false',
    not ClassDescendsFrom(GetClass('TRegSampleLeaf'), 'TNotAClass'));

  regArr := EnumDescendants('TRegSampleBase', False);
  CheckTrue(e, 'enum excludes the ancestor itself',
    not RegArrHas(regArr, 'TRegSampleBase'));
  CheckTrue(e, 'enum finds mid descendant', RegArrHas(regArr, 'TRegSampleMid'));
  CheckTrue(e, 'enum finds leaf descendant', RegArrHas(regArr, 'TRegSampleLeaf'));

  regArr := EnumDescendants('TRegSampleBase', True);
  CheckTrue(e, 'enum includeSelf adds the ancestor',
    RegArrHas(regArr, 'TRegSampleBase'));

  { scenario: selection model + .lfm code-location mapping (M5 selection-link) }
  writeln('-- selection model + lfm line mapping --');
  if b.LoadFromFile('apps/ide/eliah/sample.lfm') then
  begin
    selTxt := b.Text;
    ldoc := TDocModel.Create;
    CheckTrue(e, 'sel sample parses', LoadLfmText(selTxt, ldoc));
    { node names captured from the `object <Name>:` headers }
    CheckStr(e, 'node 3 name', ldoc.NodeName(3), 'BtnOk');
    CheckInt(e, 'find BtnOk by name', ldoc.FindByName('BtnOk'), 3);
    CheckInt(e, 'find Timer1 by name', ldoc.FindByName('Timer1'), 5);
    CheckInt(e, 'unknown name -> -1', ldoc.FindByName('Nope'), -1);

    sel := TSelectionModel.Create(ldoc);
    CheckInt(e, 'initial selection none', sel.Selected, -1);
    sel.Select(3);
    CheckInt(e, 'select index 3', sel.Selected, 3);
    CheckStr(e, 'selected name', sel.SelectedName, 'BtnOk');
    CheckInt(e, 'one change', sel.Changes, 1);
    sel.Select(3);
    CheckInt(e, 're-select same: no extra change', sel.Changes, 1);
    sel.SelectByName('Timer1');
    CheckInt(e, 'select by name', sel.Selected, 5);
    sel.SelectByName('Ghost');
    CheckInt(e, 'select unknown name clears', sel.Selected, -1);

    { code <-> designer line mapping }
    selLn := LfmFindObjectLine(selTxt, 'BtnOk');
    CheckTrue(e, 'BtnOk has an object line', selLn >= 0);
    CheckStr(e, 'name at that line round-trips', LfmObjectNameAt(selTxt, selLn), 'BtnOk');
    CheckInt(e, 'missing name -> no line', LfmFindObjectLine(selTxt, 'Nope'), -1);

    { wire-event command helpers }
    CheckStr(e, 'handler name', EventHandlerName('BtnOk', 'Click'), 'BtnOkClick');
    selTxt := EventHandlerStub('BtnOkClick');
    CheckTrue(e, 'stub declares the proc',
      CodeHasHandler(selTxt, 'BtnOkClick'));
    CheckTrue(e, 'stub is a procedure',
      LfmFindObjectLine(selTxt, 'x') = -1);   { stub has no object lines }
    CheckTrue(e, 'no handler in empty code', not CodeHasHandler('', 'BtnOkClick'));
    CheckTrue(e, 'unrelated proc is not the handler',
      not CodeHasHandler('procedure Foo(Sender: TObject); begin end;', 'BtnOkClick'));
  end
  else
    CheckTrue(e, 'sel sample.lfm present', False);

  { scenario: the non-blocking runner (garin/runner StreamStart/Poll/Stop) }
  writeln('-- runner: StreamStart / StreamPoll --');
  CheckTrue(e, 'stream starts',
    StreamStart(sp, '/bin/sh', ['-c', 'echo one; echo two; exit 3']));
  spOut := '';
  spTurns := 0;
  while sp.Running and (spTurns < 200) do
  begin
    spOut := spOut + StreamPoll(sp, 100);
    Inc(spTurns);
  end;
  CheckTrue(e, 'stream ends on its own', not sp.Running);
  CheckStr(e, 'stream output', spOut, 'one' + #10 + 'two' + #10);
  CheckInt(e, 'stream exit code', sp.ExitCode, 3);
  writeln('-- runner: a large stream arrives whole --');
  CheckTrue(e, 'big stream starts',
    StreamStart(sp, '/bin/sh', ['-c', 'head -c 300000 /dev/zero | tr ''\000'' x']));
  spOut := '';
  spTurns := 0;
  while sp.Running and (spTurns < 2000) do
  begin
    spOut := spOut + StreamPoll(sp, 100);
    Inc(spTurns);
  end;
  CheckInt(e, 'all 300000 bytes', Length(spOut), 300000);
  CheckTrue(e, 'bytes are intact', (spOut[1] = 'x') and (spOut[300000] = 'x'));
  writeln('-- runner: StreamStop --');
  CheckTrue(e, 'long child starts',
    StreamStart(sp, '/bin/sh', ['-c', 'exec sleep 30']));
  CheckStr(e, 'poll returns without output', StreamPoll(sp, 50), '');
  { TIMEOUT 0 SPECIFICALLY, because that is what the espide tick uses and a
    monitor on a quiet serial port is a child with nothing to say. If a zero
    timeout blocks instead of returning at once, the GUI's timer handler never
    returns, no further tick fires, and the app hangs with its last log line
    printed -- which is exactly what --auto did on a live board: 15 minutes for
    an 8-second monitor. }
  CheckStr(e, 'poll with timeout 0 returns at once', StreamPoll(sp, 0), '');
  CheckTrue(e, 'still running after a zero poll', sp.Running);
  CheckTrue(e, 'still running after a poll', sp.Running);
  StreamStop(sp);
  CheckTrue(e, 'stopped', not sp.Running);
  CheckInt(e, 'killed by SIGTERM', sp.ExitCode, 128 + 15);

  { scenario: espproj — chip decisions and project recognition }
  writeln('-- espproj --');
  CheckStr(e, 'esptool S3', EspChipFromEsptool('Detecting chip type... ESP32-S3' + #10 +
    'Connected to ESP32-S3 on /dev/ttyACM0:' + #10), 'esp32s3');
  CheckStr(e, 'esptool C3', EspChipFromEsptool('Connected to ESP32-C3 on /dev/ttyACM1:'), 'esp32c3');
  CheckStr(e, 'esptool none', EspChipFromEsptool('A fatal error occurred: Failed to connect'), '');
  CheckTrue(e, 'permission problem named',
    Pos('dialout', EspPortProblem('[Errno 13] Permission denied: ''/dev/ttyACM0''')) > 0);
  CheckStr(e, 'chip label', EspChipLabel('esp32c3'), 'ESP32-C3');
  CheckStr(e, 'suffix chip', EspProjectChip('examples/esp32/hello-c3'), 'esp32c3');
  CheckStr(e, 'suffix chip s3', EspProjectChip('examples/esp32/timer-s3/'), 'esp32s3');
  CheckStr(e, 'an IDF project', EspProjectProblem('examples/esp32/hello-s3'), '');
  CheckTrue(e, 'a bare folder is refused',
    Pos('not an ESP-IDF project', EspProjectProblem('apps/ide/bochan/fixtures')) > 0);
  CheckStr(e, 'root from a source file',
    EspFindProjectRoot('examples/esp32/hello-s3/main/main.pas', 'examples/esp32'),
    'examples/esp32/hello-s3');
  CheckStr(e, 'no root above a bare folder',
    EspFindProjectRoot('apps/ide/bochan/fixtures/three.txt', 'apps/ide'), '');
  { 'auto' with no board refuses: the S3 is never a silent default }
  CheckTrue(e, 'auto + no board refuses',
    not EspDecideChip('auto', '', '', chip, why));
  CheckTrue(e, 'auto + no board says so', Pos('No board detected', why) = 1);
  CheckStr(e, 'auto + no board picks nothing', chip, '');
  CheckTrue(e, 'auto follows the board', EspDecideChip('auto', 'esp32c3', '', chip, why));
  CheckStr(e, 'auto chip', chip, 'esp32c3');
  CheckTrue(e, 'project/board mismatch refuses',
    not EspDecideChip('auto', 'esp32s3', 'esp32c3', chip, why));
  CheckTrue(e, 'mismatch names both chips',
    (Pos('ESP32-C3', why) > 0) and (Pos('ESP32-S3', why) > 0));
  CheckTrue(e, 'selector/board mismatch refuses',
    not EspDecideChip('esp32c3', 'esp32s3', '', chip, why));
  CheckTrue(e, 'explicit chip, no board', EspDecideChip('esp32c3', '', 'esp32c3', chip, why));
  tree := EspListTree('examples/esp32/hello-s3', 3);
  CheckTrue(e, 'tree lists main/ before files', (Length(tree) > 2) and (tree[0] = 'main/'));
  { search every entry: a local build leaves main.o and libpxx_app.a in main/,
    so main.pas's index depends on the checkout }
  ok := False;
  for spTurns := 0 to Length(tree) - 1 do
    if tree[spTurns] = 'main/main.pas' then ok := True;
  CheckTrue(e, 'tree recurses into main/', ok);

  { EspListDir, the one place the tree's ORDER and FILTER live. The fixture is
    arranged so the ordering claim cannot pass by accident: 'zeta/' sorts
    AFTER both files alphabetically, so a listing that merely sorted names
    would put it last, and a directories-first listing puts it second. }
  ents := EspListDir('apps/ide/bochan/fixtures/faketree');
  CheckInt(e, 'faketree lists four entries', Length(ents), 4);
  CheckStr(e, 'dirs first, sorted (1)', ents[0], 'alpha/');
  CheckStr(e, 'a dir sorting after every file still comes second', ents[1], 'zeta/');
  CheckStr(e, 'then files, sorted (1)', ents[2], 'aaa.txt');
  CheckStr(e, 'then files, sorted (2)', ents[3], 'bbb.txt');
  { the filter: build/ and anything starting with a dot never appear }
  ok := False;
  for spTurns := 0 to Length(ents) - 1 do
    if (ents[spTurns] = 'build/') or (ents[spTurns] = '.hidden/')
       or (ents[spTurns] = '.dotfile') then ok := True;
  CheckTrue(e, 'build/ and dot entries are filtered out', not ok);
  CheckInt(e, 'a missing directory lists nothing',
    Length(EspListDir('apps/ide/bochan/fixtures/no-such-dir')), 0);

  { EspBoardsFromPorts: the no-udev fallback. Bridge is '' because the bridge
    came from the by-id name and there is none -- asserted, because a bridge
    invented from a raw device name would be a guess presented as a reading. }
  SetLength(ents, 2);
  ents[0] := '/dev/ttyUSB0';
  ents[1] := '/dev/ttyACM1';
  boards := EspBoardsFromPorts(ents);
  CheckInt(e, 'raw ports become boards', Length(boards), 2);
  CheckStr(e, 'the port is the path', boards[0].Port, '/dev/ttyUSB0');
  CheckStr(e, 'the name is its basename', boards[1].Name, 'ttyACM1');
  CheckStr(e, 'no bridge is claimed without a by-id name', boards[0].Bridge, '');
  CheckStr(e, 'and no chip before Detect', boards[1].Chip, '');

  { scenario: espproj — attached boards, read WITHOUT opening a port }
  writeln('-- espproj: boards from a by-id tree --');
  CheckStr(e, 'CP2102 named', EspBridgeFromByIdName(
    'usb-Silicon_Labs_CP2102_USB_to_UART_Bridge_Controller_0001-if00-port0'), 'CP2102');
  CheckStr(e, 'native USB-JTAG named', EspBridgeFromByIdName(
    'usb-Espressif_USB_JTAG_serial_debug_unit_44:B1:76:05:2B:2C-if00'), 'native USB-JTAG');
  CheckStr(e, 'CH34x family named', EspBridgeFromByIdName(
    'usb-1a86_USB_Single_Serial_5A47013421-if00'), 'CH34x');
  { a bridge we do not know answers '' and not a guess }
  CheckStr(e, 'an unknown bridge is not guessed',
    EspBridgeFromByIdName('usb-Some_Other_Thing_1234-if00'), '');
  boards := EspListBoardsIn('apps/ide/bochan/fixtures/by-id');
  { FOUR links are in the fixture and one of them DANGLES (usb-Unplugged_Board_
    dead-if00 -> ../tty/ttyUSB404, which does not exist). Three is therefore the
    positive control for the claim in EspListBoardsIn's own comment: a stale
    by-id entry for an unplugged board must not be listed as attached. If this
    ever reads 4, that sentence has become false. }
  CheckInt(e, 'three boards, the dangling link dropped', Length(boards), 3);
  CheckStr(e, 'sorted by name', boards[0].Name,
    'usb-1a86_USB_Single_Serial_5A47013421-if00');
  CheckStr(e, 'port is the by-id path', boards[0].Port,
    'apps/ide/bochan/fixtures/by-id/usb-1a86_USB_Single_Serial_5A47013421-if00');
  CheckStr(e, 'bridge filled from the name', boards[2].Bridge, 'CP2102');
  CheckStr(e, 'chip blank before Detect', boards[2].Chip, '');
  CheckTrue(e, 'a board line says nothing was asked',
    Pos('not asked yet', EspBoardLine(boards[2])) > 0);

  { ---- which ONE port Detect may open ----
    The fixture IS the host this bug was found on: a CH34x, a native USB-JTAG and
    a CP2102. Detect used to walk all three and reset all three, two of them
    belonging to other people. Every row below is about touching exactly one. }
  writeln('-- espproj: one port, not all of them --');
  { a bridge only ever RULES OUT. The native USB-Serial/JTAG descriptor is not on
    the classic ESP32 (no USB) or the S2 (USB OTG, rendered differently). }
  CheckTrue(e, 'native USB-JTAG cannot be a classic ESP32',
    not EspBridgeCouldBeChip('native USB-JTAG', 'esp32'));
  CheckTrue(e, 'native USB-JTAG cannot be an S2',
    not EspBridgeCouldBeChip('native USB-JTAG', 'esp32s2'));
  CheckTrue(e, 'native USB-JTAG can be a C3',
    EspBridgeCouldBeChip('native USB-JTAG', 'esp32c3'));
  { an external bridge is a wire and excludes NOTHING -- including for the chip
    that has no USB of its own, which is exactly how it is usually attached }
  CheckTrue(e, 'a CP2102 can be a classic ESP32',
    EspBridgeCouldBeChip('CP2102', 'esp32'));
  CheckTrue(e, 'an unknown bridge excludes nothing',
    EspBridgeCouldBeChip('', 'esp32c3'));

  { an explicit port is an explicit choice: nothing is inferred, nothing else
    considered }
  CheckTrue(e, 'an explicit port is honoured',
    EspChooseDetectPort(boards, boards[2].Port, '', dport, dwhy));
  CheckStr(e, 'and it is exactly that port', dport, boards[2].Port);
  { a chip name must not override it either }
  CheckTrue(e, 'an explicit port beats a chip hint',
    EspChooseDetectPort(boards, boards[0].Port, 'esp32c3', dport, dwhy));
  CheckStr(e, 'still that port', dport, boards[0].Port);
  { a stale by-id name is refused BY NAME rather than falling back to probing }
  CheckTrue(e, 'a port that is not attached is refused',
    not EspChooseDetectPort(boards, '/dev/serial/by-id/usb-Gone-if00', '', dport, dwhy));
  CheckStr(e, 'and no port is chosen', dport, '');
  CheckTrue(e, 'and the refusal names it',
    Pos('usb-Gone-if00', dwhy) > 0);

  { THE REGRESSION ROW. auto, no chip, several boards: refuse. This is the exact
    case that reset the other two boards; if it ever returns True again, Detect
    is opening a port nobody pointed at. }
  CheckTrue(e, 'auto with several boards REFUSES',
    not EspChooseDetectPort(boards, '', '', dport, dwhy));
  CheckStr(e, 'and chooses no port at all', dport, '');
  CheckTrue(e, 'and tells the user to pick', Pos('Pick a port', dwhy) > 0);
  CheckTrue(e, 'and lists the ports to pick from',
    Pos('usb-Silicon_Labs_CP2102', dwhy) > 0);

  { an ambiguous chip hint is ALSO a refusal, and on this three-board host every
    chip is ambiguous: two external bridges could each be a classic ESP32, so the
    hint narrows three to two and two is not one. Worth asserting rather than
    assuming -- it is the honest limit of narrowing by USB descriptor. }
  CheckTrue(e, 'a chip hint that leaves two candidates refuses',
    not EspChooseDetectPort(boards, '', 'esp32', dport, dwhy));
  CheckTrue(e, 'and says finding out would reset them',
    Pos('would reset', dwhy) > 0);

  { where narrowing DOES work: the native-USB board is excluded for a classic
    ESP32, leaving one. Nothing is opened to learn that. }
  SetLength(twoBoards, 2);
  twoBoards[0] := boards[1];   { native USB-JTAG }
  twoBoards[1] := boards[2];   { CP2102 }
  CheckStr(e, 'fixture order holds: [1] is the JTAG one', twoBoards[0].Bridge,
    'native USB-JTAG');
  CheckTrue(e, 'a chip hint narrowing to one is used',
    EspChooseDetectPort(twoBoards, '', 'esp32', dport, dwhy));
  CheckStr(e, 'and it is the external bridge', dport, twoBoards[1].Port);

  { one board and nothing to go on is the ordinary single-board case: pressing
    Detect with one board attached is consent to reset THAT board }
  SetLength(twoBoards, 1);
  twoBoards[0] := boards[0];
  CheckTrue(e, 'one board is probed without a hint',
    EspChooseDetectPort(twoBoards, '', '', dport, dwhy));
  CheckStr(e, 'and it is that board', dport, boards[0].Port);

  SetLength(twoBoards, 0);
  CheckTrue(e, 'no boards refuses',
    not EspChooseDetectPort(twoBoards, '', '', dport, dwhy));
  CheckTrue(e, 'and says nothing is connected',
    Pos('no board is connected', dwhy) > 0);

  { the port-busy wording. This read "no ESP chip answered" until a probe of a
    port another session was capturing logged exactly that WHILE having knocked
    the board into download mode: esptool resets before it reads, so this message
    must not suggest the board was left alone. }
  CheckTrue(e, 'a racing opener does not read as no-chip',
    Pos('in use by another program', EspPortProblem(
      'A serial exception error occurred: device reports readiness to read but' +
      ' returned no data (device disconnected or multiple access on port?)')) > 0);
  CheckTrue(e, 'and it warns the board may still have been reset',
    Pos('may still have been reset', EspPortProblem(
      'device reports readiness to read but returned no data')) > 0);
  CheckTrue(e, 'a genuine no-answer still says it was reset',
    Pos('still reset', EspPortProblem('Failed to connect to ESP32')) > 0);
  { EBUSY is the OPPOSITE case and must not borrow the same warning: a refused
    open cannot have toggled DTR/RTS, so that board was left alone. The two are
    a pair -- one says someone else's run may have just died, one says it did
    not -- and conflating them makes both useless. }
  CheckTrue(e, 'a locked port says the board was NOT reset',
    Pos('NOT reset', EspPortProblem(
      'serial.serialutil.SerialException: could not open port: port is busy')) > 0);
  CheckTrue(e, 'and a locked port is not described as a reset risk',
    Pos('may still have been reset', EspPortProblem(
      'could not open port: port is busy')) = 0);
  { NOT "an empty directory" -- git cannot store one, so this fixture holds a
    single .keep, and the row says what it actually measures: a dotfile in a
    by-id directory is not a board. It read 1 before the hidden-entry skip. }
  CheckInt(e, 'a dir holding only a dotfile lists no boards',
    Length(EspListBoardsIn('apps/ide/bochan/fixtures/fakeidf-empty')), 0);
  CheckStr(e, 'MAC from esptool', EspMacFromEsptool(
    'Crystal is 40MHz' + #10 + 'MAC: e0:8c:fe:57:bb:b8' + #10), 'e0:8c:fe:57:bb:b8');
  { a truncated MAC is NOT half-reported }
  CheckStr(e, 'a short MAC is refused', EspMacFromEsptool('MAC: e0:8c:fe' + #10), '');
  CheckStr(e, 'no MAC line', EspMacFromEsptool('Connecting....' + #10), '');
  CheckStr(e, 'revision from esptool', EspRevisionFromEsptool(
    'Chip is ESP32-D0WD-V3 (revision v3.1)' + #10), 'v3.1');
  CheckStr(e, 'no revision line', EspRevisionFromEsptool('Chip is ESP32' + #10), '');

  { scenario: espproj — the dialout group and the sg route }
  writeln('-- espproj: dialout --');
  CheckTrue(e, 'a member is seen',
    EspDialoutFromGroupText('cdrom:x:24:neo' + #10 + 'dialout:x:20:readsb,neo' + #10,
                            'neo') = edMember);
  CheckTrue(e, 'a non-member is seen',
    EspDialoutFromGroupText('dialout:x:20:readsb' + #10, 'neo') = edNotMember);
  { an EMPTY member list must not read as membership, and a substring must not
    either: 'neopolitan' is not 'neo' }
  CheckTrue(e, 'an empty dialout line is not membership',
    EspDialoutFromGroupText('dialout:x:20:' + #10, 'neo') = edNotMember);
  CheckTrue(e, 'a longer name is not a member',
    EspDialoutFromGroupText('dialout:x:20:neopolitan' + #10, 'neo') = edNotMember);
  CheckTrue(e, 'an unreadable group file says nothing',
    EspDialoutFromGroupText('', 'neo') = edUnknown);
  CheckTrue(e, 'the member note explains sg',
    Pos('sg dialout', EspDialoutNote(edMember)) > 0);
  CheckTrue(e, 'the non-member note says how to fix it',
    Pos('usermod', EspDialoutNote(edNotMember)) > 0);
  CheckStr(e, 'nothing to say when unknown', EspDialoutNote(edUnknown), '');
  CheckStr(e, 'a plain path quotes plainly', EspShellQuote('/dev/ttyUSB0'),
    '''/dev/ttyUSB0''');
  { sg dialout -c takes ONE string and forwards no arguments, so the port has to
    be quoted INTO the command -- which is the whole reason this exists }
  CheckStr(e, 'a quote in a path cannot escape',
    EspShellQuote('a''b'), '''a''\''''b''');
  CheckTrue(e, 'sg wraps', Pos('sg dialout -c ', EspWrapSg('echo hi', True)) = 1);
  CheckStr(e, 'no sg, no wrapper', EspWrapSg('echo hi', False), 'echo hi');

  { scenario: espproj — is ESP-IDF installed }
  writeln('-- espproj: ESP-IDF detection --');
  idf := EspDetectIdfIn('apps/ide/bochan/fixtures/fakeidf',
                        'apps/ide/bochan/fixtures/fakehome');
  CheckTrue(e, 'the fake IDF is found', idf.Found);
  { 5.4.2 and not 6.0.1: the fixture's numbers differ from the installed IDF on
    purpose, so a pass cannot be the real ~/esp/esp-idf answering }
  CheckStr(e, 'version from the header', idf.Version, '5.4.2');
  CheckStr(e, 'path recorded', idf.Path, 'apps/ide/bochan/fixtures/fakeidf');
  CheckStr(e, 'python env named', idf.PyEnv, 'idf5.4_py3.11_env');
  CheckTrue(e, 'the line names the version', Pos('5.4.2', EspIdfLine(idf)) > 0);
  { a directory that EXISTS but has no tools/idf.py is not an install: a failed
    clone must not be reported as one }
  idf := EspDetectIdfIn('apps/ide/bochan/fixtures/fakeidf-empty', '');
  CheckTrue(e, 'an empty dir is not an install', not idf.Found);
  CheckTrue(e, 'it says where to get IDF', Pos('espressif.com', idf.Advice) > 0);
  CheckStr(e, 'the line says not found', EspIdfLine(idf), 'ESP-IDF: not found');
  { $IDF_PATH wins over ~/esp/esp-idf }
  idf := EspDetectIdfIn('apps/ide/bochan/fixtures/fakeidf', '/nonexistent-home');
  CheckStr(e, 'env path wins', idf.Path, 'apps/ide/bochan/fixtures/fakeidf');

  { scenario: espproj — per-project libraries }
  writeln('-- espproj: libraries config --');
  cfg := EspLibCfgParse(
    '# a comment' + #10 +
    'unit-dir = /home/u/mylib' + #10 +
    'UNIT-DIR = /home/u/other' + #10 +          { key case does not matter }
    'component-dir = /home/u/pxx_esp' + #10 +
    'require = pxx_esp' + #10 +
    'future-key = something a later IDE wrote' + #10 +
    '' + #10 +
    'unit-dir =' + #10);                        { an empty value adds nothing }
  CheckInt(e, 'two unit roots', Length(cfg.UnitDirs), 2);
  CheckStr(e, 'first unit root', cfg.UnitDirs[0], '/home/u/mylib');
  CheckStr(e, 'key case ignored', cfg.UnitDirs[1], '/home/u/other');
  CheckInt(e, 'one component root', Length(cfg.ComponentDirs), 1);
  CheckInt(e, 'one require', Length(cfg.Requires), 1);
  CheckTrue(e, 'a configured project is not empty', not EspLibCfgEmpty(cfg));
  CheckTrue(e, 'an empty file is empty',
    EspLibCfgEmpty(EspLibCfgParse('# nothing here' + #10)));
  { round trip: what we write, we read back identically }
  cfgTxt := EspLibCfgRender(cfg);
  cfg2 := EspLibCfgParse(cfgTxt);
  CheckInt(e, 'round trip unit roots', Length(cfg2.UnitDirs), Length(cfg.UnitDirs));
  CheckStr(e, 'round trip first unit root', cfg2.UnitDirs[0], cfg.UnitDirs[0]);
  CheckStr(e, 'round trip second unit root', cfg2.UnitDirs[1], cfg.UnitDirs[1]);
  CheckStr(e, 'round trip component root', cfg2.ComponentDirs[0], cfg.ComponentDirs[0]);
  CheckStr(e, 'round trip require', cfg2.Requires[0], cfg.Requires[0]);
  args := EspLibCfgPxxFlags(cfg);
  CheckInt(e, 'one -Fu per unit root', Length(args), 2);
  CheckStr(e, '-Fu is spelled with no space', args[0], '-Fu/home/u/mylib');
  CheckStr(e, 'the config path is in the project', EspLibCfgPath('/tmp/proj/'),
    '/tmp/proj/espide.cfg');
  CheckTrue(e, 'the line counts them', Pos('2 unit root(s)', EspLibCfgLine(cfg)) > 0);
  CheckStr(e, 'nothing to say when unconfigured',
    EspLibCfgLine(EspLibCfgParse('')), '');

  { scenario: espproj -- which compiler this checkout builds with }
  writeln('-- espproj: the pin --');
  pin := EspPinFromLogText(
    '2026-09-25T21:14:21Z  pinned v440  8bfa6543bc28878f9e5acf2258d5a84b  (was 234383049c6b)  0b6fffa0cbe4af32' + #10 +
    '2026-09-25T22:05:28Z  pinned v441  4ebfa2d047a27eae32246a00f0ccb5cb  (was 8bfa6543bc28)  c50502d1a47b6f66' + #10);
  { the LAST pinned row wins: v440 is in the same text and must not be the
    answer, which a first-match parser would have made it }
  CheckStr(e, 'the pin in place is the last row', pin.Version, '441');
  CheckStr(e, 'its sha', pin.Sha, '4ebfa2d047a27eae32246a00f0ccb5cb');
  CheckStr(e, 'its commit', pin.Commit, 'c50502d1a47b6f66');
  CheckTrue(e, 'the line names the version and the sha',
    (Pos('v441', EspPinLine(pin)) > 0) and (Pos('4ebfa2d047a2', EspPinLine(pin)) > 0));
  CheckStr(e, 'an unreadable log says unknown',
    EspPinLine(EspPinFromLogText('')), 'pxx pin: unknown');
  { a log with rows that are not pins must not be read as one }
  CheckStr(e, 'a non-pin row is not a pin',
    EspPinFromLogText('2026-09-25T21:14:21Z  rolled back v439  deadbeef' + #10).Version, '');

  Halt(EduthReport(e));
end.

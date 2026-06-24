program bochan;

{ bochan (בוחן, "examiner") — headless test driver for the garin core.

  Exercises garin's render-agnostic models and hands every result to eduth for a
  verdict. Links NO GUI/TUI face (no lib/pcl) — building this at all is the proof
  that garin is render-agnostic. }

uses buffer, eduth, docmodel, lfmload, builder, project, perspective, registry,
  typinfo, selection;

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
  diagOut :=
    'ok: ignore this line'                          + #10 +
    'pascal26:3: error: undefined variable (x)'     + #10 +
    'some banner without the shape'                 + #10 +
    'pascal26:24: error: unit source not found'     + #10;
  diags := TDiagList.Create;
  diags.Parse(diagOut);
  CheckInt(e, 'two diagnostics parsed', diags.Count, 2);
  CheckInt(e, 'first diag line', diags.DiagLine(0), 3);
  CheckStr(e, 'first diag msg', diags.DiagMsg(0), 'error: undefined variable (x)');
  CheckInt(e, 'second diag line', diags.DiagLine(1), 24);
  CheckStr(e, 'second diag msg', diags.DiagMsg(1), 'error: unit source not found');
  diags.Clear;
  CheckInt(e, 'clear resets', diags.Count, 0);

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
  end
  else
    CheckTrue(e, 'sel sample.lfm present', False);

  Halt(EduthReport(e));
end.

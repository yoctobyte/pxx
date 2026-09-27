program test_pcl_treeview;

{ comctrls.TTreeView over a real GtkTreeView + GtkTreeStore.

  WHAT THIS HAS TO PROVE THAT AN OBVIOUS TEST WOULD NOT.

  1. The STRUCTURE reached the store, not just the model. Every row is read
     back out of the GtkTreeStore by walking it with gtk_tree_model_iter_*,
     which a widgetset that recorded nothing cannot answer: the base seam
     returns '' from TreeAdd and the store stays empty, so `rows=` goes to 0.

  2. The two STRUCT LAYOUTS the binding declares by hand are right. GtkTreeIter
     and GValue come out of the C import with no layout at all -- SizeOf says 4
     for both, which is TypeStorageSize(tyUnknown) and not a size -- so
     gtk3widgets declares them itself. A wrong iter is a stack smash and a
     wrong GValue stores into the wrong type. `gtype=gchararray` checks the
     G_TYPE_STRING constant the binding also had to spell by hand, and the
     round-tripped TEXT of every row checks the GValue.

  3. Selection round-trips through the opaque key. Select a node, ask the
     widgetset which is selected, and require the SAME TTreeNode object back
     -- not a node with the same text, which a broken key lookup could still
     produce, since two siblings here share a name on purpose.

  No event loop is needed: a GtkTreeStore is a model, not a window, and it
  answers off-screen. gtk_init is still required. }

uses interfaces, gtk3, gtk3_c, controls, comctrls, uwidgetset;

var
  Tree: TTreeView;
  a, b, c, dup1, dup2: TTreeNode;

function CStr(p: Pointer): AnsiString;
var s: AnsiString; ch: PChar;
begin
  s := '';
  if p <> nil then
  begin
    ch := p;
    while ch^ <> #0 do
    begin
      s := s + ch^;
      p := p + 1;
      ch := p;
    end;
  end;
  CStr := s;
end;

function IntStr(v: Integer): AnsiString;
var s: AnsiString; n: Integer;
begin
  if v = 0 then begin IntStr := '0'; Exit; end;
  s := '';
  n := v;
  while n > 0 do
  begin
    s := Chr(48 + (n mod 10)) + s;
    n := n div 10;
  end;
  IntStr := s;
end;

{ The GtkTreeView lives inside the scrolled window that is the handle, same
  shape as TMemo. Reaching in is what makes this a test of the WIDGET rather
  than of the Pascal model that mirrors it. }
function Store: Pointer;
begin
  Store := gtk_tree_view_get_model(gtk_bin_get_child(Tree.Handle));
end;

type
  TIterRec = record stamp: LongInt; d1, d2, d3: Pointer; end;

var
  Rows: Integer;
  Dump: AnsiString;

{ Depth-first over the STORE, appending '<indent><text>' for each row. }
procedure Walk(parent: Pointer; depth: Integer);
var it: TIterRec; v: record g: QWord; a0, a1: Int64; end;
    i, n, d: Integer; pad: AnsiString;
begin
  n := gtk_tree_model_iter_n_children(Store, parent);
  for i := 0 to n - 1 do
  begin
    if gtk_tree_model_iter_nth_child(Store, @it, parent, i) = 0 then Continue;
    v.g := 0; v.a0 := 0; v.a1 := 0;
    gtk_tree_model_get_value(Store, @it, 0, @v);
    pad := '';
    for d := 1 to depth do pad := pad + '.';
    { separator BEFORE, not after: a trailing space in an expected string is
      invisible in a diff and gets eaten by whatever touches the file next }
    if Dump <> '' then Dump := Dump + ' ';
    Dump := Dump + pad + CStr(g_value_get_string(@v));
    g_value_unset(@v);
    Rows := Rows + 1;
    Walk(@it, depth + 1);
  end;
end;

var
  sel: TTreeNode;

begin
  gtk_init(nil, nil);

  { the G_TYPE_STRING the binding spells by hand, named back by GLib itself }
  writeln('gtype=', CStr(g_type_name(G_TYPE_STRING)));

  Tree := TTreeView.Create(nil);

  a := Tree.AddRoot('project', '/p');
  b := a.AddChild('main', '/p/main');
  b.AddChild('main.pas', '/p/main/main.pas');
  c := Tree.AddRoot('other', '/o');

  { two siblings with the SAME text, under different parents: a key lookup
    that matched on text instead of on the widgetset's key would return the
    wrong one of these, and the selection row below would still "pass" }
  dup1 := b.AddChild('twin', '/p/main/twin');
  dup2 := c.AddChild('twin', '/o/twin');

  Rows := 0;
  Dump := '';
  Walk(nil, 0);
  writeln('rows=', IntStr(Rows));
  writeln('dump=', Dump);

  { selection round-trip through the opaque key }
  dup2.Select;
  sel := Tree.Selected;
  if sel = nil then writeln('sel=nil')
  else if sel = dup2 then writeln('sel=dup2 data=', sel.Data)
  else if sel = dup1 then writeln('sel=WRONG-TWIN')
  else writeln('sel=other data=', sel.Data);

  dup1.Select;
  sel := Tree.Selected;
  if sel = dup1 then writeln('sel2=dup1 data=', sel.Data)
  else if sel = dup2 then writeln('sel2=WRONG-TWIN')
  else writeln('sel2=?');

  { SetText goes through the store, so the readback proves the GValue path
    both ways }
  b.Text := 'renamed';
  Rows := 0;
  Dump := '';
  Walk(nil, 0);
  writeln('after=', Dump);

  Tree.Clear;
  Rows := 0;
  Dump := '';
  Walk(nil, 0);
  writeln('cleared=', IntStr(Rows));
end.

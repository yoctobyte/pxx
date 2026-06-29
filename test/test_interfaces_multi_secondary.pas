program TestInterfacesMultiSecondary;
{$mode objfpc}

type
  IReadable = interface
    function ReadStr: string;
  end;

  IDocument = interface(IReadable)
    function GetTitle: string;
  end;

  IWritable = interface
    procedure WriteStr(const S: string);
  end;

  TDocument = class(IDocument, IWritable)
    Title: string;
    Content: string;
    function ReadStr: string;
    function GetTitle: string;
    procedure WriteStr(const S: string);
  end;

function TDocument.ReadStr: string;
begin
  Result := Self.Content;
end;

function TDocument.GetTitle: string;
begin
  Result := Self.Title;
end;

procedure TDocument.WriteStr(const S: string);
begin
  Self.Content := S;
end;

var
  doc: TDocument;
  readable: IReadable;
  document: IDocument;
  writable: IWritable;
begin
  doc := TDocument.Create;
  doc.Title := 'Title';
  doc.Content := 'initial';

  doc.WriteStr('direct');
  writeln(doc.Content);
  doc.Content := 'initial';

  document := doc;
  writable := doc;
  writable.WriteStr('Some content');
  readable := doc;

  writeln(document.GetTitle);
  writeln(document.ReadStr);
  writeln(readable.ReadStr);
  writeln(doc.Title);
  writeln(doc.Content);
end.

{ bug-tobject-destroy-not-virtual-override: FPC's universal
  `destructor Destroy; override;` (and virtual `constructor Create; override;`)
  must compile on a root-derived class and dispatch/chain correctly, even though
  pxx's TObject is an implicit method-less root. Method impls precede the main
  var block (pxx requires that ordering); each impl traces via writeln and the
  harness asserts the exact output sequence. }
program test_tobject_destroy_override;

type
  { bare class (implicit TObject root): Destroy override + inherited Destroy }
  TFoo = class
    destructor Destroy; override;
  end;

  { explicit class(TObject) chain: polymorphic destroy through a base ref +
    virtual constructor override }
  TAnimal = class(TObject)
    constructor Create; override;
    destructor Destroy; override;
  end;
  TDog = class(TAnimal)
    destructor Destroy; override;
  end;

destructor TFoo.Destroy;
begin
  writeln('F');
  inherited Destroy;      { implicit-root no-op }
end;

constructor TAnimal.Create;
begin
  inherited Create;       { implicit-root no-op }
  writeln('c');
end;

destructor TAnimal.Destroy;
begin
  writeln('A');
  inherited Destroy;      { implicit-root no-op }
end;

destructor TDog.Destroy;
begin
  writeln('D');
  inherited Destroy;      { -> TAnimal.Destroy }
end;

var
  f: TFoo;
  a: TAnimal;
begin
  f := TFoo.Create;
  f.Free;                 { -> TFoo.Destroy: F }
  a := TDog.Create;       { virtual ctor TAnimal.Create: c }
  a.Free;                 { base ref -> virtual TDog.Destroy -> TAnimal.Destroy: D, A }
  writeln('OK');
end.

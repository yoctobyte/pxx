{ Arity-overloaded class names: `TD`, `TD<K>` and `TD<K,V>` coexisting, which is
  how FPC's Generics.Collections publishes TDictionary and how rtl-generics
  declares THashService.

  Two independent defects had to be fixed for this, and the test asserts both:

  1. A bare `TD.N` implementation header was given to the TEMPLATE whenever a
     template of that name existed, because the dispatch matched on the name
     alone. The bare spelling is legitimately how a generic method impl is
     written too, so the header is genuinely ambiguous here — it is resolved by
     asking which class DECLARES the method. Symptom was `unresolved forward:
     TD.N`, pointing at the non-generic class's own method.

  2. Specialization rewrites every occurrence of the template's name to the
     specialized name, which also caught the BASE-CLASS reference in
     `TD<K> = class(TD)` — so the specialization was emitted inheriting from
     itself and reported `base type not found: TD$LongInt`.

  The inheritance assertion is the load-bearing one: `TD<LongInt>.N` reaches the
  NON-generic parent's method through the specialization. That fails if the base
  link is merely parsed rather than real, which a compile-only check would miss.

  Output verified identical to fpc 3.2.2 -O1 -Mdelphi.
}
program test_generic_name_overload;

type
  TD = class
    class function N: LongInt; static;
  end;

  { generic inheriting the SAME-NAMED ordinary class }
  TD<K> = class(TD)
    class function N1: LongInt; static;
  end;

  { a second arity alongside both }
  TD<K, V> = class
    class function N2: LongInt; static;
  end;

class function TD.N: LongInt; begin Result := 0; end;
class function TD<K>.N1: LongInt; begin Result := 1; end;
class function TD<K, V>.N2: LongInt; begin Result := 2; end;

begin
  { each arity resolves to its own class }
  writeln(TD.N, ' ', TD<LongInt>.N1, ' ', TD<LongInt, LongInt>.N2);

  { the inherited method is reachable through the specialization — proves the
    base clause resolved to the ordinary class and not to the specialization }
  writeln(TD<LongInt>.N);
end.

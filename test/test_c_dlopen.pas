program test_c_dlopen;
uses dl, sysutils;

procedure Fail(const msg: string);
begin
  writeln('FAIL: ', msg);
  halt(1);
end;

type
  // Double -> Double (libm.so.6)
  TCosFunc = function(x: Double): Double; cdecl;
  
  // void -> PChar (libz.so.1)
  TZlibVersionFunc = function: PChar; cdecl;
  
  // PChar, PChar -> PChar (libcrypt.so.1)
  TCryptFunc = function(phrase, setting: PChar): PChar; cdecl;

function PCharHasPrefix(p: PChar; const prefix: string): Boolean;
var
  i: Integer;
begin
  Result := True;
  for i := 1 to Length(prefix) do
  begin
    if p[i - 1] <> prefix[i] then
    begin
      Result := False;
      Break;
    end;
  end;
end;

var
  m_handle, z_handle, c_handle: Pointer;
  cos_ptr, zver_ptr, crypt_ptr: Pointer;
  
  cos_func: TCosFunc;
  zver_func: TZlibVersionFunc;
  crypt_func: TCryptFunc;
  
  d_res: Double;
  z_res, c_res: PChar;
begin
  // 1. Load libm.so.6
  m_handle := dlopen(PChar('libm.so.6'), 1);
  if m_handle = nil then
    Fail('dlopen(libm.so.6) failed: ' + PChar(dlerror()));

  cos_ptr := dlsym(m_handle, PChar('cos'));
  if cos_ptr = nil then
  begin
    dlclose(m_handle);
    Fail('dlsym(cos) failed: ' + PChar(dlerror()));
  end;

  cos_func := TCosFunc(cos_ptr);
  d_res := cos_func(0.0);
  writeln('cos(0.0) = ', d_res);
  if (d_res < 0.999) or (d_res > 1.001) then
  begin
    dlclose(m_handle);
    Fail('cos(0.0) did not yield 1.0');
  end;

  // 2. Load libz.so.1
  z_handle := dlopen(PChar('libz.so.1'), 1);
  if z_handle = nil then
  begin
    dlclose(m_handle);
    Fail('dlopen(libz.so.1) failed: ' + PChar(dlerror()));
  end;

  zver_ptr := dlsym(z_handle, PChar('zlibVersion'));
  if zver_ptr = nil then
  begin
    dlclose(z_handle);
    dlclose(m_handle);
    Fail('dlsym(zlibVersion) failed: ' + PChar(dlerror()));
  end;

  zver_func := TZlibVersionFunc(zver_ptr);
  z_res := zver_func();
  writeln('zlib version = ', z_res);
  if (z_res = nil) or (z_res[0] = #0) then
  begin
    dlclose(z_handle);
    dlclose(m_handle);
    Fail('zlibVersion returned empty or nil');
  end;

  // 3. Load libcrypt.so.1
  c_handle := dlopen(PChar('libcrypt.so.1'), 1);
  if c_handle = nil then
  begin
    dlclose(z_handle);
    dlclose(m_handle);
    Fail('dlopen(libcrypt.so.1) failed: ' + PChar(dlerror()));
  end;

  crypt_ptr := dlsym(c_handle, PChar('crypt'));
  if crypt_ptr = nil then
  begin
    dlclose(c_handle);
    dlclose(z_handle);
    dlclose(m_handle);
    Fail('dlsym(crypt) failed: ' + PChar(dlerror()));
  end;

  crypt_func := TCryptFunc(crypt_ptr);
  c_res := crypt_func(PChar('supersecretpassword'), PChar('$6$saltsalt$'));
  if c_res = nil then
  begin
    dlclose(c_handle);
    dlclose(z_handle);
    dlclose(m_handle);
    Fail('crypt through dlsym returned nil');
  end;

  writeln('crypt hash via dlsym: ', c_res);
  if not PCharHasPrefix(c_res, '$6$saltsalt$') then
  begin
    dlclose(c_handle);
    dlclose(z_handle);
    dlclose(m_handle);
    Fail('crypt hash does not match expected prefix');
  end;

  // 4. Close all library handles
  dlclose(c_handle);
  dlclose(z_handle);
  dlclose(m_handle);
  
  writeln('All dynamic loading and dlsym tests passed successfully!');
end.

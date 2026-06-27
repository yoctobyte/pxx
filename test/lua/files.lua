-- Lua file library over crtl fopen/fread/fwrite/fseek
local path = "/tmp/pxx_lua_file_api.txt"
local f = assert(io.open(path, "wb"))
assert(f:write("alpha\nbeta\n"))
assert(f:seek("set", 6) == 6)
assert(f:write("BETA\n"))
assert(f:close())

f = assert(io.open(path, "rb"))
print(f:read("*l"))
print(f:read("*a"))
assert(f:close())
os.remove(path)

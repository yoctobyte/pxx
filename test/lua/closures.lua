-- closures, upvalues, memoization
local function counter()
  local n = 0
  return function() n = n + 1; return n end
end
local c = counter()
print(c(), c(), c())

local function memo_fib()
  local cache = {[0]=0, [1]=1}
  local function f(n) if cache[n] then return cache[n] end
    cache[n] = f(n-1) + f(n-2); return cache[n] end
  return f
end
print(memo_fib()(30))

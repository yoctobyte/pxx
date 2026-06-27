-- coroutine.wrap generator + create/resume
local function squares(n)
  return coroutine.wrap(function() for i=1,n do coroutine.yield(i*i) end end)
end
local sum = 0
for v in squares(5) do sum = sum + v end
print("sum-of-squares", sum)

local co = coroutine.create(function(a)
  local b = coroutine.yield(a + 1)
  return b * 2
end)
local _, r1 = coroutine.resume(co, 10)
local _, r2 = coroutine.resume(co, 100)
print("resume", r1, r2)

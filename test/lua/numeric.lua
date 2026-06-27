-- float value model (pins the double-value-model fixes)
print(3.14)
print(1.5 + 2.5)
print(2 ^ 10)
print(7 / 2)
print(string.format("%.2f", 3.14159))
print(math.sqrt(16.0))
print(string.format("%.4f", math.pi))
-- stdev of a sample
local function sd(t)
  local s, n = 0.0, #t
  for _,v in ipairs(t) do s = s + v end
  local m = s / n
  local var = 0.0
  for _,v in ipairs(t) do var = var + (v-m)^2 end
  return string.format("mean=%.2f sd=%.2f", m, math.sqrt(var/n))
end
print(sd({2.0,4.0,4.0,4.0,5.0,5.0,7.0,9.0}))

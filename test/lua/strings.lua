-- string library + sorting + table.concat
local s = "Hello, World"
print(s:upper(), #s, s:sub(1,5))
print((s:gsub("o", "0")))
local words = {}
for w in ("the quick brown fox"):gmatch("%a+") do words[#words+1] = w end
table.sort(words)
print(table.concat(words, ","))
local t = {5,2,8,1,9,3}
table.sort(t, function(a,b) return a > b end)
print(table.concat(t, " "))

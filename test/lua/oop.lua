-- metatables, colon-method definitions (pins sizeof("self") fix), inheritance
local Animal = {}
Animal.__index = Animal
function Animal.new(name) return setmetatable({name=name}, Animal) end
function Animal:speak() return self.name .. " makes a sound" end

local Dog = setmetatable({}, {__index = Animal})
Dog.__index = Dog
function Dog.new(name) local o = Animal.new(name); return setmetatable(o, Dog) end
function Dog:speak() return self.name .. " barks" end

local a = Animal.new("cat")
local d = Dog.new("rex")
print(a:speak())
print(d:speak())
print(d.name)

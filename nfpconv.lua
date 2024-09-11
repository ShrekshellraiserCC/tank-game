local input = arg[1]
local output = arg[2]

local f = assert(fs.open(input, "r"))
local fo = assert(fs.open(output, "w"))

fo.write("{")
while true do
    local s = f.readLine()
    if not s then break end
    fo.write("'" .. s .. "',")
end
fo.write("}")
f.close()
fo.close()

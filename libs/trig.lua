local function round(n)
    return math.floor(n + 0.5)
end

local sineCache = {}
local function sin(deg)
    deg = round(deg) % 360
    return sineCache[deg]
end

local cosCache = {}
local function cos(deg)
    deg = round(deg) % 360
    return cosCache[deg]
end

for i = 0, 360 do
    sineCache[i] = math.sin(math.rad(i))
    cosCache[i] = math.cos(math.rad(i))
end

local atanCache = {}
local function atan(n)
    return math.deg(math.atan(n))
end

return {
    sin = sin,
    cos = cos,
    atan = atan,
    round = round
}

local trig = {}

function trig.round(n)
    return math.floor(n + 0.5)
end

local sineCache = {}
function trig.sin(deg)
    deg = trig.round(deg) % 360
    return sineCache[deg]
end

local cosCache = {}
function trig.cos(deg)
    deg = trig.round(deg) % 360
    return cosCache[deg]
end

for i = 0, 360 do
    sineCache[i] = math.sin(math.rad(i))
    cosCache[i] = math.cos(math.rad(i))
end

local atanCache = {}
function trig.atan(n)
    return math.deg(math.atan(n))
end

return trig

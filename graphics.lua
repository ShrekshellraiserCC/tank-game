local trig = require "trig"


---Perform a linear interpolation between v0 and v1
---@param v0 number
---@param v1 number
---@param t number [0,1]
---@return number
local function lerp(v0, v1, t)
    return v0 + t * (v1 - v0)
end

local box
local function setBox(b)
    box = b
end

local tw, th = term.getSize()
local mx, my = tw, th / 2 * 3
local cx, cy = mx, my
local xmin = cx - mx
local xmax = cx + mx
local ymin = cy - my
local ymax = cy + my
local function setViewCenter(x, y)
    cx, cy = x, y
    xmin = cx - mx
    xmax = cx + mx
    ymin = cy - mx
    ymax = cy + mx
end


---Convert a coordinate in screen to world position (in pixels)
---@param x number
---@param y number
---@return integer
---@return integer
local function screenToWorldPos(x, y)
    return trig.round(x + cx - mx), trig.round(y + cy - my)
end

---Convert a coordinate in world to screen position (in pixels)
---@param x number
---@param y number
---@return integer
---@return integer
local function worldToScreenPos(x, y)
    return trig.round(x - cx + mx), trig.round(y - cy + my)
end

local function setPixel(x, y, color)
    box:set_pixel(trig.round(x - cx + mx), trig.round(y - cy + my), color)
end

---Draw a line between two points
---@param x0 number
---@param y0 number
---@param x1 number
---@param y1 number
---@param color color
local function drawLine(x0, y0, x1, y1, color)
    local length = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    for t = 0, 1, 1 / (length * 1.1) do
        local x = lerp(x0, x1, t)
        local y = lerp(y0, y1, t)
        setPixel(trig.round(x), trig.round(y), color)
    end
end

---Draw a line from a starting point with a particular distance and angle
---@param x number
---@param y number
---@param length number
---@param angle number
---@param color color
local function drawAngledLine(x, y, length, angle, color)
    local x1, y1 = x + length * trig.cos(angle), y + length * trig.sin(angle)
    drawLine(x, y, x1, y1, color)
end

---@alias points {x:number,y:number}[]


local function calculateAngle(x0, y0, x1, y1)
    local dx = x1 - x0
    local angle = trig.atan((y1 - y0) / (x1 - x0))
    if dx < 0 then
        angle = angle + 180
    end
    return angle
end

---@param rxmin number
---@param rymin number
---@param rxmax number
---@param rymax number
---@return boolean
local function withinViewport(rxmin, rymin, rxmax, rymax)
    rxmin, rymin = worldToScreenPos(rxmin, rymin)
    rxmax, rymax = worldToScreenPos(rxmax, rymax)
    return (rymin < th * 3 and rymax > 0) and (rxmin < tw * 2 and rxmax > 0)
end


return {
    setBox = setBox,
    setPixel = setPixel,
    drawLine = drawLine,
    setViewCenter = setViewCenter,
    drawAngledLine = drawAngledLine,
    calculateAngle = calculateAngle,
    screenToWorldPos = screenToWorldPos,
    worldToScreenPos = worldToScreenPos,
    withinViewport = withinViewport,
    lerp = lerp
}

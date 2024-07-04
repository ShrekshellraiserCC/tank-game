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

local function slope(x1, y1, x2, y2)
    return (y2 - y1) / (x2 - x1)
end

local function bary(x, y, p1, p2, p3)
    local p23y_delta, p13x_delta, p32x_delta = p2[2] - p3[2], p1[1] - p3[1], p3[1] - p2[1]

    local xp3_delta, yp3_delta = x - p3[1], y - p3[2]

    local div = (p23y_delta * p13x_delta + p32x_delta * (p1[2] - p3[2]))

    local dot_a = (p23y_delta * xp3_delta + p32x_delta * yp3_delta) / div
    local dot_b = ((p3[2] - p1[2]) * xp3_delta + p13x_delta * yp3_delta) / div

    return dot_a, dot_b, 1 - dot_a - dot_b
end

---@alias Point {[1]:number,[2]:number,[3]:number,[4]:number} x, y, u, v

---@alias Triangle {[1]:Point,[2]:Point,[3]:Point}

---Render a triangle
---@param poly Polygon
---@param p1 Point
---@param p2 Point
---@param p3 Point
---@param frag fun(poly: Polygon, x: number, y: number, u: number, v: number)
local function renderTriangle(poly, p1, p2, p3, frag)
    if p1[2] > p3[2] then p1, p3 = p3, p1 end
    if p1[2] > p2[2] then p1, p2 = p2, p1 end
    if p2[2] > p3[2] then p2, p3 = p3, p2 end

    local split_alpha = (p2[2] - p1[2]) / (p3[2] - p1[2])
    local split_x = (1 - split_alpha) * p1[1] + split_alpha * p3[1]
    local split_y = (1 - split_alpha) * p1[2] + split_alpha * p3[2]
    local split_u = (1 - split_alpha) * p1[3] + split_alpha * p3[3]
    local split_v = (1 - split_alpha) * p1[4] + split_alpha * p3[4]

    local left_point, right_point = p2, { split_x, split_y, split_u, split_v }
    if left_point[1] > right_point[1] then
        left_point, right_point = right_point, left_point
    end

    local delta_left_top     = 1 / slope(p3[1], p3[2], left_point[1], left_point[2])
    local delta_right_top    = 1 / slope(p3[1], p3[2], right_point[1], right_point[2])
    local delta_left_bottom  = 1 / slope(p1[1], p1[2], left_point[1], left_point[2])
    local delta_right_bottom = 1 / slope(p1[1], p1[2], right_point[1], right_point[2])

    local subpixel_bottom    = math.floor(p1[2] + 0.5) + 0.5 - p1[2]
    local subpixel_top       = math.floor(p2[2] + 0.5) + 0.5 - left_point[2]

    if delta_left_top then
        local x_left, x_right = left_point[1] + delta_left_top * subpixel_top,
            right_point[1] + delta_right_top * subpixel_top

        for y = math.floor(p2[2] + 0.5), math.ceil(p3[2] - 0.5) do
            for x = math.ceil(x_left - 0.5), math.ceil(x_right - 0.5) - 1 do
                local bary_a, bary_b, bary_c = bary(x, y, left_point, right_point, p3)
                local u = left_point[3] * bary_a + right_point[3] * bary_b + p3[3] * bary_c
                local v = left_point[4] * bary_a + right_point[4] * bary_b + p3[4] * bary_c

                frag(poly, x, y, u, v)
            end

            x_left, x_right = x_left + delta_left_top, x_right + delta_right_top
        end
    end

    if delta_left_bottom then
        local x_left, x_right = p1[1] + delta_left_bottom * subpixel_bottom, p1[1] + delta_right_bottom * subpixel_bottom

        for y = math.floor(p1[2] + 0.5), math.floor(p2[2] + 0.5) - 1 do
            for x = math.ceil(x_left - 0.5), math.ceil(x_right - 0.5) - 1 do
                local bary_a, bary_b, bary_c = bary(x, y, p1, left_point, right_point)
                local u = p1[3] * bary_a + left_point[3] * bary_b + right_point[3] * bary_c
                local v = p1[4] * bary_a + left_point[4] * bary_b + right_point[4] * bary_c

                frag(poly, x, y, u, v)
            end

            x_left, x_right = x_left + delta_left_bottom, x_right + delta_right_bottom
        end
    end
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
    local ax, ay = trig.round(x - cx + mx), trig.round(y - cy + my)
    if ax < 1 or ay < 1 or ax > tw * 2 or ay > th * 3 then
        return
    end
    box:set_pixel(ax, ay, color)
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
    renderTriangle = renderTriangle,
    drawLine = drawLine,
    setViewCenter = setViewCenter,
    drawAngledLine = drawAngledLine,
    calculateAngle = calculateAngle,
    screenToWorldPos = screenToWorldPos,
    worldToScreenPos = worldToScreenPos,
    withinViewport = withinViewport,
    lerp = lerp
}

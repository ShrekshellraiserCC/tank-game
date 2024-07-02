local trig = require "trig"
local graphics = require "graphics"

local function vectorize(v)
    return vector.new(v.x or 0, v.y or 0, v.z or 0)
end

-- Ear clipping algorithm to triangulate polygon
---@return Triangle[]
local earClipping

---@alias Texture color[][]

local function log(s, ...)
    local f = assert(fs.open("log.txt", "a"))
    f.writeLine(s:format(...))
    f.close()
end

---@param tri Triangle
local function logTriangle(tri)
    log("# Triangle")
    log("-- points:")
    log("%s", tri.A)
    log("%s", tri.B)
    log("%s", tri.C)
    log("-- uvpoints:")
    log("%s", tri.UV_A)
    log("%s", tri.UV_B)
    log("%s", tri.UV_C)
end

---@param poly Polygon
local function logPolygon(poly)
    log("=== Polygon ===")
    log("-- points:")
    for i, v in ipairs(poly.points) do
        log("%s", v)
    end
    log("-- uvpoints:")
    for i, v in ipairs(poly.uvpoints) do
        log("%s", v)
    end
    log("-- triangles:")
    for i, v in ipairs(poly.triangles) do
        logTriangle(v)
    end
end

---@param poly Polygon
local function calculatePolygon(poly)
    ---@class Polygon
    poly = poly -- so great
    poly.cacheValid = false
    poly.buffer = {}
    poly.axmin, poly.axmax, poly.aymin, poly.aymax = math.huge, -math.huge, math.huge, -math.huge
    local xsum, ysum = 0, 0
    for _, point in ipairs(poly.points) do
        xsum = xsum + point.x
        ysum = ysum + point.y
        poly.axmin = math.min(poly.axmin, point.x)
        poly.axmax = math.max(poly.axmax, point.x)
        poly.aymin = math.min(poly.aymin, point.y)
        poly.aymax = math.max(poly.aymax, point.y)
    end
    poly.center = vector.new(xsum / #poly.points, ysum / #poly.points, 0)
    -- Square radius
    poly.xmin, poly.ymin, poly.xmax, poly.ymax = poly.axmin - poly.center.x,
        poly.aymin - poly.center.y, poly.axmax - poly.center.x, poly.aymax - poly.center.y


    if not poly.uvpoints then
        poly.uvpoints = {}
        -- local width = poly.axmax - poly.axmin
        -- local height = poly.aymax - poly.aymin

        for i, point in ipairs(poly.points) do
            -- local uvx = ((point.x - poly.axmin) / width)
            -- local uvy = ((point.y - poly.aymin) / height)

            local uvx = math.max((point.x - poly.center.x) / (poly.axmax - poly.axmin) + 0.5, 0)
            local uvy = math.max((point.y - poly.center.y) / (poly.aymax - poly.aymin) + 0.5, 0)
            poly.uvpoints[i] = vector.new(uvx, uvy, 0)
        end
    end
    poly.triangles = earClipping(poly)
end

---@param points points|Vector[]
---@param color color
---@param uvpoints Vector[]?
---@return Polygon
local function polygon(points, color, uvpoints)
    ---@class Polygon
    ---@field renderer fun(poly: Polygon)?
    ---@field points Vector[]
    ---@field triangles Triangle[]
    ---@field texture Texture?
    ---@field buffer color[][]?
    local poly = {}
    poly.points = {}
    for i, v in ipairs(points) do
        poly.points[i] = vectorize(v)
    end
    poly.color = color
    poly.uvpoints = uvpoints
    calculatePolygon(poly)
    return poly
end

---Create a triangle
---@param A Vector
---@param B Vector
---@param C Vector
---@param UV_A Vector?
---@param UV_B Vector?
---@param UV_C Vector?
---@return Triangle
local function triangle(A, B, C, UV_A, UV_B, UV_C)
    ---@class Triangle
    local tri = {
        A,
        B,
        C,
        A = A,
        B = B,
        C = C,
        UV_A = UV_A,
        UV_B = UV_B,
        UV_C = UV_C,
    }
    return tri
end


local function triangleArea(p1, p2, p3)
    return (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
end

-- Check if point is inside triangle ABC
---@param P Vector
---@param A Triangle|Vector
---@param B Vector?
---@param C Vector?
---@return boolean
local function isPointInTriangle(P, A, B, C)
    if A.A or A[1] then
        -- triangle
        B = A[2]
        C = A[3]
        A = A[1] -- last
    end
    local d1 = triangleArea(P, A, B)
    local d2 = triangleArea(P, B, C)
    local d3 = triangleArea(P, C, A)
    local has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    local has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)
end

local function barycentricCoords(A, B, C, P)
    local v0 = C - A
    local v1 = B - A
    local v2 = P - A

    local d00 = v0:dot(v0)
    local d01 = v0:dot(v1)
    local d11 = v1:dot(v1)
    local d20 = v2:dot(v0)
    local d21 = v2:dot(v1)

    local denom = d00 * d11 - d01 * d01

    local v = (d11 * d20 - d01 * d21) / denom
    local w = (d00 * d21 - d01 * d20) / denom
    local u = 1.0 - v - w

    return u, v, w
end

---Interpolate the UV of a given triangle
---@param tri Triangle
---@param P Vector point
---@return Vector
local function interpolateUV(tri, P)
    local u, v, w = barycentricCoords(tri.A, tri.B, tri.C, P)
    local UV_P = vector.new(
        u * tri.UV_A.x + v * tri.UV_B.x + w * tri.UV_C.x,
        u * tri.UV_A.y + v * tri.UV_B.y + w * tri.UV_C.y,
        0
    )
    return UV_P
end


-- Ear clipping algorithm to triangulate polygon
---@param poly Polygon
---@return Triangle[]
function earClipping(poly)
    local triangles = {}
    local remainingPoints = { table.unpack(poly.points) }
    local remainingUV = { table.unpack(poly.uvpoints) }

    while #remainingPoints > 3 do
        local earFound = false
        for i = 1, #remainingPoints do
            local prevIndex = (i - 2) % #remainingPoints + 1
            local nextIndex = i % #remainingPoints + 1
            local A, B, C = remainingPoints[prevIndex], remainingPoints[i], remainingPoints[nextIndex]
            local UVA, UVB, UVC = remainingUV[prevIndex], remainingUV[i], remainingUV[nextIndex]

            local isEar = true
            for j, P in ipairs(remainingPoints) do
                if j ~= prevIndex and j ~= i and j ~= nextIndex and isPointInTriangle(P, A, B, C) then
                    isEar = false
                    break
                end
            end

            if isEar then
                if triangleArea(A, B, C) < 0 then
                    A, C = C, A -- Swap A and C to ensure counterclockwise order
                    UVA, UVC = UVC, UVA
                end
                table.insert(triangles, triangle(A, B, C, UVA, UVB, UVC))
                table.remove(remainingPoints, i)
                table.remove(remainingUV, i)
                earFound = true
                break
            end
        end

        if not earFound then
            error("No ears found. The polygon might be self-intersecting or not simple.")
        end
    end

    if #remainingPoints == 3 then
        local A, B, C = remainingPoints[1], remainingPoints[2], remainingPoints[3]
        local UVA, UVB, UVC = remainingUV[1], remainingUV[2], remainingUV[3]
        if triangleArea(A, B, C) < 0 then
            A, C = C, A -- Swap A and C to ensure counterclockwise order
            UVA, UVC = UVC, UVA
        end
        table.insert(triangles,
            triangle(A, B, C, UVA, UVB, UVC))
    else
        local center = remainingPoints[1]
        local centerUV = remainingUV[1]
        for i = 2, #remainingPoints - 1 do
            local A, B, C = center, remainingPoints[i], remainingPoints[i + 1]
            local UVA, UVB, UVC = centerUV, remainingUV[i], remainingUV[i + 1]
            if triangleArea(A, B, C) < 0 then
                A, C = C, A -- Swap A and C to ensure counterclockwise order
                UVA, UVC = UVC, UVA
            end
            table.insert(triangles, triangle(A, B, C, UVA, UVB, UVC))
        end
    end

    return triangles
end

local function points(...)
    local t = { ... }
    assert(#t % 2 == 0, "Odd number of coordinates!")
    local p = {}
    for i = 1, #t, 2 do
        p[#p + 1] = { x = t[i], y = t[i + 1] }
    end
    return p
end

---Get the corners of a rectangle, starting from the top-left corner.
---@param x number
---@param y number
---@param w number
---@param h number
---@return points
local function getRectanglePointsCorner(x, y, w, h)
    return points(x, y, x + w - 1, y, x + w - 1, y + h - 1, x, y + h - 1)
end

---Create the points of a circle of given quality
---@param x number
---@param y number
---@param r number
---@param sides number
---@return points
local function getCirclePoints(x, y, r, sides)
    local points = {}
    for i = 0, 359, 359 / sides do
        local dx = r * trig.cos(i)
        local dy = r * trig.sin(i)
        points[#points + 1] = { x = x + dx, y = y + dy }
    end
    return points
end

--- Polygon Renderers

---@param poly Polygon
---@param point Vector
local function pointInPolygon(poly, point)
    local oddNodes = false
    local j = #poly.points

    for i = 1, #poly.points do
        if (poly.points[i].y < point.y and poly.points[j].y >= point.y or poly.points[j].y < point.y and poly.points[i].y >= point.y) and
            (poly.points[i].x <= point.x or poly.points[j].x <= point.x) then
            if poly.points[i].x + (point.y - poly.points[i].y) / (poly.points[j].y - poly.points[i].y) * (poly.points[j].x - poly.points[i].x) < point.x then
                oddNodes = not oddNodes
            end
        end
        j = i
    end

    return oddNodes
end

---@param poly Polygon
---@param x integer
---@param y integer
---@param color color
local function setPixelForPolygon(poly, x, y, color)
    local dx, dy = trig.round(x - poly.axmin + 1), trig.round(y - poly.aymin + 1)
    poly.buffer = poly.buffer or {}
    poly.buffer[dy] = poly.buffer[dy] or {}
    poly.buffer[dy][dx] = color
    graphics.setPixel(x, y, color)
end


---Draw a line between two points
---@param poly Polygon
---@param x0 number
---@param y0 number
---@param x1 number
---@param y1 number
---@param color color
local function drawLineForPolygon(poly, x0, y0, x1, y1, color)
    local length = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
    for t = 0, 1, 1 / (length * 1.1) do
        local x = graphics.lerp(x0, x1, t)
        local y = graphics.lerp(y0, y1, t)
        setPixelForPolygon(poly, trig.round(x), trig.round(y), color)
    end
end

local function defaultPolygonRender(poly)
    for i = 1, #poly.points do
        local ni = (i % #poly.points) + 1
        drawLineForPolygon(poly, poly.points[i].x, poly.points[i].y, poly.points[ni].x, poly.points[ni].y, poly.color)
    end
    poly.cacheValid = true
end

---@param poly Polygon
local function filledPolygonRender(poly)
    local pos = vector.new(0, 0, 0)
    for dy = poly.ymin, poly.ymax do
        for dx = poly.xmin, poly.xmax do
            local x, y = poly.center.x + dx, poly.center.y + dy
            pos.x, pos.y = x, y
            if pointInPolygon(poly, pos) then
                setPixelForPolygon(poly, x, y, poly.color)
            end
        end
    end
    poly.cacheValid = true
end

local triangleColors = { colors.red, colors.blue, colors.green }
---@param poly Polygon
local function wireFrameRender(poly)
    for _, v in ipairs(poly.triangles) do
        -- error(textutils.serialise(v))
        for i = 1, 3 do
            local ni = (i % 3) + 1
            local color = triangleColors[i]
            drawLineForPolygon(poly, v[i].x, v[i].y, v[ni].x, v[ni].y, color)
        end
    end
    poly.cacheValid = true
end

local reverseBlitLUT = {}
for _, color in pairs(colors) do
    if type(color) == "number" then
        reverseBlitLUT[colors.toBlit(color)] = color
    end
end

---@param poly Polygon
local function textureRender(poly)
    assert(poly.texture, "Polygon has no texture!")
    local tw, th = #poly.texture[1], #poly.texture
    local pos = vector.new(0, 0, 0)
    for dy = poly.ymin, poly.ymax do
        for dx = poly.xmin, poly.xmax do
            local x, y = poly.center.x + dx, poly.center.y + dy
            pos.x, pos.y = x, y
            for _, tri in ipairs(poly.triangles) do
                if isPointInTriangle(pos, tri) then
                    local uvpos = interpolateUV(tri, pos)
                    uvpos.x = uvpos.x % 1
                    uvpos.y = uvpos.y % 1
                    local tx = trig.round(uvpos.x * (tw - 1)) + 1
                    local ty = trig.round(uvpos.y * (th - 1)) + 1
                    local color = poly.texture[ty][tx]
                    setPixelForPolygon(poly, x, y, color)
                    break
                end
            end
        end
    end
    -- poly.cacheValid = true
end

---@param poly Polygon
---@param horizontal boolean
local function debugUV(poly, horizontal)
    local pos = vector.new(0, 0, 0)
    for dy = poly.ymin, poly.ymax, 3 do
        for dx = poly.xmin, poly.xmax, 2 do
            local x, y = poly.center.x + dx, poly.center.y + dy
            pos.x, pos.y = x, y
            local sx, sy = graphics.worldToScreenPos(x, y)
            for _, tri in ipairs(poly.triangles) do
                if isPointInTriangle(pos, tri) then
                    local uvpos = interpolateUV(tri, pos)
                    win.setCursorPos(trig.round(sx / 2), trig.round(sy / 3))
                    if horizontal then
                        win.write(("%1d"):format(uvpos.x * 10))
                    else
                        win.write(("%1d"):format(uvpos.y * 10))
                    end
                    break
                end
            end
        end
    end
end

---@param poly Polygon
local function rgbTriangleRender(poly)
    local pos = vector.new(0, 0, 0)
    for dy = poly.ymin, poly.ymax do
        for dx = poly.xmin, poly.xmax do
            local x, y = poly.center.x + dx, poly.center.y + dy
            pos.x, pos.y = x, y
            for _, tri in ipairs(poly.triangles) do
                if isPointInTriangle(pos, tri) then
                    local u, v, w = barycentricCoords(tri.A, tri.B, tri.C, pos)
                    local color = colors.white
                    if u > v and u > w then
                        color = colors.red
                    elseif v > u and v > w then
                        color = colors.green
                    elseif w > u and w > v then
                        color = colors.blue
                    end
                    setPixelForPolygon(poly, x, y, color)
                    break
                end
            end
        end
    end
    poly.cacheValid = true
end

---@param poly Polygon
local function texturedWireframeRender(poly)
    textureRender(poly)
    wireFrameRender(poly)
end

---@param poly Polygon
local function cachePolygonRender(poly)
    for dy, _ in pairs(poly.buffer) do
        for dx, color in pairs(poly.buffer[dy]) do
            local x, y = poly.axmin + dx, poly.aymin + dy
            if poly.buffer[dy] and poly.buffer[dy][dx] then
                graphics.setPixel(x, y, color)
            end
        end
    end
end

---@param poly Polygon
local function polyWithinViewport(poly)
    return graphics.withinViewport(poly.axmin, poly.aymin, poly.axmax, poly.aymax)
end

---@param polyA Polygon
---@param polyB Polygon
---@param padding number?
local function polyOverlap(polyA, polyB, padding)
    padding = padding or 0
    return (polyA.axmin - padding < polyB.axmax and polyA.axmax + padding > polyB.axmin) and
        (polyA.aymin - padding < polyB.aymax and polyA.aymax + padding > polyB.aymin)
end

---Draw lines between a list of points
---@param poly Polygon
local function drawPolygon(poly)
    if not polyWithinViewport(poly) then return end
    if poly.cacheValid then
        cachePolygonRender(poly)
    elseif poly.renderer then
        poly:renderer()
    else
        defaultPolygonRender(poly)
    end
end

---Apply a 2D rotation to a given point around 0,0
---@param x number
---@param y number
---@param degrees number
---@return number
---@return number
local function rotatePoint(x, y, degrees)
    local sin, cos = trig.sin(degrees), trig.cos(degrees)
    return x * cos - y * sin, x * sin + y * cos
end


---Get the corners of a rectangle
---@param x number
---@param y number
---@param w number
---@param h number
---@param angle number?
---@return points
local function getRectangleCorners(x, y, w, h, angle)
    local corners = {}
    local dirs = {
        { x = -1, y = 1 }, { x = 1, y = 1 }, { x = 1, y = -1 }, { x = -1, y = -1 }
    }
    angle = angle or 0
    for i = 1, 4 do
        local rx = dirs[i].x * w / 2
        local ry = dirs[i].y * h / 2
        rx, ry = rotatePoint(rx, ry, angle)
        corners[i] = {
            x = trig.round(x + rx),
            y = trig.round(y + ry)
        }
    end
    return corners
end

---Draw a rectangle (out from the center-point)
---@param x number
---@param y number
---@param w number
---@param h number
---@param color color
---@param angle number?
---@param filled boolean?
local function drawRectangle(x, y, w, h, color, angle, filled)
    local corners = getRectangleCorners(x, y, w, h, angle)
    local poly = polygon(corners, color)
    if filled then
        poly.renderer = filledPolygonRender
    end
    poly.cacheValid = false
    drawPolygon(poly)
end

local function loadTexture(fn)
    local f = assert(fs.open(fn, "r"))
    local t = f.readAll()
    f.close()
    local data = textutils.unserialise(t)
    assert(type(data) == "table", ("File %s is not a valid file!"):format(fn))
    local stage1
    if type(data[1]) == "table" then
        if type(data[1][1] == "table") then
            -- this is a BIMG
            stage1 = {}
            for i, v in ipairs(data[1]) do
                stage1[#stage1 + 1] = v[2] -- copy out background colors
            end
        end
    elseif type(data[1]) == "string" then
        stage1 = data
    end
    assert(stage1, ("%s is not a recognized image!"):format(fn))
    local stage2 = {}
    for row, str in ipairs(stage1) do
        stage2[row] = {}
        for i = 1, #str do
            stage2[row][i] = reverseBlitLUT[str:sub(i, i)]
        end
    end
    return stage2
end

return {
    polygon = polygon,
    getCirclePoints = getCirclePoints,
    getRectangleCorners = getRectangleCorners,
    getRectanglePointsCorner = getRectanglePointsCorner,
    drawPolygon = drawPolygon,
    drawRectangle = drawRectangle,
    polyWithinViewport = polyWithinViewport,
    polyOverlap = polyOverlap,
    loadTexture = loadTexture,
    renderers = {
        textureRender = textureRender,
        filledPolygonRender = filledPolygonRender,
        wireFrameRender = wireFrameRender,
        texturedWireframeRender = texturedWireframeRender,
        rgbTriangleRender = rgbTriangleRender,
        debugUV = debugUV
    },
    debug = {
        logPolygon = logPolygon
    }
}

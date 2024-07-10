local trig = require "libs.trig"
local graphics = require "libs.graphics"

local function vectorize(v)
    return vector.new(v.x or 0, v.y or 0, v.z or 0)
end

-- Ear clipping algorithm to triangulate polygon
---@return integer[][]
local earClipping

---@class Texture
---@field data color[][]
---@field w integer
---@field h integer

local function log(s, ...)
    local f = assert(fs.open("log.txt", "a"))
    f.writeLine(s:format(...))
    f.close()
end

---@param poly Polygon
local function calculatePolygonBounds(poly)
    local bounds = { math.huge, math.huge, -math.huge, -math.huge }
    poly.bounds = bounds
    for _, p in ipairs(poly.points) do
        bounds[1] = math.min(bounds[1], p[1])
        bounds[2] = math.min(bounds[2], p[2])
        bounds[3] = math.max(bounds[3], p[1])
        bounds[4] = math.max(bounds[4], p[2])
    end
end

---@param poly Polygon
local function generatePolygonUVs(poly)
    for _, p in ipairs(poly.points) do
        local rx, ry = p[1] - poly.bounds[1], p[2] - poly.bounds[2] -- 0 based
        local w, h = poly.bounds[3] - poly.bounds[1], poly.bounds[4] - poly.bounds[2]
        local uvw, uvh = poly.uvbounds[3] - poly.uvbounds[1], poly.uvbounds[4] - poly.uvbounds[2]
        p[3] = ((rx / w) * uvw) + poly.uvbounds[1]
        p[4] = ((ry / h) * uvh) + poly.uvbounds[2]
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


---@param p1 Point
---@param p2 Point
---@param p3 Point
---@return number
local function triangleArea(p1, p2, p3)
    return (p1[1] - p3[1]) * (p2[2] - p3[2]) - (p2[1] - p3[1]) * (p1[2] - p3[2])
end

-- Check if point is inside triangle ABC
---@param P Point
---@param A Point
---@param B Point
---@param C Point
---@return boolean
local function isPointInTriangle(P, A, B, C)
    local d1 = triangleArea(P, A, B)
    local d2 = triangleArea(P, B, C)
    local d3 = triangleArea(P, C, A)
    local has_neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    local has_pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (has_neg and has_pos)
end

-- Ear clipping algorithm to triangulate polygon
---@param poly Polygon
---@return Triangle[]
function earClipping(poly)
    local triangles = {}
    local remainingPoints = { table.unpack(poly.apoints) }

    while #remainingPoints > 3 do
        local earFound = false
        for i = 1, #remainingPoints do
            local prevIndex = (i - 2) % #remainingPoints + 1
            local nextIndex = i % #remainingPoints + 1
            local A, B, C = remainingPoints[prevIndex], remainingPoints[i], remainingPoints[nextIndex]

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
                end
                table.insert(triangles, { A, B, C })
                table.remove(remainingPoints, i)
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
        if triangleArea(A, B, C) < 0 then
            A, C = C, A -- Swap A and C to ensure counterclockwise order
        end
        table.insert(triangles, { A, B, C })
    else
        local center = remainingPoints[1]
        for i = 2, #remainingPoints - 1 do
            local A, B, C = center, remainingPoints[i], remainingPoints[i + 1]
            if triangleArea(A, B, C) < 0 then
                A, C = C, A -- Swap A and C to ensure counterclockwise order
            end
            table.insert(triangles, { A, B, C })
        end
    end

    return triangles
end

---Apply the given rotation, position, and scale to the polygon's points, then generates the triangles
---@param poly Polygon
local function calculatePolygonTriangles(poly)
    poly.apoints = {}
    for i, p in ipairs(poly.points) do
        local x, y = p[1] * poly.scale, p[2] * poly.scale
        if poly.angle ~= 0 then
            x, y = rotatePoint(x, y, poly.angle)
        end
        x, y = x + poly.pos.x, y + poly.pos.y
        poly.apoints[i] = { x, y, p[3], p[4] }
    end
    local center = vector.new(0, 0, 0)
    for _, p in ipairs(poly.apoints) do
        center = center + vector.new(p[1], p[2], 0)
    end
    poly.center = center / #poly.apoints
    poly.triangles = earClipping(poly)
end

---@type table<color,Texture>
local colorTextures = {}
for _, v in pairs(colors) do
    if type(v) == "number" then
        colorTextures[v] = { data = { { v } }, w = 1, h = 1 }
    end
end

---@param pos Vector
---@param relPoints Point[]|Vector[] List of points, if UV not present it will be generated automatically
---@param color color?
---@return Polygon
local function polygon(pos, relPoints, color)
    ---@class Polygon
    ---@field points Point[]
    ---@field bounds Point
    ---@field uvbounds Point
    ---@field scale number
    ---@field pos Vector
    ---@field center Vector Absolute position of the center of this
    ---@field angle number
    ---@field texture Texture
    ---@field triangles Triangle[]
    ---@field apoints Point[] absolute positioned points
    local poly = {}
    poly.scale = 1
    poly.pos = pos
    poly.angle = 0
    poly.uvbounds = { 0, 0, 1, 1 }
    poly.points = {}
    if color then
        poly.texture = { data = { { color } }, w = 1, h = 1 }
    end
    --- Points processing: Convert Vector to Point
    for i, v in ipairs(relPoints) do
        if v.x then
            -- Vector
            poly.points[i] = { v.x, v.y }
        else
            poly.points[i] = v
        end
    end
    calculatePolygonBounds(poly)
    -- Generate UVs
    if not poly.points[1][3] then
        generatePolygonUVs(poly)
    end
    calculatePolygonTriangles(poly)
    return poly
end

---@param poly Polygon
---@return Vector[] points
local function getPolygonWorldVectors(poly)
    local vecs = {}
    for i, v in ipairs(poly.apoints) do
        vecs[i] = vector.new(v[1], v[2], 0)
    end
    return vecs
end


---Get the corners of a rectangle, starting from the top-left corner.
---@param w number
---@param h number
---@return Point[]
local function getRectanglePointsCorner(w, h)
    return { { 0, 0 }, { w, 0 }, { w, h }, { 0, h } }
end

---Create the points of a circle of given quality
---@param r number
---@param sides number
---@return Point[]
local function getCirclePoints(r, sides)
    local points = {}
    for i = 0, 359, 359 / sides do
        local dx = r * trig.cos(i)
        local dy = r * trig.sin(i)
        points[#points + 1] = { dx, dy }
    end
    return points
end

--- Polygon Renderers

---@param poly Polygon
---@param point Vector
local function pointInPolygon(poly, point)
    local oddNodes = false
    local j = #poly.apoints

    for i = 1, #poly.apoints do
        if (poly.apoints[i][2] < point.y and poly.apoints[j][2] >= point.y or poly.apoints[j][2] < point.y and poly.apoints[i][2] >= point.y) and
            (poly.apoints[i][1] <= point.x or poly.apoints[j][1] <= point.x) then
            if poly.apoints[i][1] + (point.y - poly.apoints[i][2]) / (poly.apoints[j][2] - poly.apoints[i][2]) * (poly.apoints[j][1] - poly.apoints[i][1]) < point.x then
                oddNodes = not oddNodes
            end
        end
        j = i
    end

    return oddNodes
end

local reverseBlitLUT = {
    [" "] = -1
}
for _, color in pairs(colors) do
    if type(color) == "number" then
        reverseBlitLUT[colors.toBlit(color)] = color
    end
end

---@param poly Polygon
local function polyWithinViewport(poly)
    return graphics.withinViewport(poly.bounds[1] + poly.pos.x, poly.bounds[2] + poly.pos.y, poly.bounds[3] + poly.pos.x,
        poly.bounds[4] + poly.pos.y)
end

---@param polyA Polygon
---@param polyB Polygon
---@param padding number?
local function polyOverlap(polyA, polyB, padding)
    padding = padding or 0
    return (polyA.bounds[1] - padding < polyB.bounds[3] and polyA.bounds[3] + padding > polyB.bounds[1]) and
        (polyA.bounds[2] - padding < polyB.bounds[4] and polyA.bounds[4] + padding > polyB.bounds[2])
end

local function defaultFrag(poly, x, y, u, w)
    local tex = poly.texture
    local tw, th = tex.w, tex.h
    local tx, ty = (u * tw) % tw + 1, (w * th) % th + 1
    tx, ty = math.min(tw, math.max(1, tx)), math.min(th, math.max(1, ty))
    local col = tex.data[math.floor(ty)][math.floor(tx)]
    if col ~= -1 then
        graphics.setPixel(x, y, col)
    end
end

---Draw lines between a list of points
---@param poly Polygon
local function drawPolygon(poly)
    -- if not polyWithinViewport(poly) then return end
    for _, tri in ipairs(poly.triangles) do
        graphics.renderTriangle(poly, tri[1], tri[2], tri[3], defaultFrag)
    end
end

---Get the corners of a rectangle from the centerpoint
---@param w number
---@param h number
---@return Point[]
local function getRectangleCorners(w, h)
    local corners = {
        { -w / 2, -h / 2 },
        { w / 2,  -h / 2 },
        { w / 2,  h / 2 },
        { -w / 2, h / 2 }
    }
    return corners
end

local function parseTexture(s)
    local data = textutils.unserialise(s)
    assert(type(data) == "table", "Invalid texture")
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
    assert(stage1, "Not a valid image format!")
    local stage2 = { data = {} }
    for row, str in ipairs(stage1) do
        stage2.data[row] = {}
        for i = 1, #str do
            stage2.data[row][i] = reverseBlitLUT[str:sub(i, i)]
        end
    end
    stage2.w = #stage2.data[1]
    stage2.h = #stage2.data
    return stage2
end

local function loadTexture(fn)
    local f = assert(fs.open(fn, "r"))
    local t = f.readAll()
    f.close()
    return parseTexture(t)
end

---@param axis Vector
---@param poly Polygon
---@return number min
---@return number max
local function projectPolygon(axis, poly)
    local pointsVectors = {}
    for i, v in ipairs(poly.apoints) do
        pointsVectors[i] = vector.new(v[1], v[2], 0)
    end
    local dotProduct = axis:dot(pointsVectors[1])
    local min, max = dotProduct, dotProduct
    for i, v in ipairs(pointsVectors) do
        dotProduct = v:dot(axis)
        min = math.min(min, dotProduct)
        max = math.max(max, dotProduct)
    end
    return min, max
end

local function intervalDistance(minA, maxA, minB, maxB)
    if minA < minB then
        return minB - maxA
    end
    return minA - maxB
end

---@param polyA Polygon
---@param polyB Polygon
---@param velocity Vector
local function polygonCollision(polyA, polyB, velocity)
    local intersect = true
    local willIntersect = true

    local edgeCountA = #polyA.points
    local edgeCountB = #polyB.points
    local minIntervalDistance = math.huge
    local minTranslationVector = vector.new(0, 0, 0)
    local translationAxis = vector.new(0, 0, 0)
    local collisionNormal = vector.new(0, 0, 0)

    local function getEdge(poly, index)
        local currentPoint = poly.apoints[index]
        local nextPoint = poly.apoints[(index % #poly.apoints) + 1]
        return vector.new(nextPoint[1] - currentPoint[1], nextPoint[2] - currentPoint[2], 0),
            vector.new((nextPoint[2] - currentPoint[2]), -(nextPoint[1] - currentPoint[1]), 0)
    end

    for i = 1, edgeCountA + edgeCountB - 1 do
        local edge, normal
        if i <= edgeCountA then
            edge, normal = getEdge(polyA, i)
        else
            edge, normal = getEdge(polyB, i - edgeCountA)
        end

        local axis = vector.new(-edge.y, edge.x, 0)
        axis = axis:normalize()

        local minA, minB, maxA, maxB = 0, 0, 0, 0
        minA, maxA = projectPolygon(axis, polyA)
        minB, maxB = projectPolygon(axis, polyB)

        if intervalDistance(minA, maxA, minB, maxB) > 0 then
            intersect = false -- not currently intersecting
        end

        local velocityProjection = axis:dot(velocity)
        if velocityProjection < 0 then
            minA = minA + velocityProjection
        else
            maxA = maxA + velocityProjection
        end

        local distance = intervalDistance(minA, maxA, minB, maxB)
        if distance > 0 then
            willIntersect = false
        end
        if (not intersect) and (not willIntersect) then
            break
        end

        distance = math.abs(distance)
        if distance < minIntervalDistance then
            minIntervalDistance = distance
            translationAxis = axis
            collisionNormal = normal

            local d = polyA.center - polyB.center
            if d:dot(translationAxis) < 0 then
                translationAxis = translationAxis:unm()
            end
        end
    end
    if willIntersect then
        minTranslationVector = translationAxis * minIntervalDistance
    end
    return {
        willIntersect = willIntersect,
        minimumTranslationVector = minTranslationVector,
        intersect = intersect,
        translationAxis = translationAxis,
        collisionNormal = collisionNormal
    }
end



return {
    polygon = polygon,
    getCirclePoints = getCirclePoints,
    getRectangleCorners = getRectangleCorners,
    getRectanglePointsCorner = getRectanglePointsCorner,
    drawPolygon = drawPolygon,
    polyWithinViewport = polyWithinViewport,
    polyOverlap = polyOverlap,
    loadTexture = loadTexture,
    calculatePolygonTriangles = calculatePolygonTriangles,
    colorTextures = colorTextures,
    polygonCollision = polygonCollision,
    parseTexture = parseTexture,
    pointInPolygon = pointInPolygon
}

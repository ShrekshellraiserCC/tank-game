local map = {}

local shapes = require "libs.shapes"
local palette = require "libs.palette"

---@class SavedMap
---@field name string
---@field description string?
---@field walls table
---@field doors table?
---@field textures table?

---@class LoadedMap : SavedMap
---@field walls Polygon[]
---@field textures table<string,Texture>

---@param v any
---@param s string
---@param ... any
---@return any
local function nassert(v, s, ...)
    if not v then
        term.clear()
        term.setCursorPos(1, 1)
        error(s:format(...), 0)
    end
    return v
end

---@param v any
---@param part string
---@param i integer polygon #
---@param s string
---@param ... any
---@return any
local function passert(v, part, i, s, ...)
    return nassert(v, ("Error parsing polygon %s/%d: %s"):format(part, i, s), ...)
end

---@param part string
---@param i integer
---@return Polygon
local function parseShapes(part, i, desc)
    passert(type(desc.position) == "table" and desc.position[1] and desc.position[2],
        part, i, "Invalid position.")
    local position = vector.new(desc.position[1], desc.position[2], 0)
    local points
    if desc.shape == "rect" then
        passert(desc.width and desc.height, part, i, "rect missing width/height.")
        points = shapes.getRectanglePointsCorner(desc.width, desc.height)
    elseif desc.shape == "ctr_rect" then
        passert(desc.width and desc.height, part, i, "ctr_rect missing width/height.")
        points = shapes.getRectangleCorners(desc.width, desc.height)
    elseif desc.shape == "circle" then
        passert(desc.radius and desc.quality, part, i, "circle missing radius/quality")
        points = shapes.getCirclePoints(desc.radius, desc.quality)
    end
    passert(points, part, i, "Unrecognized shape '%s'.", desc.shape)
    return shapes.polygon(position, points)
end

---@param loaded LoadedMap
---@param part string
---@param i integer
---@return Polygon
local function parsePolygon(loaded, part, i, desc)
    passert(type(desc.position) == "table" and desc.position[1] and desc.position[2],
        part, i, "Invalid position.")
    local position = vector.new(desc.position[1], desc.position[2], 0)
    local poly
    if desc.shape then
        poly = parseShapes(part, i, desc)
    else
        passert(desc.points, part, i, "Not a shape, but has no points.")
        poly = shapes.polygon(position, desc.points)
    end
    if desc.texture then
        passert(loaded.textures[desc.texture], part, i, "Texture '%s' is not defined.", desc.texture)
        poly.texture = loaded.textures[desc.texture]
    elseif desc.color then
        poly.texture = shapes.colorTextures[palette.colors[desc.color]]
        passert(poly.texture, part, i, "Unrecognized color '%s'.", desc.color)
    else
        passert(false, part, i, "Missing a texture or color")
    end
    return poly
end

---@return LoadedMap
function map.loadMap(s)
    local json = s
    if type(json) == "string" then
        json = textutils.unserialise(s)
    end
    if type(json) ~= "table" then
        json = textutils.unserialiseJSON(s)
    end
    nassert(type(json) == "table", "Map is not a table!")
    nassert(json.name, "Map is invalid, it has no name!")
    ---@type SavedMap
    json = json
    ---@type LoadedMap
    local loadedMap = {
        name = json.name,
        description = json.description,
        walls = {},
        doors = {},
        textures = {}
    }
    for k, v in pairs(json.textures) do
        if fs.exists(k) then
            local ok, texture = pcall(function() return shapes.loadTexture(v) end)
            nassert(ok, "Error loading texture %s from file: %s", k, texture)
            loadedMap.textures[k] = texture
        else
            local ok, texture = pcall(function() return shapes.parseTexture(v) end)
            nassert(ok, "Error parsing texture %s data: %s", k, texture)
            loadedMap.textures[k] = texture
        end
    end
    for i, v in ipairs(json.walls) do
        loadedMap.walls[i] = parsePolygon(loadedMap, "wall", i, v)
    end
    for i, v in ipairs(json.doors) do
        loadedMap.doors[i] = parsePolygon(loadedMap, "door", i, v)
        passert(v.team, "door", i, "Door is missing a team!")
        loadedMap.doors[i].team = v.team
    end
    return loadedMap
end

local function readFile(fn)
    local f = assert(fs.open(fn, "r"))
    local s = f.readAll()
    f.close()
    return s
end

function map.loadMapFile(fn)
    local s = readFile(fn)
    return map.loadMap(assert(textutils.unserializeJSON(s)) --[[@as table]])
end

---@param m LoadedMap
function map.renderMap(m)
    for _, v in pairs(m.walls) do
        shapes.drawPolygon(v)
    end
    for _, v in pairs(m.doors) do
        shapes.drawPolygon(v)
    end
end

return map

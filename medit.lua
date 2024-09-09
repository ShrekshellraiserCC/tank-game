local map      = require("libs.map")
local mbar     = require("libs.mbar")
local graphics = require("libs.graphics")
local shapes   = require("libs.shapes")
local palette  = require("libs.palette")
local sidebar  = require("libs.sidebar")

local win      = window.create(term.current(), 1, 1, term.getSize())

palette.apply(win)
mbar.setWindow(win)
local sbar = sidebar.new(win, 20)
local fakebox = require("libs.fakebox").new(win)
local pixelbox = require("libs.pixelbox").new(win)

local activeBox
local function setOneToOneScale(oneToOne)
    if oneToOne then
        graphics.mulx, graphics.muly = 1, 1
        graphics.setBox(fakebox)
        activeBox = fakebox
    else
        graphics.mulx, graphics.muly = 2, 3
        graphics.setBox(pixelbox)
        activeBox = pixelbox
    end
end
setOneToOneScale(false)
-- graphics.setViewCenter(10, 10)

local baseWidth, baseHeight = 51, 19

---@type SavedMap
local smap
---@type LoadedMap
local wmap

---@type Polygon?
local selectedPoly
---@type integer
local selectedIndex = 0
---@type "doors"|"walls"|"spawn"?
local selectedType

local function updateWorkingMap()
    wmap = map.loadMap(smap)
    if selectedPoly then
        selectedPoly = wmap[selectedType][selectedIndex]
    end
end
local function loadMap(name)
    local s = map.readFile(name)
    smap = textutils.unserialiseJSON(s) --[[@as SavedMap]]
    updateWorkingMap()
end
loadMap("maps/default.json")

local running = true
local quitButton = mbar.button("Quit", function(entry)
    running = false
end)
local fileMenu = mbar.buttonMenu { quitButton }
local fileButton = mbar.button("File", nil, fileMenu)

local viewTermViewport = false
local termViewboxButton = mbar.toggleButton("Term Viewport", function(self)
    viewTermViewport = self.value
end)
local viewSpawnpoints = false
local viewSpawnpointsButton = mbar.toggleButton("Spawnpoints", function(self)
    viewSpawnpoints = self.value
end)
local oneToOneScaleButton = mbar.toggleButton("1:1 View", function(self)
    setOneToOneScale(self.value)
end)
local viewMenu = mbar.buttonMenu { termViewboxButton, viewSpawnpointsButton, oneToOneScaleButton }
local viewButton = mbar.button("View", nil, viewMenu)

local bar = mbar.bar { fileButton, viewButton }
bar.shortcut(quitButton, keys.q, true)

local vx, vy = 1, 1
local clickx, clicky
local ovx, ovy
graphics.setViewCorner(vx, vy)

local function scp(x, y)
    win.setCursorPos(x, y)
end
---@param fg integer?
---@param bg integer?
---@return integer ofg
---@return integer obg
local function col(fg, bg)
    local ofg = win.getTextColor()
    local obg = win.getBackgroundColor()
    win.setTextColor(fg or ofg)
    win.setBackgroundColor(bg or obg)
    return ofg, obg
end

local function divscale(x, y)
    return x / graphics.mulx, y / graphics.muly
end
local function mulscale(x, y)
    return x * graphics.mulx, y * graphics.muly
end

---Get the screen coordinates (actual) of the corners of a gizmo for the given polygon
---@param poly Polygon
---@return number x1
---@return number y1
---@return number x2
---@return number y2
local function getGizmoCorners(poly)
    local px, py = poly.pos.x, poly.pos.y
    local x1, y1 = graphics.worldToScreenPos(px + poly.bounds[1] - 1, py + poly.bounds[2] - 1)
    local x2, y2 = graphics.worldToScreenPos(px + poly.bounds[3], py + poly.bounds[4])

    local ow, oh = x2 - x1, y2 - y1

    local x1r, y1r = divscale(x1, y1)
    local x2r, y2r = divscale(x2, y2)
    -- local cx, cy = math.ceil((x1r + x2r) / 2), math.ceil((y1r + y2r) / 2)

    -- local hw, hh = math.floor(ow / 2), math.floor(oh / 2)
    -- local x1rs, y1rs = cx - hw, cy - hh
    -- local x2rs, y2rs = x1rs + ow, y1rs + oh

    return math.ceil(x1r - 1), math.ceil(y1r - 1), x2r + 1, y2r + 1
end

local function drawGizmoBox(x1, y1, x2, y2)
    local ofg, obg = col(colors.white, colors.black)
    local w = x2 - x1 - 1
    local h = y2 - y1 - 1
    local hbar = ("\132"):rep(w)
    local cornerch = "\8"
    scp(x1, y1)
    win.write(cornerch)
    win.write(hbar)
    win.write(cornerch)
    scp(x1, y2)
    win.write(cornerch)
    win.write(hbar)
    win.write(cornerch)
    for dy = 1, h do
        local ch = dy % 2 == 0 and "\145" or "\132"
        scp(x1, y1 + dy)
        win.write(ch)
        scp(x2, y1 + dy)
        win.write(ch)
    end
    col(ofg, obg)
end

---@param poly Polygon
local function drawGizmoBoxp(poly)
    local x1, y1, x2, y2 = getGizmoCorners(poly)
    drawGizmoBox(x1, y1, x2, y2)
end

---@param x integer
---@param y integer
---@return Polygon?
---@return "doors"|"walls"
---@return integer
local function getClickedOnPolygon(x, y)
    local vec = vector.new(x, y, 0)
    for k, v in ipairs(wmap.walls) do
        if shapes.pointInPolygon(v, vec) then
            return v, "walls", k
        end
    end
    for k, v in ipairs(wmap.doors) do
        if shapes.pointInPolygon(v, vec) then
            return v, "doors", k
        end
    end
    return nil, "doors", -1
end

local function renderSpawnpoints()
    if not viewSpawnpoints then return end
    local ofg, obg = col(palette.colors.red, palette.colors.black)
    for k, v in ipairs(wmap.spawns.red) do
        local x, y = divscale(graphics.worldToScreenPos(v[1], v[2]))
        scp(x, y)
        win.write("\2")
    end
    col(palette.colors.blue, palette.colors.black)
    for k, v in ipairs(wmap.spawns.blue) do
        local x, y = divscale(graphics.worldToScreenPos(v[1], v[2]))
        scp(x, y)
        win.write("\2")
    end
    col(ofg, obg)
end

local function renderTermViewport()
    if not viewTermViewport then return end
    local tw, th = term.getSize()
    local vpw, vph = baseWidth, baseHeight
    if activeBox == fakebox then
        vpw, vph = vpw * 2, vph * 3
    end
    local cx, cy = math.floor((tw - vpw) / 2), math.floor((th - vph) / 2)
    local x1, y1 = graphics.screenToWorldPos(mulscale(cx, cy))
    local x2, y2 = graphics.screenToWorldPos(mulscale(cx + vpw + 1, cy + vph + 1))
    graphics.drawRectangle(x1, y1, x2, y2, colors.white)
end

local updated = true
local function renderLoop()
    while true do
        sbar.showCursor(win)
        sleep()
        if updated then
            win.setVisible(false)
            win.clear()
            activeBox:clear(colors.black)
            map.renderMap(wmap)
            renderTermViewport()
            activeBox:render()
            renderSpawnpoints()
            if selectedPoly then
                drawGizmoBoxp(selectedPoly)
            end
            sbar.render()
            bar.render()
            win.setVisible(true)
            updated = false
        end
    end
end

local shapeOptions = { "rect", "ctr_rect", "circle" }

local wallRectScheme = {
    sidebar.label("Wall"),
    sidebar.numberInput("Pos X", "position", 1),
    sidebar.numberInput("Pos Y", "position", 2),
    sidebar.dropdown("Shape", shapeOptions, "shape"),
    sidebar.numberInput("Width", "width"),
    sidebar.numberInput("Height", "height")
}

local doorRectScheme = {
    sidebar.label("Door"),
    sidebar.numberInput("Pos X", "position", 1),
    sidebar.numberInput("Pos Y", "position", 2),
    sidebar.dropdown("Shape", shapeOptions, "shape"),
    sidebar.dropdown("Team", { "red", "blue" }, "team"),
    sidebar.numberInput("Width", "width"),
    sidebar.numberInput("Height", "height")
}

local schemes = {
    walls = {
        rect = wallRectScheme,
        ctr_rect = wallRectScheme
    },
    doors = {
        rect = doorRectScheme,
        ctr_rect = doorRectScheme
    }
}

local function polygonUpdate(data)
    updateWorkingMap()
end

---@type "none"|"camera"|"object"|"object_inital"
local selectionMode = "none"
local wasMouseDragged = false
local eventHandlers = {
    mouse_click = function(button, x, y)
        clickx, clicky = x, y
        local npoly, npolyType, nPolyIndex =
            getClickedOnPolygon(graphics.screenToWorldPos(mulscale(x, y)))
        if npoly then
            ovx, ovy = npoly.pos.x, npoly.pos.y
            updated = true
            selectionMode = "object_inital"
            selectedPoly, selectedType, selectedIndex = npoly, npolyType, nPolyIndex
            local spoly = smap[selectedType][selectedIndex]
            local scheme = schemes[selectedType][spoly.shape]
            sbar.update(scheme, spoly, polygonUpdate)
        else
            selectionMode = "camera"
            ovx, ovy = vx, vy
        end
    end,
    mouse_drag = function(button, x, y)
        if selectionMode == "camera" then
            vx = ovx - (x - clickx) * graphics.mulx
            vy = ovy - (y - clicky) * graphics.muly
            graphics.setViewCorner(vx, vy)
            updated = true
        elseif selectionMode == "object_inital" then
            assert(selectedPoly, "No poly?")
            local nx = ovx + (x - clickx) * graphics.mulx
            local ny = ovy + (y - clicky) * graphics.muly
            local rpoly = smap[selectedType][selectedIndex]
            rpoly.position[1] = nx
            rpoly.position[2] = ny
            updateWorkingMap()
            updated = true
        end
        wasMouseDragged = true
    end,
    mouse_up = function(button, x, y)
        if selectionMode == "camera" then
            ovx, ovy = nil, nil
            updated = true
            selectionMode = "none"
            if not wasMouseDragged then
                selectedPoly, selectedType, selectedIndex = nil, nil, -1
            end
        elseif selectionMode == "object_inital" then
            selectionMode = "object"
        end
        wasMouseDragged = false
    end,
}

local function eventLoop()
    graphics.setViewCorner(vx, vy)
    while running do
        local e = table.pack(os.pullEvent())
        if not (bar.onEvent(e) or sbar.onEvent(e)) then
            if eventHandlers[e[1]] then
                eventHandlers[e[1]](table.unpack(e, 2))
            end
        else
            updated = true
        end
    end
end

parallel.waitForAny(renderLoop, eventLoop)

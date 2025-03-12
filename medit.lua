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
local bixelbox = require("libs.bixelbox").new(win)

local activeBox
---@param mode "1x"|"real"|"2x"
local function setScaleMode(mode)
    if mode == "1x" then
        graphics.mulx, graphics.muly = 1, 1
        graphics.setBox(fakebox)
        activeBox = fakebox
    elseif mode == "2x" then
        graphics.mulx, graphics.muly = 1, 1.5
        graphics.setBox(bixelbox)
        activeBox = bixelbox
    else
        graphics.mulx, graphics.muly = 2, 3
        graphics.setBox(pixelbox)
        activeBox = pixelbox
    end
end
setScaleMode("real")

local baseWidth, baseHeight = 51, 19
local vx, vy = 1, 1

---@type SavedMap
local smap
---@type LoadedMap
local wmap
local mapFilename

local selectItem

---@type Polygon|{color:"red"|"blue",pos:Vector}?
local selectedPoly
---@type integer
local selectedIndex = 0
---@type "doors"|"walls"|"spawns"|"floors"?
local selectedType

local function updateWorkingMap()
    wmap = map.loadMap(smap)
    if selectedPoly then
        if selectedType ~= "spawns" then
            selectedPoly = wmap[selectedType][selectedIndex]
        else
            selectedPoly = wmap.spawns[selectedPoly.color][selectedIndex]
        end
    end
end
local textureOptions = { "None" }
local textureLut = {}
local function updateTextureOptions()
    for k, v in pairs(textureLut) do
        textureLut[k] = nil
    end
    for k, v in pairs(textureOptions) do
        textureOptions[k] = nil
    end
    textureOptions[1] = "None"
    for k, v in pairs(wmap.textures) do
        textureLut[k] = k
        textureOptions[#textureOptions + 1] = k
    end
end
local function loadMap(name)
    local s = map.readFile(name)
    smap = textutils.unserialiseJSON(s) --[[@as SavedMap]]
    updateWorkingMap()
    updateTextureOptions()
end
local function saveMap(name)
    mapFilename = name
    local s = textutils.serialiseJSON(smap)
    local f = assert(fs.open(name, "w"))
    f.write(s)
    f.close()
end
loadMap("maps/default.json")

local bar
local running = true
local quitButton = mbar.button("Quit", function(entry)
    running = false
end)
local openButton = mbar.button("Open", function(entry)
    local complete = require("cc.shell.completion")
    local fn = mbar.popupRead("Open", 15, nil, function(str)
        local list = complete.file(shell, str)
        for i = #list, 1, -1 do
            if not (list[i]:match("/$") or list[i]:match("%.json$")) then
                table.remove(list, i)
            end
        end
        return list
    end)
    bar.resetKeys()
    if fn then
        loadMap(fn)
        mapFilename = fn
    end
end)
local saveAsButton = mbar.button("Save As", function(entry)
    local fn = mbar.popupRead("Save As", 15)
    bar.resetKeys()
    if fn then
        saveMap(fn)
        mapFilename = fn
    end
end)
local fileMenu = mbar.buttonMenu { openButton, saveAsButton, quitButton }
local fileButton = mbar.button("File", nil, fileMenu)

local viewWalls = true
local viewDoors = true
local viewFloors = true
local viewWallsButton = mbar.toggleButton("Walls", function(self)
    viewWalls = self.value
end)
viewWallsButton.setValue(viewWalls)
local viewDoorsButton = mbar.toggleButton("Doors", function(self)
    viewDoors = self.value
end)
viewDoorsButton.setValue(viewDoors)
local viewFloorsButton = mbar.toggleButton("Floors", function(self)
    viewFloors = self.value
end)
viewFloorsButton.setValue(viewDoors)

local viewWireframe = false
local viewWireframeButton = mbar.toggleButton("Wireframe", function(self)
    viewWireframe = self.value
end)
local viewTermViewport = false
local termViewboxButton = mbar.toggleButton("Term Viewport", function(self)
    viewTermViewport = self.value
end)
local viewSpawnpoints = false
local viewSpawnpointsButton = mbar.toggleButton("Spawnpoints", function(self)
    viewSpawnpoints = self.value
end)
local modes = {
    "real", "1x", "2x"
}
local viewModeMenu = mbar.radialMenu({ "Game", "1:1", "2x" }, function(self)
    setScaleMode(modes[self.selected])
end)
local viewModeButton = mbar.button("Scale", nil, viewModeMenu)
local viewCenterLines = false
local viewCenterLinesButton = mbar.toggleButton("Center Lines", function(self)
    viewCenterLines = self.value
end)
local objectViewMenu = mbar.buttonMenu {
    viewFloorsButton,
    viewWallsButton,
    viewDoorsButton,
    viewSpawnpointsButton
}
local objectViewButton = mbar.button("Object", nil, objectViewMenu)
local viewMenu = mbar.buttonMenu {
    objectViewButton,
    termViewboxButton,
    viewModeButton,
    viewWireframeButton,
    viewCenterLinesButton
}
local viewButton = mbar.button("View", nil, viewMenu)

local insertWallButton = mbar.button("Wall", function(entry)
    local tw, th = win.getSize()
    local idx = #smap.walls + 1
    smap.walls[idx] = {
        shape = "rect",
        width = 10,
        height = 10,
        color = "white",
        position = {
            vx + math.floor(tw / 2) * graphics.mulx,
            vy + math.floor(th / 2) * graphics.muly
        },
    }
    updateWorkingMap()
    selectItem(wmap.walls[idx], "walls", idx)
end)
local insertDoorButton = mbar.button("Door", function(entry)
    local tw, th = win.getSize()
    smap.doors = smap.doors or {}
    local idx = #smap.doors + 1
    smap.doors[idx] = {
        shape = "rect",
        width = 10,
        height = 10,
        color = "white",
        position = {
            vx + math.floor(tw / 2) * graphics.mulx,
            vy + math.floor(th / 2) * graphics.muly
        },
        team = "red"
    }
    updateWorkingMap()
    selectItem(wmap.doors[idx], "doors", idx)
end)
local insertFloorButton = mbar.button("Floor", function(entry)
    local tw, th = win.getSize()
    smap.floors = smap.floors or {}
    local idx = #smap.floors + 1
    smap.floors[idx] = {
        shape = "rect",
        width = 10,
        height = 10,
        color = "white",
        position = {
            vx + math.floor(tw / 2) * graphics.mulx,
            vy + math.floor(th / 2) * graphics.muly
        },
    }
    updateWorkingMap()
    selectItem(wmap.floors[idx], "floors", idx)
end)
local insertRedSpawnButton = mbar.button("Red", function(entry)
    local tw, th = win.getSize()
    local idx = #smap.spawns.red + 1
    local x, y = vx + math.floor(tw / 2) * graphics.mulx, vy + math.floor(th / 2) * graphics.muly
    smap.spawns.red[idx] = {
        x, y
    }
    updateWorkingMap()
    selectItem({ pos = vector.new(x, y, 0), color = "red" }, "spawns", idx)
end)
local insertBlueSpawnButton = mbar.button("Blue", function(entry)
    local tw, th = win.getSize()
    local idx = #smap.spawns.blue + 1
    local x, y = vx + math.floor(tw / 2) * graphics.mulx, vy + math.floor(th / 2) * graphics.muly
    smap.spawns.blue[idx] = {
        x, y
    }
    updateWorkingMap()
    selectItem({ pos = vector.new(x, y, 0), color = "blue" }, "spawns", idx)
end)
local insertSpawnMenu = mbar.buttonMenu { insertRedSpawnButton, insertBlueSpawnButton }
local insertSpawnButton = mbar.button("Spawn", nil, insertSpawnMenu)

local insertMenu = mbar.buttonMenu { insertFloorButton, insertWallButton, insertDoorButton, insertSpawnButton }
local insertButton = mbar.button("Insert", nil, insertMenu)

local selectWalls, selectDoors, selectFloors = true, true, true
local selectWallsButton = mbar.toggleButton("Walls", function(self)
    selectWalls = self.value
end)
selectWallsButton.setValue(selectWalls)
local selectDoorsButton = mbar.toggleButton("Doors", function(self)
    selectDoors = self.value
end)
selectDoorsButton.setValue(selectWalls)
local selectFloorsButton = mbar.toggleButton("Floors", function(self)
    selectFloors = self.value
end)
selectFloorsButton.setValue(selectWalls)
local selectableMenu = mbar.buttonMenu {
    selectFloorsButton,
    selectWallsButton,
    selectDoorsButton
}
local selectableButton = mbar.button("Selectable", nil, selectableMenu)


local blankScheme = {
    sidebar.label("Nothing Selected")
}
local function nop() end

local deleteButton = mbar.button("Delete", function(entry)
    if not selectedPoly then return end
    if selectedType == "spawns" then
        if #smap.spawns[selectedPoly.color] > 1 then
            table.remove(smap.spawns[selectedPoly.color], selectedIndex)
            updateWorkingMap()
            selectedPoly, selectedIndex, selectedType = nil, -1, nil
            sbar.update(blankScheme, {}, nop)
        end
    else
        table.remove(smap[selectedType], selectedIndex)
        selectedPoly, selectedIndex, selectedType = nil, -1, nil
        updateWorkingMap()
        sbar.update(blankScheme, {}, nop)
    end
end)

local editMenu = mbar.buttonMenu { selectableButton, deleteButton }
local editButton = mbar.button("Edit", nil, editMenu)

local dumpPaletteButton = mbar.button("Dump Palette", function(entry)
    palette.dump(win)
end)
local debugMenu = mbar.buttonMenu({ dumpPaletteButton })
local debugButton = mbar.button("Debug", nil, debugMenu)

bar = mbar.bar { fileButton, editButton, insertButton, viewButton, debugButton }
bar.shortcut(quitButton, keys.q, true)
bar.shortcut(deleteButton, keys.delete)

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
---@return number cx
---@return number cy
local function getGizmoCorners(poly)
    local px, py = poly.pos.x, poly.pos.y
    local x1, y1 = graphics.worldToScreenPos(px + poly.bounds[1] - 1, py + poly.bounds[2] - 1)
    local x2, y2 = graphics.worldToScreenPos(px + poly.bounds[3], py + poly.bounds[4])

    local ow, oh = x2 - x1, y2 - y1

    local x1r, y1r = divscale(x1, y1)
    local x2r, y2r = divscale(x2, y2)
    x2r, y2r = x2r + 1, y2r + 1
    local cx, cy = graphics.worldToScreenPos(px, py)

    return math.floor(x1r), math.floor(y1r), math.ceil(x2r), math.ceil(y2r), divscale(cx, cy)
end
local horizStr
do
    local w, h = win.getSize()
    horizStr = ("-"):rep(w)
end
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param cx number
---@param cy number
local function drawCenterLines(x1, y1, x2, y2, cx, cy)
    local ofg, obg = col(colors.white, colors.black)
    local w, h = win.getSize()
    scp(-w + x1, cy)
    win.write(horizStr)
    scp(x2 + 1, cy)
    win.write(horizStr)
    for dy = 1, h do
        scp(cx, -h + y1 + dy - 1)
        win.write("|")
        scp(cx, y2 + dy)
        win.write("|")
    end
    scp(cx, y1)
    win.write("\25")
    scp(cx, y2)
    win.write("\24")
    scp(x1, cy)
    win.write("\26")
    scp(x2, cy)
    win.write("\27")
    col(ofg, obg)
end

---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@param cx number
---@param cy number
local function drawGizmoBox(x1, y1, x2, y2, cx, cy)
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
    local x1, y1, x2, y2, cx, cy = getGizmoCorners(poly)
    drawGizmoBox(x1, y1, x2, y2, cx, cy)
    if viewCenterLines then
        drawCenterLines(x1, y1, x2, y2, cx, cy)
    end
end

---@param x integer
---@param y integer
---@return Polygon?
---@return "doors"|"walls"|"floors"
---@return integer
local function getClickedOnPolygon(x, y)
    local vec = vector.new(x, y, 0)
    if viewWalls and selectWalls then
        for k, v in ipairs(wmap.walls) do
            if shapes.pointInPolygon(v, vec) then
                return v, "walls", k
            end
        end
    end
    if viewDoors and selectDoors then
        for k, v in ipairs(wmap.doors) do
            if shapes.pointInPolygon(v, vec) then
                return v, "doors", k
            end
        end
    end
    if viewFloors and selectFloors then
        for k, v in ipairs(wmap.floors) do
            if shapes.pointInPolygon(v, vec) then
                return v, "floors", k
            end
        end
    end
    return nil, "doors", -1
end

---@param x integer
---@param y integer
---@return {pos:Vector, color:"red"|"blue"}?
---@return "spawns"
---@return integer
local function getClickedOnSpawnpoint(x, y)
    if viewSpawnpoints then
        for k, v in ipairs(wmap.spawns.red) do
            local sx, sy = divscale(graphics.worldToScreenPos(v[1], v[2]))
            if x == math.floor(sx) and y == math.floor(sy) then
                return { pos = vector.new(x, y, 0), color = "red" }, "spawns", k
            end
        end
        for k, v in ipairs(wmap.spawns.blue) do
            local sx, sy = divscale(graphics.worldToScreenPos(v[1], v[2]))
            if x == math.floor(sx) and y == math.floor(sy) then
                return { pos = vector.new(x, y, 0), color = "blue" }, "spawns", k
            end
        end
    end
    return nil, "spawns", -1
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
    vpw, vph = vpw * 2 / graphics.mulx, vph * 3 / graphics.muly
    local cx, cy = math.floor((tw - vpw) / 2), math.floor((th - vph) / 2)
    local x1, y1 = graphics.screenToWorldPos(mulscale(cx, cy))
    local x2, y2 = graphics.screenToWorldPos(mulscale(cx + vpw + 1, cy + vph + 1))
    graphics.drawRectangle(x1, y1, x2, y2, colors.white)
end

local updated = true
local function render()
    win.setVisible(false)
    win.clear()
    activeBox:clear(colors.black)
    if viewFloors then
        for _, v in pairs(wmap.floors) do
            shapes.drawPolygon(v, viewWireframe, true)
        end
    end
    if viewDoors then
        for _, v in pairs(wmap.doors) do
            shapes.drawPolygon(v, viewWireframe)
        end
    end
    if viewWalls then
        for _, v in pairs(wmap.walls) do
            shapes.drawPolygon(v, viewWireframe)
        end
    end
    renderTermViewport()
    activeBox:render()
    renderSpawnpoints()
    if selectedPoly and selectedType == "spawns" then
        local spawn = smap.spawns[selectedPoly.color][selectedIndex]
        local x, y = divscale(graphics.worldToScreenPos(spawn[1], spawn[2]))
        drawGizmoBox(x - 1, y - 1, x + 1, y + 1, x, y)
    elseif selectedPoly then
        drawGizmoBoxp(selectedPoly)
        scp(divscale(graphics.worldToScreenPos(selectedPoly.pos.x, selectedPoly.pos.y)))
        col(colors.white, colors.black)
        win.write("+")
    end
    sbar.render()
    bar.render()
    local tw, th = win.getSize()
    col(colors.white, colors.black)
    win.setCursorPos(1, th)
    win.write(("%d, %d"):format(vx, vy))
    win.setVisible(true)
    updated = false
end

local function renderLoop()
    while true do
        sbar.showCursor(win)
        sleep()
        if updated then
            render()
        end
    end
end

local shapeOptions = { "rect", "ctr_rect", "circle" }
updateTextureOptions()

local colorOptions = {}
for k, v in pairs(palette.colors) do
    colorOptions[#colorOptions + 1] = k
end

local function textureCallback(t, v)
    if v == "None" then
        t.texture = nil
        t.color = "white"
    else
        t.texture = v
        t.color = nil
    end
end

local wallRectScheme = {
    sidebar.label("Wall"),
    sidebar.numberInput("Pos X", nil, "position", 1),
    sidebar.numberInput("Pos Y", nil, "position", 2),
    sidebar.numberInput("Angle", nil, "angle"),
    sidebar.dropdown("Shape", shapeOptions, nil, "shape"),
    sidebar.dropdown("Color", colorOptions, nil, "color"),
    sidebar.dropdown("Texture", textureOptions, textureCallback, "texture"),
    sidebar.numberInput("Width", { min = 2 }, "width"),
    sidebar.numberInput("Height", { min = 2 }, "height"),
}

local wallCircleScheme = {
    sidebar.label("Wall"),
    sidebar.numberInput("Pos X", nil, "position", 1),
    sidebar.numberInput("Pos Y", nil, "position", 2),
    sidebar.numberInput("Angle", nil, "angle"),
    sidebar.dropdown("Shape", shapeOptions, nil, "shape"),
    sidebar.dropdown("Color", colorOptions, nil, "color"),
    sidebar.dropdown("Texture", textureOptions, textureCallback, "texture"),
    sidebar.numberInput("Radius", { min = 2 }, "radius"),
    sidebar.numberInput("Quality", { min = 3, max = 50 }, "quality"),
}
local floorRectScheme = {
    sidebar.label("Floor"),
    sidebar.numberInput("Pos X", nil, "position", 1),
    sidebar.numberInput("Pos Y", nil, "position", 2),
    sidebar.numberInput("Angle", nil, "angle"),
    sidebar.dropdown("Shape", shapeOptions, nil, "shape"),
    sidebar.dropdown("Color", colorOptions, nil, "color"),
    sidebar.dropdown("Texture", textureOptions, textureCallback, "texture"),
    sidebar.numberInput("Width", { min = 2 }, "width"),
    sidebar.numberInput("Height", { min = 2 }, "height"),
}

local floorCircleScheme = {
    sidebar.label("Floor"),
    sidebar.numberInput("Pos X", nil, "position", 1),
    sidebar.numberInput("Pos Y", nil, "position", 2),
    sidebar.numberInput("Angle", nil, "angle"),
    sidebar.dropdown("Shape", shapeOptions, nil, "shape"),
    sidebar.dropdown("Color", colorOptions, nil, "color"),
    sidebar.dropdown("Texture", textureOptions, textureCallback, "texture"),
    sidebar.numberInput("Radius", { min = 2 }, "radius"),
    sidebar.numberInput("Quality", { min = 3, max = 50 }, "quality"),
}


local doorRectScheme = {
    sidebar.label("Door"),
    sidebar.numberInput("Pos X", nil, "position", 1),
    sidebar.numberInput("Pos Y", nil, "position", 2),
    sidebar.numberInput("Angle", nil, "angle"),
    sidebar.dropdown("Shape", shapeOptions, nil, "shape"),
    sidebar.dropdown("Color", colorOptions, nil, "color"),
    sidebar.dropdown("Texture", textureOptions, textureCallback, "texture"),
    sidebar.dropdown("Team", { "red", "blue" }, nil, "team"),
    sidebar.numberInput("Width", { min = 2 }, "width"),
    sidebar.numberInput("Height", { min = 2 }, "height")
}

local doorCircleScheme = {
    sidebar.label("Door"),
    sidebar.numberInput("Pos X", nil, "position", 1),
    sidebar.numberInput("Pos Y", nil, "position", 2),
    sidebar.numberInput("Angle", nil, "angle"),
    sidebar.dropdown("Shape", shapeOptions, nil, "shape"),
    sidebar.dropdown("Color", colorOptions, nil, "color"),
    sidebar.dropdown("Texture", textureOptions, textureCallback, "texture"),
    sidebar.dropdown("Team", { "red", "blue" }, nil, "team"),
    sidebar.numberInput("Radius", { min = 2 }, "radius"),
    sidebar.numberInput("Quality", { min = 3, max = 50 }, "quality")
}

local spawnScheme = {
    sidebar.numberInput("X Pos", nil, 1),
    sidebar.numberInput("Y Pos", nil, 2)
}

local schemes = {
    walls = {
        rect = wallRectScheme,
        ctr_rect = wallRectScheme,
        circle = wallCircleScheme
    },
    doors = {
        rect = doorRectScheme,
        ctr_rect = doorRectScheme,
        circle = doorCircleScheme
    },
    floors = {
        rect = floorRectScheme,
        ctr_rect = floorRectScheme,
        circle = floorCircleScheme
    },
    spawns = spawnScheme
}
sbar.update(blankScheme, {}, nop)

local function polygonUpdate(data)
    if not selectedType then return end
    if data.shape == "rect" or data.shape == "ctr_rect" then
        data.radius = nil
        data.quality = nil
        data.width = data.width or 10
        data.height = data.height or 10
    elseif data.shape == "circle" then
        data.width = nil
        data.height = nil
        data.radius = data.radius or 10
        data.quality = data.quality or 8
    end
    if data.angle then
        data.angle = data.angle % 360
        if data.angle == 0 then
            data.angle = nil
        end
    end
    local scheme = schemes[selectedType][data.shape]
    sbar.update(scheme, data, polygonUpdate)
    updateWorkingMap()
end

local function spawnpointUpdate(data)
    if not selectedPoly then return end
    updateWorkingMap()
end

function selectItem(poly, type, index)
    selectedPoly, selectedType, selectedIndex = poly, type, index
    if selectedType == "spawns" then
        local scheme = schemes.spawns
        local spawn = smap.spawns[poly.color][selectedIndex]
        ovx, ovy = spawn[1], spawn[2]
        spawn.color = selectedPoly.color
        sbar.update(scheme, spawn, spawnpointUpdate)
    else
        local spoly = smap[selectedType][selectedIndex]
        local scheme = schemes[selectedType][spoly.shape]
        sbar.update(scheme, spoly, polygonUpdate)
    end
end

---@type "none"|"camera"|"object"|"object_inital"
local selectionMode = "none"
local wasMouseDragged = false
local eventHandlers = {
    mouse_click = function(button, x, y)
        clickx, clicky = x, y
        local npoly, npolyType, nPolyIndex =
            getClickedOnPolygon(graphics.screenToWorldPos(mulscale(x, y)))
        if not npoly then
            ---@diagnostic disable-next-line: cast-local-type
            npoly, npolyType, nPolyIndex = getClickedOnSpawnpoint(x, y)
        end
        if npoly then
            ovx, ovy = npoly.pos.x, npoly.pos.y
            updated = true
            selectionMode = "object_inital"
            selectItem(npoly, npolyType, nPolyIndex)
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
            if selectedType ~= "spawns" then
                local rpoly = smap[selectedType][selectedIndex]
                rpoly.position[1] = nx
                rpoly.position[2] = ny
            else
                selectedPoly[1], selectedPoly[2] = nx, ny
            end
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
                sbar.update(blankScheme, {}, nop)
            end
        elseif selectionMode == "object_inital" then
            selectionMode = "object"
        end
        wasMouseDragged = false
    end,
    term_resize = function()
        local w, h = term.getSize()
        win.reposition(1, 1, w, h)
        pixelbox:resize(w, h)
        bixelbox:resize(w, h)
        fakebox:resize(w, h)
        graphics.refreshSize()
        updated = true
    end
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

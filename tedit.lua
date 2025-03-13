-- Texture editor
local map        = require("libs.map")
local mbar       = require("libs.mbar")
local graphics   = require("libs.graphics")
local shapes     = require("libs.shapes")
local palette    = require("libs.palette")
local trig       = require("libs.trig")

local win        = window.create(term.current(), 1, 1, term.getSize())
local previewWin = window.create(win, 1, 1, term.getSize())
palette.apply(win)
mbar.setWindow(win)
local pixelbox = require("libs.pixelbox").new(previewWin)

local previewW, previewX
local cameraX, cameraY
local editorW, editorH

local doRender = true

---@type color[][] [y][x] -> color
local texture = { {} }
local textureW = 1
local textureH = 1
local texDirty = true
local textureFilename
local polyMatchTextureSize = false

local frame = 0

---@param texString string
local function loadTexture(texString)
    local tex = shapes.parseTexture(texString)
    texture = tex.data
    textureH = tex.h
    textureW = tex.w
    texDirty = true
end

local function serializeTexture()
    local tex = {}
    for y = 1, textureH do
        tex[y] = ""
        for x = 1, textureW do
            tex[y] = tex[y] .. colors.toBlit(((texture[y] or {})[x]) or 1)
        end
    end
    return textutils.serialize(tex, { compact = true })
end
local function saveTextureFile(fn)
    local f = assert(fs.open(fn, "w"))
    f.write(serializeTexture())
    f.close()
end

local function loadTextureFile(fn)
    local s = map.readFile(fn)
    loadTexture(s)
end
-- loadTexture('{"0123", "4567", "89ab", "cdef"}')
loadTextureFile("bliss.tex")

local viewDouble = false
local horizShift = false
local vertShift = false
local running = true
local quitButton = mbar.button("Quit", function(entry)
    running = false
end)

local openButton = mbar.button("Open", function(entry)
    local complete = require("cc.shell.completion")
    doRender = false
    local fn = mbar.popupRead("Open", 15, nil, function(str)
        local list = complete.file(shell, str)
        for i = #list, 1, -1 do
            if not (list[i]:match("/$") or list[i]:match("%.tex$")) then
                table.remove(list, i)
            end
        end
        return list
    end)

    if fn then
        loadTextureFile(fn)
        textureFilename = fn
    end
    doRender = true
end)

local saveAsButton = mbar.button("Save As", function(entry)
    local complete = require("cc.shell.completion")
    doRender = false
    local fn = mbar.popupRead("Open", 15, nil, function(str)
        local list = complete.file(shell, str)
        for i = #list, 1, -1 do
            if not (list[i]:match("/$") or list[i]:match("%.tex$")) then
                table.remove(list, i)
            end
        end
        return list
    end)

    if fn then
        saveTextureFile(fn)
        textureFilename = fn
    end
    doRender = true
end)

local saveButton = mbar.button("Save", function(entry)
    if textureFilename then
        saveTextureFile(textureFilename)
    else
        saveAsButton.click()
    end
end)

local function updateTextureSize()
    local ntexture = {}
    for y = 1, textureH do
        ntexture[y] = {}
        for x = 1, textureW do
            ntexture[y][x] = (texture[y] or {})[x] or 1
        end
    end
    texture = ntexture
end

local newButton = mbar.button("New", function(entry)
    doRender = false
    local w = tonumber(mbar.popupRead("Width", 15, nil, nil, tostring(textureW)))
    if not w then
        doRender = true
        return
    end
    local h = tonumber(mbar.popupRead("Height", 15, nil, nil, tostring(textureW)))
    if not h then
        doRender = true
        return
    end
    texture = {}
    textureW = w
    textureH = h
    updateTextureSize()
    doRender = true
    texDirty = true
end)

local fileMenu = mbar.buttonMenu { newButton, openButton, saveAsButton, saveButton, quitButton }
local fileButton = mbar.button("File", nil, fileMenu)

local selectedColor = colors.white
local colorMenu = mbar.colorMenu(function(self)
    selectedColor = self.selectedCol
end)
colorMenu.setSelected(selectedColor)
local colorButton = mbar.button("Color", nil, colorMenu)

local resizeWidthButton = mbar.button("Width", function(entry)
    doRender = false
    local v = mbar.popupRead("Width", 15, nil, nil, tostring(textureW))
    if tonumber(v) then
        textureW = tonumber(v)
        texDirty = true
        updateTextureSize()
    end
    doRender = true
end)
local resizeHeightButton = mbar.button("Height", function(entry)
    doRender = false
    local v = mbar.popupRead("Height", 15, nil, nil, tostring(textureH))
    if tonumber(v) then
        textureH = tonumber(v)
        texDirty = true
        updateTextureSize()
    end
    doRender = true
end)

local resizeMenu = mbar.buttonMenu { resizeWidthButton, resizeHeightButton }
local resizeButton = mbar.button("Resize", nil, resizeMenu)

local editMenu = mbar.buttonMenu { colorButton, resizeButton }
local editButton = mbar.button("Edit", nil, editMenu)

local doubleToggle = mbar.toggleButton("Double", function(self)
    viewDouble = self.value
end)
local vertShiftToggle = mbar.toggleButton("Vert. Shift", function(self)
    vertShift = self.value
end)
local horizShiftToggle = mbar.toggleButton("Hori. Shift", function(self)
    horizShift = self.value
end)
local backgroundColor = colors.black
local backgroundColorMenu = mbar.colorMenu(function(self)
    backgroundColor = self.selectedCol
end)
backgroundColorMenu.setSelected(backgroundColor)
local backgroundColorButton = mbar.button("BG Color", nil, backgroundColorMenu)
local matchSizeButton = mbar.toggleButton("Match Tex. Size", function(self)
    polyMatchTextureSize = self.value
end)

local viewMenu = mbar.buttonMenu { doubleToggle, matchSizeButton, vertShiftToggle, horizShiftToggle, backgroundColorButton }
local viewButton = mbar.button("View", nil, viewMenu)

local bar = mbar.bar { fileButton, editButton, viewButton }
bar.shortcut(quitButton, keys.q, true)
bar.shortcut(saveButton, keys.s, true)

local function termResize()
    local w, h = term.getSize()
    win.reposition(1, 1, w, h)
    previewW = math.floor(w / 2)
    previewX = w - previewW
    cameraX = 0
    cameraY = 0
    editorW = previewX - 1
    editorH = h
    previewWin.reposition(previewX, 1, previewW, h)
    pixelbox:resize(previewW, h)
    graphics.refreshSize(previewW, h)
    graphics.setViewCenter(cameraX, cameraY)
end
termResize()

graphics.mulx, graphics.muly = 2, 3
graphics.setBox(pixelbox)


local shiftSpeed = 9
local function renderTexture()
    local sx = math.floor((editorW - textureW) / 2)
    local sy = math.floor((editorH - textureH) / 2)
    for py = 1, textureH do
        texture[py] = texture[py] or {}
        for px = 1, textureW do
            local col = colors.toBlit(texture[py][px] or 1)
            win.setCursorPos(sx + px - 1, sy + py - 1)
            win.blit(" ", col, col)
        end
    end

    local w, h = 30, 30
    if polyMatchTextureSize then
        w, h = textureW, textureH
        if viewDouble then
            w, h = w * 2, h * 2
        end
    end
    local poly = shapes.polygon(vector.new(0, 0, 0), shapes.getRectangleCorners(w, h))
    poly.texture = { data = texture, w = textureW, h = textureH }
    local theta = frame * shiftSpeed
    local cx, cy = 0, 0
    if vertShift then
        cy = trig.sin(theta) * 5
    end
    if horizShift then
        cx = trig.cos(theta) * 5
    end

    graphics.setViewCenter(trig.round(cx), trig.round(cy))
    shapes.drawPolygon(poly, false, viewDouble)
end
renderTexture()

local function render()
    win.setVisible(false)
    win.setBackgroundColor(backgroundColor)
    win.clear()
    pixelbox:clear(backgroundColor)
    renderTexture()
    pixelbox:render()
    bar.render()
    win.setVisible(true)
end

local function screenToTextureCoords(cx, cy)
    local sx = math.floor((editorW - textureW) / 2)
    local sy = math.floor((editorH - textureH) / 2)
    local tx = cx - sx + 1
    local ty = cy - sy + 1
    if tx < 1 or tx > textureW or ty < 1 or ty > textureH then
        return
    end
    return tx, ty
end

local function tryDraw(cx, cy)
    local ix, iy = screenToTextureCoords(cx, cy)
    if ix then
        texture[iy][ix] = selectedColor
        texDirty = true
    end
end

local function eventLoop()
    while running do
        local e = table.pack(os.pullEvent())
        if not bar.onEvent(e) then
            if e[1] == "mouse_click" then
                tryDraw(e[3], e[4])
            elseif e[1] == "mouse_drag" then
                tryDraw(e[3], e[4])
            end
        end
    end
end

local function renderLoop()
    while running do
        frame = frame + 1
        if doRender then
            render()
        end
        sleep(0.05)
    end
end

parallel.waitForAny(eventLoop, renderLoop)

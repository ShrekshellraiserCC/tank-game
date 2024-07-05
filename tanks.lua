local pixelbox = require "libs.pixelbox"
local shapes   = require "libs.shapes"
local graphics = require "libs.graphics"
local trig     = require "libs.trig"
local palette  = require "libs.palette"
local map      = require "libs.map"
local gamedata = require "libs.gamedata"
local profile  = require "libs.gameprofiling"

local win      = window.create(term.current(), 1, 1, term.getSize())
local box      = pixelbox.new(win)
graphics.setBox(box)


palette.apply(win)


local mainPlayer = gamedata.newPlayer(os.computerID(), "red")


---@class Bullet
---@field pos Vector
---@field vel Vector
---@field remainingBounces integer
---@field health integer
---@field ticksToLive integer

local tw, th = term.getSize()



--- STATISTIC VARIABLES


---- GAME LOGIC


---@param player Player
local function renderPlayer(player)
    shapes.drawPolygon(player.poly)
    graphics.drawAngledLine(player.pos.x, player.pos.y, player.turretLength, player.turretAngle, player.turretColor)
    shapes.drawPolygon(player.turretPoly)
end

---@param player Player
local function renderHud(player)
    win.setCursorPos(1, th)
    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.white)
    win.clearLine()
    local weapon = player.weapon
    local bulletStatus = ("*"):rep(weapon.shotsRemaining) .. ("_"):rep(weapon.shotCapacity - weapon.shotsRemaining)
    win.write(("[%s]"):format(bulletStatus))
end

local flag = false
local function render()
    local render0 = os.epoch(profile.timeunit)
    win.setVisible(false)
    box:clear(colors.black)
    map.renderMap(gamedata.map)
    for _, v in pairs(gamedata.players) do
        renderPlayer(v)
    end
    for _, v in pairs(gamedata.bullets) do
        local bulletPoly = shapes.polygon(v.pos, shapes.getRectanglePointsCorner(2, 2), colors.white)
        shapes.drawPolygon(bulletPoly)
    end
    box:render()
    renderHud(mainPlayer)
    profile.renderdt = os.epoch(profile.timeunit) - render0
end

local tw, th = term.getSize()
local mx, my = tw, th / 2 * 3

--- VIEW POS CODE
local aiming = false
local aimpos = vector.new(0, 0, 0)
local view = vector.new(mx, my, 0)
local targetView = vector.new(mx, my, 0)
local viewVelocity = 5
local function updateViewpos()
    if aiming then
        targetView = mainPlayer.pos + (aimpos - vector.new(tw, th / 2 * 3, 0)) * 0.40
    else
        targetView.x = mainPlayer.pos.x
        targetView.y = mainPlayer.pos.y
    end
    ---@type Vector
    local dview = targetView - view
    if dview:length() > viewVelocity then
        dview = dview:normalize() * viewVelocity
    end
    view = view + dview
    graphics.setViewCenter(view.x, view.y)
end

local enableOverlay = false
mainPlayer.pos.x, mainPlayer.pos.y = mx, my
local function gameLoop()
    while true do
        sleep(0) -- main tick loop
        local t0 = os.epoch(profile.timeunit)
        profile.collisionChecks, profile.edgeChecks = 0, 0
        profile.collisiondt, profile.renderdt = 0, 0
        -- updatePlayer(mainPlayer)
        for _, player in pairs(gamedata.players) do
            gamedata.tickPlayer(player)
        end
        for i in pairs(gamedata.bullets) do
            gamedata.tickBullet(i)
        end
        updateViewpos()
        render()
        profile.framedt = os.epoch(profile.timeunit) - t0
        profile.frameCount = profile.frameCount + 1
        profile.totalRenderDt = profile.totalRenderDt + profile.renderdt
        profile.totalCollisionDt = profile.totalCollisionDt + profile.collisiondt
        profile.totaldt = profile.totaldt + profile.framedt
        if enableOverlay then
            profile.display(win)
        end
        win.setVisible(true)
    end
end

local heldKeys = {}
local directionVectors = {
    w = vector.new(0, -1, 0),
    d = vector.new(1, 0, 0),
    s = vector.new(0, 1, 0),
    a = vector.new(-1, 0, 0)
}

local function updateKeys()
    term.setCursorPos(1, 1)
    mainPlayer.boosting = heldKeys[keys.leftShift]
    local heldDirection = vector.new(0, 0, 0)
    for k, v in pairs(directionVectors) do
        if heldKeys[keys[k]] then
            heldDirection = heldDirection + v
        end
    end
    if heldDirection:length() > 0 then
        local angle = trig.atan(heldDirection.y / heldDirection.x) + 90
        if heldDirection.x < 0 then
            angle = angle + 180
        end
        mainPlayer.targetAngle = angle
        mainPlayer.targetVelocity = -(mainPlayer.boosting and mainPlayer.boostStats.maxVelocity or mainPlayer.baseStats.maxVelocity)
    else
        mainPlayer.targetVelocity = 0
        mainPlayer.targetAngle = mainPlayer.angle
    end
end


local function inputLoop()
    while true do
        local e, key, x, y = os.pullEvent()
        if e == "key" then
            if key == keys.t then
                enableOverlay = not enableOverlay
            elseif key == keys.right then
                flag = not flag
            end
            heldKeys[key] = true
            updateKeys()
        elseif e == "key_up" then
            heldKeys[key] = nil
            updateKeys()
        elseif e == "mouse_click" or e == "mouse_drag" then
            local tankposx, tankposy = graphics.worldToScreenPos(mainPlayer.pos.x, mainPlayer.pos.y)
            local angle = graphics.calculateAngle(tankposx, tankposy, x * 2, y * 3)
            mainPlayer.turretAngle = angle
            if key == 2 then
                -- right click to aim
                aiming = true
                aimpos = vector.new(x * 2, y * 3, 0)
            elseif key == 1 then
                gamedata.fire(mainPlayer)
                aimpos = vector.new(x * 2, y * 3, 0)
            end
        elseif e == "mouse_up" then
            if key == 2 then
                aiming = false
            end
        end
    end
end

parallel.waitForAny(inputLoop, gameLoop)

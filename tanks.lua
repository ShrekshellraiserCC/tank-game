local pixelbox = require "libs.pixelbox"
local shapes   = require "libs.shapes"
local graphics = require "libs.graphics"
local trig     = require "trig"
local palette  = require "libs.palette"
local map      = require "libs.map"
local gamedata = require "libs.gamedata"

local win      = window.create(term.current(), 1, 1, term.getSize())
local box      = pixelbox.new(win)
graphics.setBox(box)

local friction = 0.99

palette.apply(win)


local mainPlayer = gamedata.newPlayer("red")

---@type table<integer,Player>
local players = {}

players[1] = mainPlayer
mainPlayer.id = 1

players[2] = gamedata.newPlayer("blue")
players[2].id = 2

---@class Bullet
---@field pos Vector
---@field vel Vector
---@field remainingBounces integer
---@field health integer
---@field ticksToLive integer

local tw, th = term.getSize()
---@type Bullet[]
local bullets = {}

local function newBullet(pos, velocity)
    ---@class Bullet
    bullets[#bullets + 1] = {
        pos = pos,
        vel = velocity,
        remainingBounces = 5,
        health = 1,
        ticksToLive = 20 * 20,
    }
    return bullets[#bullets]
end


--- STATISTIC VARIABLES

local collisionChecks = 0
local edgeChecks = 0
local collisiondt = 0
local framedt = 0
local totaldt = 0
local renderdt = 0
local frameCount = 0
local totalRenderDt = 0
local totalCollisionDt = 0
local timeunit = "utc"
local timelabel = "ms"

local enableOverlay = true
local function handleStats()
    frameCount = frameCount + 1
    totalRenderDt = totalRenderDt + renderdt
    totalCollisionDt = totalCollisionDt + collisiondt
    totaldt = totaldt + framedt
    if enableOverlay then
        win.setCursorPos(1, 1)
        win.write(("Frame %d"):format(frameCount))
        win.setCursorPos(1, 2)
        win.write(("collisionChecks %d"):format(collisionChecks))
        win.setCursorPos(1, 3)
        win.write(("edgeChecks %d"):format(edgeChecks))
        win.setCursorPos(1, 4)
        win.write(("render dt %d%s (ave %.2f%s)"):format(renderdt, timelabel, totalRenderDt / frameCount, timelabel))
        win.setCursorPos(1, 5)
        win.write(("collision dt %d%s (ave %.2f%s)"):format(collisiondt, timelabel, totalCollisionDt / frameCount,
            timelabel))
        win.setCursorPos(1, 6)
        win.write(("frame dt %d%s | %.2fFPS (ave %.2f%s | %.2fFPS)"):format(framedt, timelabel, 1 / (framedt / 1000),
            totaldt / frameCount, timelabel, 1 / (totaldt / 1000 / frameCount)))
    end
end

---- GAME LOGIC
---@type LoadedMap
local gameMap = map.loadMapFile("maps/default.json")

---@param i integer
local function tickBullet(i)
    local bullet = bullets[i]
    bullet.vel = bullet.vel * friction
    local translation = bullet.vel

    local bulletPoly = shapes.polygon(bullet.pos, shapes.getRectanglePointsCorner(2, 2), colors.white)

    local collision0 = os.epoch(timeunit)

    local function collide(poly)
        if shapes.polyOverlap(bulletPoly, poly, 20) then
            local r = shapes.polygonCollision(bulletPoly, poly, translation)
            if r.willIntersect then
                if bullet.remainingBounces == 0 then
                    bullets[i] = nil
                    return
                end
                -- bullet.vel.x = -bullet.vel.x
                -- bullet.vel.y = -bullet.vel.y
                translation = translation + r.minimumTranslationVector * 1.2
                local normal = r.collisionNormal:normalize()
                -- normal.y = -normal.y
                -- error(normal)
                -- bullet.vel.x = bullet.vel.x * normal.x
                -- bullet.vel.y = bullet.vel.y * normal.y
                bullet.vel = bullet.vel - normal * bullet.vel:dot(normal) * 2
                -- bullet.vel = normal * bullet.vel:length()
                if bullet.vel:length() < 1 then
                    bullets[i] = nil
                    return
                end
                bullet.remainingBounces = bullet.remainingBounces - 1
            end
        end
    end

    for _, v in ipairs(gameMap.walls) do
        collide(v)
    end
    for _, v in ipairs(gameMap.doors) do
        collide(v)
    end
    collisiondt = collisiondt + os.epoch(timeunit) - collision0
    bullet.pos.x = bullet.pos.x + translation.x
    bullet.pos.y = bullet.pos.y + translation.y

    bullet.ticksToLive = bullet.ticksToLive - 1
    if bullet.ticksToLive == 0 then
        bullets[i] = nil
    end
end

---@param player Player
local function tickPlayer(player)
    -- update player angle
    local angleDifference = (player.targetAngle - player.angle)
    angleDifference = (angleDifference + 180) % 360 - 180
    local maxAngleVelocity = player.boosting and player.boostStats.maxAngleVelocity or player.baseStats.maxAngleVelocity
    local angleVelocity = math.min(math.abs(angleDifference), maxAngleVelocity)
    local sign = angleDifference > 0 and 1 or -1
    player.angle = player.angle + angleVelocity * sign
    -- update player velocity
    local velDifference = player.targetVelocity - player.velocity
    local acceleration = math.min(math.abs(velDifference), player.maxAcceleration)
    sign = velDifference > 0 and 1 or -1
    player.velocity = (player.velocity + velDifference * acceleration) * friction
    if math.abs(player.velocity) < 0.02 then
        player.velocity = 0
    end
    -- update player position
    local translation = vector.new(0, 0, 0)
    translation.x = player.velocity * math.cos(math.rad(player.angle + 90))
    translation.y = player.velocity * math.sin(math.rad(player.angle + 90))

    local playerPoly = player.poly
    playerPoly.pos = player.pos
    playerPoly.angle = player.angle
    player.turretPoly.pos = player.pos
    player.turretPoly.angle = player.turretAngle
    shapes.calculatePolygonTriangles(playerPoly)
    shapes.calculatePolygonTriangles(player.turretPoly)

    local collision0 = os.epoch(timeunit)
    for _, v in pairs(gameMap.walls) do
        if shapes.polyOverlap(playerPoly, v, 20) then
            local r = shapes.polygonCollision(playerPoly, v, translation)
            if r.willIntersect then
                translation = translation + r.minimumTranslationVector
            end
        end
    end
    for _, v in ipairs(gameMap.doors) do
        term.setCursorPos(1, 1)
        if v.team ~= player.team then
            if shapes.polyOverlap(playerPoly, v, 20) then
                local r = shapes.polygonCollision(playerPoly, v, translation)
                if r.willIntersect then
                    translation = translation + r.minimumTranslationVector
                end
            end
        end
    end
    collisiondt = collisiondt + os.epoch(timeunit) - collision0

    player.pos.x = player.pos.x + translation.x
    player.pos.y = player.pos.y + translation.y

    -- update player's ammunition status
    if player.lastReloadTime + player.reloadDelay < os.epoch "utc" then
        player.shotsRemaining = math.min(player.shotsRemaining + 1, player.shotCapacity)
        player.lastReloadTime = os.epoch "utc"
    end
end

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
    local bulletStatus = ("*"):rep(player.shotsRemaining) .. ("_"):rep(player.shotCapacity - player.shotsRemaining)
    win.write(("[%s]"):format(bulletStatus))
end

local flag = false
local function render()
    local render0 = os.epoch(timeunit)
    win.setVisible(false)
    box:clear(colors.black)
    map.renderMap(gameMap)
    for _, v in pairs(players) do
        renderPlayer(v)
    end
    for _, v in pairs(bullets) do
        local bulletPoly = shapes.polygon(v.pos, shapes.getRectanglePointsCorner(2, 2), colors.white)
        shapes.drawPolygon(bulletPoly)
    end
    box:render()
    renderHud(mainPlayer)
    renderdt = os.epoch(timeunit) - render0
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


mainPlayer.pos.x, mainPlayer.pos.y = mx, my
local function gameLoop()
    while true do
        sleep(0) -- main tick loop
        local t0 = os.epoch(timeunit)
        collisionChecks, edgeChecks = 0, 0
        collisiondt, renderdt = 0, 0
        -- updatePlayer(mainPlayer)
        for _, player in pairs(players) do
            tickPlayer(player)
        end
        for i in pairs(bullets) do
            tickBullet(i)
        end
        updateViewpos()
        render()
        framedt = os.epoch(timeunit) - t0
        handleStats()
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

local function ray(magnitude, angle)
    return vector.new(magnitude * trig.cos(angle), magnitude * trig.sin(angle), 0)
end

---@param player Player
local function canFire(player)
    return os.epoch('utc') - player.lastFireTime > player.fireDelay and player.shotsRemaining > 0
end

---@param player Player
local function fire(player)
    if not canFire(player) then return end
    player.lastFireTime = os.epoch('utc')
    player.lastReloadTime = player.lastFireTime
    player.shotsRemaining = player.shotsRemaining - 1
    newBullet(player.pos + ray(player.turretLength, player.turretAngle),
        ray(player.bulletVelocity, player.turretAngle) + ray(player.velocity, player.angle + 90))
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
                fire(mainPlayer)
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

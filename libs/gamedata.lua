local palette  = require "libs.palette"
local shapes   = require "libs.shapes"
local map      = require "libs.map"
local trig     = require "libs.trig"
local profile  = require "libs.gameprofiling"
local graphics = require "libs.graphics"

---@class Team
---@field color color
---@field tankTexture Texture
---@field turretTexture Texture

---@alias TeamID "red"|"blue"

local data     = {}
local friction = 0.99

data.tickTime  = 0

---@type table<TeamID,Team>
data.teams     = {
    red = {
        color = palette.colors.red,
        tankTexture = shapes.loadTexture("textures/red_tank.tex"),
        turretTexture = shapes.loadTexture("textures/red_tank_turret.tex"),
    },
    blue = {
        color = palette.colors.blue,
        tankTexture = shapes.loadTexture("textures/blue_tank.tex"),
        turretTexture = shapes.loadTexture("textures/blue_tank_turret.tex"),
    }
}

---@alias TankStats {maxVelocity:number,maxAngleVelocity:number,maxAcceleration:number}
---@class WeaponData
---@field shotCapacity number
---@field shotsRemaining number
---@field lastFireTime number
---@field fireDelay number
---@field lastReloadTime number
---@field reloadDelay number
---@field bulletVelocity number

---@class Player
---@field pos Vector
---@field size Vector
---@field angle number
---@field velocity number
---@field targetAngle number
---@field turretAngle number
---@field turretSize Vector
---@field turretLength number
---@field poly Polygon
---@field id integer
---@field boosting boolean
---@field targetVelocity number
---@field turretPoly Polygon
---@field turretColor color
---@field team TeamID
---@field boostStats TankStats
---@field baseStats TankStats
---@field weapon WeaponData
---@field alive boolean
---@field color color

---@type table<integer,Player>
data.players   = {}

---@type Bullet[]
data.bullets   = {}

---@param player Player
function data.createPlayerPolys(player)
    player.poly = shapes.polygon(player.pos, shapes.getRectangleCorners(player.size.x, player.size.y), player.color)
    player.poly.texture = data.teams[player.team].tankTexture
    player.poly.angle = player.angle
    player.turretPoly = shapes.polygon(player.pos, shapes.getRectangleCorners(player.turretSize.x, player.turretSize.y),
        player.color)
    player.turretPoly.texture = data.teams[player.team].turretTexture
    player.turretPoly.angle = player.turretAngle
end

---@param player Player
---@param team TeamID
function data.setPlayerTeam(player, team)
    player.color = data.teams[team].color
    player.turretColor = data.teams[team].color
    player.team = team
    data.createPlayerPolys(player)
end

---@param player Player
function data.respawnPlayer(player)
    player.alive = true
    player.pos = vector.new(30, 30, 0)
    player.angle = 0
end

---@param id integer
---@return Player
function data.newPlayer(id)
    local player = {
        pos = vector.new(30, 30, 0),
        size = vector.new(4, 9, 0),
        turretLength = 8,
        turretSize = vector.new(5, 5, 0),
        angle = 0,
        targetAngle = 0,
        turretAngle = 0,
        velocity = 0,
        targetVelocity = 0,
        boosting = false,
        boostStats = {
            maxVelocity = 2,
            maxAcceleration = 0.1,
            maxAngleVelocity = 128
        },
        baseStats = {
            maxVelocity = 1,
            maxAcceleration = 0.1,
            maxAngleVelocity = 8,
        },
        weapon = {
            shotCapacity = 3,
            shotsRemaining = 3,
            lastFireTime = 0,
            fireDelay = 200,
            reloadDelay = 800,
            lastReloadTime = 0,
            bulletVelocity = 3,
        },
        alive = false,
        id = id,
    }
    data.players[id] = player
    return player
end

---@param player Player
function data.tickPlayer(player)
    if player.alive then
        local stats = player.boosting and player.boostStats or player.baseStats

        local angleDifference = (player.targetAngle - player.angle)
        angleDifference = (angleDifference + 180) % 360 - 180
        local maxAngleVelocity = stats.maxAngleVelocity
        local angleVelocity = math.min(math.abs(angleDifference), maxAngleVelocity)
        local sign = angleDifference > 0 and 1 or -1
        player.angle = player.angle + angleVelocity * sign
        -- update player velocity
        local velDifference = player.targetVelocity - player.velocity
        local acceleration = math.min(math.abs(velDifference), stats.maxAcceleration)
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

        local collision0 = os.epoch(profile.timeunit)
        for _, v in pairs(data.map.walls) do
            if shapes.polyOverlap(playerPoly, v, 20) then
                local r = shapes.polygonCollision(playerPoly, v, translation)
                if r.willIntersect then
                    translation = translation + r.minimumTranslationVector
                end
            end
        end
        for _, v in ipairs(data.map.doors) do
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
        profile.collisiondt = profile.collisiondt + os.epoch(profile.timeunit) - collision0

        player.pos.x = player.pos.x + translation.x
        player.pos.y = player.pos.y + translation.y

        -- update player's ammunition status
        if player.weapon.lastReloadTime + player.weapon.reloadDelay < os.epoch "utc" then
            player.weapon.shotsRemaining = math.min(player.weapon.shotsRemaining + 1, player.weapon.shotCapacity)
            player.weapon.lastReloadTime = os.epoch "utc"
        end
    end
end

function data.newBullet(pos, velocity)
    ---@class Bullet
    local bullet = {
        pos = pos,
        vel = velocity,
        remainingBounces = 1,
        health = 1,
        ticksToLive = 20 * 20,
    }
    data.bullets[#data.bullets + 1] = bullet
    return bullet
end

---@param i integer
function data.tickBullet(i)
    local bullet = data.bullets[i]
    bullet.vel = bullet.vel * friction
    local translation = bullet.vel

    local bulletPoly = shapes.polygon(bullet.pos, shapes.getRectanglePointsCorner(2, 2), colors.white)

    local collision0 = os.epoch(profile.timeunit)

    local collisionOccured = false
    local function collide(poly)
        if shapes.polyOverlap(bulletPoly, poly, 20) then
            collisionOccured = true
            local r = shapes.polygonCollision(bulletPoly, poly, translation)
            if r.willIntersect then
                if bullet.remainingBounces == 0 then
                    data.bullets[i] = nil
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
                    data.bullets[i] = nil
                    return
                end
                bullet.remainingBounces = bullet.remainingBounces - 1
            end
        end
    end

    for _, v in ipairs(data.map.walls) do
        collide(v)
    end
    for _, v in ipairs(data.map.doors) do
        collide(v)
    end
    profile.collisiondt = profile.collisiondt + os.epoch(profile.timeunit) - collision0
    bullet.pos.x = bullet.pos.x + translation.x
    bullet.pos.y = bullet.pos.y + translation.y

    bullet.ticksToLive = bullet.ticksToLive - 1
    if bullet.ticksToLive == 0 then
        data.bullets[i] = nil
        return
    end
    if collisionOccured and data.isServer then
        data.queueGameEvent("bullet_bounce", { x = bullet.pos.x, y = bullet.pos.y, vx = bullet.vel.x, vy = bullet.vel.y })
    end
end

---@type LoadedMap
data.map = map.loadMapFile("maps/default.json")

function data.reset()
    data.players = {}
end

---@param player Player
function data.canFire(player)
    local weapon = player.weapon
    return os.epoch('utc') - weapon.lastFireTime > weapon.fireDelay and weapon.shotsRemaining > 0
end

local function ray(magnitude, angle)
    return vector.new(magnitude * trig.cos(angle), magnitude * trig.sin(angle), 0)
end
data.ray = ray

---@param player Player
function data.fire(player, pos, vel)
    if not data.canFire(player) then return end
    local weapon = player.weapon
    weapon.lastFireTime = os.epoch('utc')
    weapon.lastReloadTime = weapon.lastFireTime
    weapon.shotsRemaining = weapon.shotsRemaining - 1
    pos = pos or player.pos + ray(player.turretLength, player.turretAngle)
    vel = vel or ray(weapon.bulletVelocity, player.turretAngle) + ray(player.velocity, player.angle + 90)
    data.newBullet(pos, vel)
end

---@class Bullet
---@field pos Vector
---@field vel Vector
---@field remainingBounces integer
---@field health integer
---@field ticksToLive integer

local tw, th = term.getSize()


--- Client connection process
-- 1. Client downloads map
-- 2. Client fetches player information (minimum info needed to transmit)
-- 3. Client fetches bullet/etc information
-- 4. Client is connected and starts listening for state updates

local win, box
---@param window Window
---@param pixelbox table
function data.setupRendering(window, pixelbox)
    win = window
    box = pixelbox
end

---@param player Player
local function renderPlayer(player)
    if player.alive then
        shapes.drawPolygon(player.poly)
        graphics.drawAngledLine(player.pos.x, player.pos.y, player.turretLength, player.turretAngle, player.turretColor)
        shapes.drawPolygon(player.turretPoly)
    end
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

local cid = os.getComputerID()
local function render()
    local render0 = os.epoch(profile.timeunit)
    win.setVisible(false)
    box:clear(colors.black)
    map.renderMap(data.map)
    for _, v in pairs(data.players) do
        renderPlayer(v)
    end
    for _, v in pairs(data.bullets) do
        local bulletPoly = shapes.polygon(v.pos, shapes.getRectanglePointsCorner(2, 2), colors.white)
        shapes.drawPolygon(bulletPoly)
    end
    box:render()
    renderHud(data.players[cid])
    profile.renderdt = os.epoch(profile.timeunit) - render0
end

--- VIEW POS CODE

local heldKeys = {}
local directionVectors = {
    w = vector.new(0, -1, 0),
    d = vector.new(1, 0, 0),
    s = vector.new(0, 1, 0),
    a = vector.new(-1, 0, 0)
}

local function updateKeys()
    local mainPlayer = data.players[os.getComputerID()]
    term.setCursorPos(1, 1)
    local updated = mainPlayer.boosting ~= heldKeys[keys.leftShift]
    mainPlayer.boosting = heldKeys[keys.leftShift]
    local heldDirection = vector.new(0, 0, 0)
    for k, v in pairs(directionVectors) do
        if heldKeys[keys[k]] then
            heldDirection = heldDirection + v
        end
    end
    local preTargetAngle, preTargetVelocity = mainPlayer.targetAngle, mainPlayer.targetVelocity
    local targetAngle, targetVelocity = preTargetAngle, preTargetVelocity
    if heldDirection:length() > 0 then
        local angle = trig.atan(heldDirection.y / heldDirection.x) + 90
        if heldDirection.x < 0 then
            angle = angle + 180
        end
        targetAngle = angle
        targetVelocity = -(mainPlayer.boosting and mainPlayer.boostStats.maxVelocity or mainPlayer.baseStats.maxVelocity)
    else
        targetVelocity = 0
        targetAngle = mainPlayer.angle
    end
    updated = updated or targetAngle ~= preTargetAngle or targetVelocity ~= preTargetVelocity
    if updated then
        local network = require("libs.gamenetwork")
        network.queueGameEvent("player_movement_update",
            {
                id = mainPlayer.id,
                targetVelocity = targetVelocity,
                targetAngle = targetAngle,
                boosting = mainPlayer.boosting,
                pos = mainPlayer.pos,
                velocity = mainPlayer.velocity,
                angle = mainPlayer.angle,
            })
    end
end

local mx, my = tw, th / 2 * 3
local aiming = false
local aimpos = vector.new(0, 0, 0)
local view = vector.new(mx, my, 0)
local targetView = vector.new(mx, my, 0)
local viewVelocity = 5
function data.updateViewpos()
    local mainPlayer = data.players[os.getComputerID()]
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

function data.inputLoop()
    while true do
        local mainPlayer = data.players[os.getComputerID()]
        local e, key, x, y = os.pullEvent()
        if e == "key" then
            if key == keys.t then
                profile.enableOverlay = not profile.enableOverlay
            end
            heldKeys[key] = true
            updateKeys()
        elseif e == "key_up" then
            heldKeys[key] = nil
            updateKeys()
        elseif e == "mouse_click" or e == "mouse_drag" then
            local tankposx, tankposy = graphics.worldToScreenPos(mainPlayer.pos.x, mainPlayer.pos.y)
            local angle = graphics.calculateAngle(tankposx, tankposy, x * 2, y * 3)
            if key == 2 then
                -- right click to aim
                aiming = true
                if mainPlayer.turretAngle ~= angle then
                    local network = require("libs.gamenetwork")
                    network.queueGameEvent("player_aim", { id = mainPlayer.id, angle = angle })
                    mainPlayer.turretAngle = angle
                end
                aimpos = vector.new(x * 2, y * 3, 0)
            elseif key == 1 then
                if data.canFire(mainPlayer) then
                    local network = require("libs.gamenetwork")
                    mainPlayer.turretAngle = angle
                    network.queueGameEvent("player_fire_shot", {
                        id = mainPlayer.id,
                        angle = angle,
                        pos = mainPlayer.pos + ray(mainPlayer.turretLength, mainPlayer.turretAngle),
                        vel = ray(mainPlayer.weapon.bulletVelocity, mainPlayer.turretAngle) +
                            ray(mainPlayer.velocity, mainPlayer.angle + 90)
                    })
                end
                aimpos = vector.new(x * 2, y * 3, 0)
            end
        elseif e == "mouse_up" then
            if key == 2 then
                aiming = false
            end
        end
    end
end

function data.gameLoop()
    local network = require "libs.gamenetwork"
    while true do
        sleep(data.tickTime) -- main tick loop
        local t0 = os.epoch(profile.timeunit)
        profile.collisionChecks, profile.edgeChecks = 0, 0
        profile.collisiondt, profile.renderdt = 0, 0
        -- updatePlayer(mainPlayer)
        for _, player in pairs(data.players) do
            data.tickPlayer(player)
        end
        for i in pairs(data.bullets) do
            data.tickBullet(i)
        end
        if network.isClient then
            data.updateViewpos()
            render()
        end
        profile.framedt = os.epoch(profile.timeunit) - t0
        profile.frameCount = profile.frameCount + 1
        profile.totalRenderDt = profile.totalRenderDt + profile.renderdt
        profile.totalCollisionDt = profile.totalCollisionDt + profile.collisiondt
        profile.totaldt = profile.totaldt + profile.framedt
        if network.isClient then
            if profile.enableOverlay then
                profile.display(win)
            end
            win.setVisible(true)
        end
    end
end

return data

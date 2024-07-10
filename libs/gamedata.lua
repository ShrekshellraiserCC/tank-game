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

data.tickTime  = 0.05

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

---@class Class
---@field weapon WeaponData
---@field boostStats TankStats
---@field baseStats TankStats
---@field size Vector
---@field turretSize Vector
---@field turretLength number

---@alias ClassID "base" | "heavy"

---@type table<ClassID,Class>
data.classes   = {
    base = {
        weapon = {
            shotCapacity = 3,
            shotsRemaining = 3,
            lastFireTime = 0,
            fireDelay = 200,
            reloadDelay = 800,
            lastReloadTime = 0,
            bulletVelocity = 2,
            bulletParticleTick = function(player, bullet)
                if math.random() > 0.3 then
                    local vel, angle = data.getRay(bullet.vel)
                    local particleAngle = (angle + 180 + math.random(-20, 20)) % 360
                    data.newParticle(bullet.pos, data.ray(vel * 0.4, particleAngle), 1000, colors.gray)
                end
            end,
            health = 1
        },
        boostStats = {
            maxVelocity = 1.5,
            maxAcceleration = 0.1,
            maxAngleVelocity = 4
        },
        baseStats = {
            maxVelocity = 1,
            maxAcceleration = 0.1,
            maxAngleVelocity = 6,
        },
        size = vector.new(4, 9, 0),
        turretLength = 8,
        turretSize = vector.new(5, 5, 0),
    },
    heavy = {
        weapon = {
            shotCapacity = 6,
            shotsRemaining = 6,
            lastFireTime = 0,
            fireDelay = 300,
            reloadDelay = 1000,
            lastReloadTime = 0,
            bulletVelocity = 2,
            bulletParticleTick = function(player, bullet)
                if math.random() > 0.3 then
                    local vel, angle = data.getRay(bullet.vel)
                    local particleAngle = (angle + 180 + math.random(-20, 20)) % 360
                    data.newParticle(bullet.pos, data.ray(vel * 0.4, particleAngle), 1000, colors.gray)
                end
            end,
            health = 2
        },
        boostStats = {
            maxVelocity = 1.3,
            maxAcceleration = 0.1,
            maxAngleVelocity = 3
        },
        baseStats = {
            maxVelocity = 0.8,
            maxAcceleration = 0.1,
            maxAngleVelocity = 5,
        },
        size = vector.new(6, 10, 0),
        turretLength = 9,
        turretSize = vector.new(6, 6, 0),
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
---@field bulletParticleTick fun(player:Player,bullet:Bullet)
---@field health integer

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
---@field class ClassID
---@field classValid boolean?
---@field teamValid boolean?
---@field name string
---@field spectating integer?

---@type table<integer,Player>
data.players   = {}

---@type table<integer,Bullet>
data.bullets   = {}


---@class Particle
---@field pos Vector
---@field vel Vector
---@field color color
---@field lifetime number
---@field creation number

---@type table<number,Particle>
data.particles = {}

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
    player.teamValid = true
    if player.classValid then
        data.createPlayerPolys(player)
    end
end

local function sclone(t)
    local nt = {}
    for k, v in pairs(t) do
        nt[k] = v
    end
    return nt
end

---@param player Player
---@param class ClassID
function data.setPlayerClass(player, class)
    local info = data.classes[class]
    player.weapon = sclone(info.weapon)
    player.class = class
    player.baseStats = sclone(info.baseStats)
    player.boostStats = sclone(info.boostStats)
    player.size = info.size * 1
    player.turretLength = info.turretLength
    player.turretSize = info.turretSize * 1
    player.classValid = true
    if player.teamValid then
        data.createPlayerPolys(player)
    end
end

---@param player Player
function data.respawnPlayer(player)
    player.alive = true
    player.pos = vector.new(30, 30, 0)
    player.angle = 0
end

---@param id integer
---@param name string
---@return Player
function data.newPlayer(id, name)
    local player = {
        pos = vector.new(30, 30, 0),
        angle = 0,
        targetAngle = 0,
        turretAngle = 0,
        velocity = 0,
        targetVelocity = 0,
        boosting = false,
        alive = false,
        id = id,
        name = name
    }
    data.players[id] = player
    return player
end

local function tickPlayerWeapon(player)
    -- update player's ammunition status
    if player.weapon.lastReloadTime + player.weapon.reloadDelay < os.epoch "utc" then
        player.weapon.shotsRemaining = math.min(player.weapon.shotsRemaining + 1, player.weapon.shotCapacity)
        player.weapon.lastReloadTime = os.epoch "utc"
    end
end

local function tickPlayerPolygons(player)
    local playerPoly = player.poly
    playerPoly.pos = player.pos
    playerPoly.angle = player.angle
    player.turretPoly.pos = player.pos
    player.turretPoly.angle = player.turretAngle
    shapes.calculatePolygonTriangles(playerPoly)
    shapes.calculatePolygonTriangles(player.turretPoly)
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

        tickPlayerPolygons(player)
        local playerPoly = player.poly

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

        tickPlayerWeapon(player)
    end
end

---@param id integer
---@param owner integer
---@param pos Vector
---@param velocity Vector
---@return Bullet
function data.newBullet(id, owner, pos, velocity)
    local player = data.players[owner]
    ---@class Bullet
    local bullet = {
        pos = pos,
        vel = velocity,
        remainingBounces = 1,
        health = player.weapon.health,
        ticksToLive = 20 * 20,
        created = os.epoch("utc"),
        id = id,
        owner = owner,
    }
    data.bullets[id] = bullet
    return bullet
end

---@param vec Vector
---@return number magnitude
---@return number degrees
function data.getRay(vec)
    local magnitude = vec:length()
    local angle = 0
    if magnitude > 0 then
        angle = trig.atan(vec.y / vec.x)
        if vec.x < 0 then
            angle = angle + 180
        end
    end
    return magnitude, angle
end

function data.tickBulletClient(i)
    local bullet = data.bullets[i]

    local player = data.players[bullet.owner]
    player.weapon.bulletParticleTick(player, bullet)
end

---@param i integer
function data.tickBulletServer(i)
    local network = require "libs.gamenetwork"
    local bullet = data.bullets[i]
    bullet.vel = bullet.vel * friction
    if bullet.vel:length() < 0.4 or bullet.health <= 0 then
        network.queueGameEvent("bullet_destroy", { id = i })
        data.bullets[i] = nil
        return
    end
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
                    network.queueGameEvent("bullet_destroy", { id = i })
                    data.bullets[i] = nil
                    return
                end
                translation = translation + r.minimumTranslationVector * 1.2
                local normal = r.collisionNormal:normalize()
                bullet.vel = bullet.vel - normal * bullet.vel:dot(normal) * 2
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
    local player = data.players[bullet.owner]
    if bullet.created + 300 < os.epoch('utc') then
        for _, v in pairs(data.players) do
            if v.alive then
                local colliding = false
                colliding = shapes.polygonCollision(bulletPoly, v.poly, translation).intersect
                if colliding then
                    network.queueGameEvent("player_died", { id = v.id, bid = i })
                end
            end
        end
    end
    profile.collisiondt = profile.collisiondt + os.epoch(profile.timeunit) - collision0
    bullet.pos.x = bullet.pos.x + translation.x
    bullet.pos.y = bullet.pos.y + translation.y

    bullet.ticksToLive = bullet.ticksToLive - 1
    if bullet.ticksToLive == 0 then
        network.queueGameEvent("bullet_destroy", { id = i })
        data.bullets[i] = nil
        return
    end
    if collisionOccured and data.isServer then
        data.queueGameEvent("bullet_bounce", { x = bullet.pos.x, y = bullet.pos.y, vx = bullet.vel.x, vy = bullet.vel.y })
    end
end

---@param pos Vector
---@param vel Vector
---@param lifetime number
---@param color color
function data.newParticle(pos, vel, lifetime, color)
    data.particles[#data.particles + 1] = {
        pos = pos,
        vel = vel,
        lifetime = lifetime,
        creation = os.epoch("utc"),
        color = color
    }
end

---@param i integer
function data.tickParticle(i)
    local particle = data.particles[i]

    particle.pos = particle.pos + particle.vel
    particle.vel = particle.vel * friction
    if os.epoch('utc') > particle.creation + particle.lifetime then
        data.particles[i] = nil
    end
end

data.mapData = map.readFile("maps/default.json")
---@type LoadedMap
data.map = map.loadMap(data.mapData)

function data.reset()
    data.players = {}
end

---@param player Player
function data.canFire(player)
    local weapon = player.weapon
    return player.alive and os.epoch('utc') - weapon.lastFireTime > weapon.fireDelay and weapon.shotsRemaining > 0
end

---@param magnitude number
---@param angle number
---@return Vector
local function ray(magnitude, angle)
    return vector.new(magnitude * trig.cos(angle), magnitude * trig.sin(angle), 0)
end
data.ray = ray

---@param bid integer
---@param player Player
function data.fire(bid, player, pos, vel)
    if not data.canFire(player) then return end
    local weapon = player.weapon
    weapon.lastFireTime = os.epoch('utc')
    weapon.lastReloadTime = weapon.lastFireTime
    weapon.shotsRemaining = weapon.shotsRemaining - 1
    pos = pos or player.pos + ray(player.turretLength, player.turretAngle)
    vel = vel or ray(weapon.bulletVelocity, player.turretAngle) + ray(player.velocity, player.angle + 90)
    data.newBullet(bid, player.id, pos, vel)
end

function data.explosion(pos)
    for i = 1, 10 do
        -- orange flame particles
        local vel = math.random()
        local angle = math.random(0, 360)
        data.newParticle(pos, data.ray(vel, angle), 800, colors.orange)
    end
    for i = 1, 30 do
        -- smoke particles
        local vel = math.random() * 2
        local angle = math.random(0, 360)
        data.newParticle(pos, data.ray(vel, angle), 800, colors.gray)
    end
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

---@type Player?
data.killer = nil

---@param player Player
local function renderHud(player)
    -- win.setCursorPos(1, th)
    -- win.setBackgroundColor(colors.black)
    -- win.setTextColor(colors.white)
    -- win.clearLine()
    if player.alive then
        local weapon = player.weapon
        local x, y = graphics.worldToScreenPos(player.pos.x, player.pos.y)
        x, y = x / 2, y / 3
        x = x - weapon.shotCapacity
        y = y - 3
        for i = weapon.shotCapacity, 1, -1 do
            win.setCursorPos(x + i * 2, y)
            win.write(weapon.shotsRemaining >= i and "\7" or "\186")
        end
        if weapon.shotsRemaining ~= weapon.shotCapacity then
            local filledPercentage = (os.epoch('utc') - weapon.lastReloadTime) / weapon.reloadDelay
            local str = ("\127"):rep(math.floor(filledPercentage * (weapon.shotCapacity * 2 - 1)))
            str = str .. ("\183"):rep(math.ceil((1 - filledPercentage) * (weapon.shotCapacity * 2 - 1)))
            win.setCursorPos(x + 2, y + 1)
            win.write(str)
        end
    elseif data.killer then
        local w, h = win.getSize()
        local str = ("Killed by %s"):format(data.killer.name)
        win.setCursorPos((w - #str) / 2, h - 2)
        win.write(str)
    end
end

local cid = os.getComputerID()
local function render()
    local render0 = os.epoch(profile.timeunit)
    win.setVisible(false)
    box:clear(colors.black)
    map.renderMap(data.map)
    for i, v in pairs(data.particles) do
        graphics.setPixel(v.pos.x, v.pos.y, v.color)
    end
    for _, v in pairs(data.players) do
        renderPlayer(v)
    end
    for _, v in pairs(data.bullets) do
        local player = data.players[v.owner]
        local bulletPoly = shapes.polygon(v.pos, shapes.getRectanglePointsCorner(2, 2), player.color)
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
    if mainPlayer.alive then
        if aiming then
            targetView = mainPlayer.pos + (aimpos - vector.new(tw, th / 2 * 3, 0)) * 0.40
        else
            targetView.x = mainPlayer.pos.x
            targetView.y = mainPlayer.pos.y
        end
    elseif mainPlayer.spectating then
        targetView = data.players[mainPlayer.spectating].pos
    else
        targetView = mainPlayer.pos
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
        local player = data.players[os.getComputerID()]
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
            local tankposx, tankposy = graphics.worldToScreenPos(player.pos.x, player.pos.y)
            local angle = graphics.calculateAngle(tankposx, tankposy, x * 2, y * 3)
            if key == 2 then
                -- right click to aim
                aiming = true
                if player.turretAngle ~= angle then
                    local network = require("libs.gamenetwork")
                    network.queueGameEvent("player_aim", { id = player.id, angle = angle })
                    player.turretAngle = angle
                end
                aimpos = vector.new(x * 2, y * 3, 0)
            elseif key == 1 then
                if data.canFire(player) then
                    local network = require("libs.gamenetwork")
                    player.turretAngle = angle
                    network.queueGameEvent("player_fire_shot", {
                        id = player.id,
                        angle = angle
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

local callbacks = {}
function data.createCallback(time, func, rep)
    local id = os.startTimer(time)
    callbacks[id] = { func = func, time = time, rep = rep }
    return id
end

function data.callbackHandlers()
    while true do
        local _, id = os.pullEvent("timer")
        local info = callbacks[id]
        if info then
            local nid
            if info.rep then
                nid = data.createCallback(info.time, info.func, info.rep)
            end
            local ret = info.func()
            if info.rep then
                callbacks[nid].rep = ret
            end
            callbacks[id] = nil
        end
    end
end

function data.startClientTicking()
    data.createCallback(data.tickTime, function()
        local t0 = os.epoch(profile.timeunit)
        profile.collisiondt, profile.renderdt = 0, 0
        for _, player in pairs(data.players) do
            tickPlayerWeapon(player)
            tickPlayerPolygons(player)
        end
        for i in pairs(data.particles) do
            data.tickParticle(i)
        end
        for i in pairs(data.bullets) do
            data.tickBulletClient(i)
        end
        profile.framedt = os.epoch(profile.timeunit) - t0
        profile.frameCount = profile.frameCount + 1
        profile.totalRenderDt = profile.totalRenderDt + profile.renderdt
        profile.totaldt = profile.totaldt + profile.framedt
        return true
    end, true)
end

function data.startClientDrawing()
    data.createCallback(data.tickTime, function()
        data.updateViewpos()
        render()
        if profile.enableOverlay then
            profile.display(win)
        end
        win.setVisible(true)
        return true
    end, true)
end

local function tickBulletOnBulletCollisions()
    local remainingBullets = sclone(data.bullets)
    local bulletPolys = {}
    for id0, bullet0 in pairs(remainingBullets) do
        remainingBullets[id0] = nil
        local bulletPoly0 = bulletPolys[id0] or
            shapes.polygon(bullet0.pos, shapes.getRectanglePointsCorner(2, 2), colors.white)
        bulletPolys[id0] = bulletPoly0
        for id1, bullet1 in pairs(remainingBullets) do
            local bulletPoly1 = bulletPolys[id1] or
                shapes.polygon(bullet1.pos, shapes.getRectanglePointsCorner(2, 2), colors.white)
            local colliding = false
            colliding = shapes.polygonCollision(bulletPoly0, bulletPoly1, vector.new(0, 0, 0)).intersect
            if colliding then
                local ohealth = bullet0.health
                local health = bullet1.health
                bullet0.health = ohealth - health
                bullet1.health = health - ohealth
            end
        end
    end
end

function data.startServerTicking()
    data.createCallback(data.tickTime, function()
        local t0 = os.epoch(profile.timeunit)
        profile.collisionChecks, profile.edgeChecks = 0, 0
        profile.collisiondt, profile.renderdt = 0, 0
        for _, player in pairs(data.players) do
            data.tickPlayer(player)
        end
        tickBulletOnBulletCollisions()
        for i in pairs(data.bullets) do
            data.tickBulletServer(i)
        end
        profile.framedt = os.epoch(profile.timeunit) - t0
        profile.frameCount = profile.frameCount + 1
        profile.totalRenderDt = profile.totalRenderDt + profile.renderdt
        profile.totalCollisionDt = profile.totalCollisionDt + profile.collisiondt
        profile.totaldt = profile.totaldt + profile.framedt
        return true
    end, true)
end

return data

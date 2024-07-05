local palette  = require "libs.palette"
local shapes   = require "libs.shapes"
local map      = require "libs.map"
local trig     = require "libs.trig"
local profile  = require "libs.gameprofiling"

---@class Team
---@field color color
---@field tankTexture Texture
---@field turretTexture Texture

---@alias TeamID "red"|"blue"

local data     = {}
local friction = 0.99


---@type table<TeamID,Team>
data.teams = {
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

---@type table<integer,Player>
data.players = {}

---@type Bullet[]
data.bullets = {}

---@param id integer
---@param team TeamID
---@return Player
function data.newPlayer(id, team)
    local player = {
        pos = vector.new(30, 30, 0),
        size = vector.new(4, 9, 0),
        turretLength = 8,
        turretSize = vector.new(5, 5, 0),
        color = data.teams[team].color,
        turretColor = data.teams[team].color,
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
        team = team
    }
    player.poly = shapes.polygon(player.pos, shapes.getRectangleCorners(player.size.x, player.size.y), player.color)
    player.poly.texture = data.teams[team].tankTexture
    player.poly.angle = player.angle
    player.turretPoly = shapes.polygon(player.pos, shapes.getRectangleCorners(player.turretSize.x, player.turretSize.y),
        player.color)
    player.turretPoly.texture = data.teams[team].turretTexture
    player.turretPoly.angle = player.turretAngle
    data.players[id] = player
    return player
end

---@param player Player
function data.tickPlayer(player)
    -- update player angle

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

function data.newBullet(pos, velocity)
    ---@class Bullet
    local bullet = {
        pos = pos,
        vel = velocity,
        remainingBounces = 5,
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

    local function collide(poly)
        if shapes.polyOverlap(bulletPoly, poly, 20) then
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
    end
end

---@type LoadedMap
data.map = map.loadMapFile("maps/default.json")

function data.reset()
    data.players = {}
end

---@param player Player
local function canFire(player)
    local weapon = player.weapon
    return os.epoch('utc') - weapon.lastFireTime > weapon.fireDelay and weapon.shotsRemaining > 0
end

local function ray(magnitude, angle)
    return vector.new(magnitude * trig.cos(angle), magnitude * trig.sin(angle), 0)
end

---@param player Player
function data.fire(player)
    if not canFire(player) then return end
    local weapon = player.weapon
    weapon.lastFireTime = os.epoch('utc')
    weapon.lastReloadTime = weapon.lastFireTime
    weapon.shotsRemaining = weapon.shotsRemaining - 1
    data.newBullet(player.pos + ray(player.turretLength, player.turretAngle),
        ray(weapon.bulletVelocity, player.turretAngle) + ray(player.velocity, player.angle + 90))
end

return data

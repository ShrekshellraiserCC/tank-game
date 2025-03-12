local gamedata                  = {}

local palette                   = require "libs.palette"
local shapes                    = require "libs.shapes"
local map                       = require "libs.map"
local trig                      = require "libs.trig"
local profile                   = require "libs.debugoverlay"
local graphics                  = require "libs.graphics"
local gamesettings              = require "libs.gamesettings"

---@class Team
---@field color color
---@field tankTexture Texture
---@field turretTexture Texture
---@field accent color

---@alias TeamID "red"|"blue"

local friction                  = 0.99

gamedata.tickTime               = 0.05

local redTankTextureData        = map.readFile("textures/red_tank.tex")
local redTankTurretTextureData  = map.readFile("textures/red_tank_turret.tex")
local blueTankTextureData       = map.readFile("textures/blue_tank.tex")
local blueTankTurretTextureData = map.readFile("textures/blue_tank_turret.tex")

---@type table<TeamID,Team>
gamedata.teams                  = {
    red = {
        color = palette.colors.red,
        accent = palette.colors.redShade,
        tankTexture = shapes.parseTexture(redTankTextureData),
        turretTexture = shapes.parseTexture(redTankTurretTextureData),
    },
    blue = {
        color = palette.colors.blue,
        accent = palette.colors.blueShade,
        tankTexture = shapes.parseTexture(blueTankTextureData),
        turretTexture = shapes.parseTexture(blueTankTurretTextureData),
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
gamedata.classes                = {
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
                    local vel, angle = gamedata.getRay(bullet.vel)
                    local particleAngle = (angle + 180 + math.random(-20, 20)) % 360
                    gamedata.newParticle(bullet.pos, gamedata.ray(vel * 0.4, particleAngle), 1000, colors.gray)
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
        size = vector.new(6, 10, 0),
        turretLength = 10,
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
                    local vel, angle = gamedata.getRay(bullet.vel)
                    local particleAngle = (angle + 180 + math.random(-20, 20)) % 360
                    gamedata.newParticle(bullet.pos, gamedata.ray(vel * 0.4, particleAngle), 1000, colors.gray)
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
        size = vector.new(8, 12, 0),
        turretLength = 12,
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
---@field kills number
---@field deaths number
---@field willRespawnAt number?

---@type table<integer,Player>
gamedata.players                = {}

---@type table<integer,Bullet>
gamedata.bullets                = {}

---@alias GameMode "SPECTATING"|"PLAYING"|"KILL_CAM"|"MENU"
---@type GameMode
gamedata.mode                   = "SPECTATING"

---@class Particle
---@field pos Vector
---@field vel Vector
---@field color color
---@field lifetime number
---@field creation number

---@type table<number,Particle>
gamedata.particles              = {}

local tw, th                    = term.getSize()

local midpx, midpy              = tw, th / 2 * 3
local aiming                    = false
local aimpos                    = vector.new(0, 0, 0)
local view                      = vector.new(midpx, midpy, 0)
local targetView                = vector.new(midpx, midpy, 0)
local viewVelocity              = 5

---@param player Player
function gamedata.createPlayerPolys(player)
    player.poly = shapes.polygon(player.pos, shapes.getRectangleCorners(player.size.x, player.size.y), player.color)
    -- player.poly.texture = gamedata.teams[player.team].tankTexture
    player.poly.angle = player.angle
    player.turretPoly = shapes.polygon(player.pos, shapes.getRectangleCorners(player.turretSize.x, player.turretSize.y),
        gamedata.teams[player.team].accent)
    -- player.turretPoly.texture = gamedata.teams[player.team].turretTexture
    player.turretPoly.angle = player.turretAngle
end

---@param player Player
---@param team TeamID
function gamedata.setPlayerTeam(player, team)
    player.color = gamedata.teams[team].color
    player.turretColor = gamedata.teams[team].accent
    player.team = team
    player.teamValid = true
    if player.classValid then
        gamedata.createPlayerPolys(player)
    end
end

---@return number red
---@return number blue
---@return number spectator
function gamedata.getTeamCounts()
    local redCount = 0
    local blueCount = 0
    local spectatorCount = 0
    for k, v in pairs(gamedata.players) do
        if v.team == "red" then
            redCount = redCount + 1
        elseif v.team == "blue" then
            blueCount = blueCount + 1
        else
            spectatorCount = spectatorCount + 1
        end
    end
    return redCount, blueCount, spectatorCount
end

function gamedata.getUnbalancedTeam()
    local red, blue = gamedata.getTeamCounts()
    if red < blue then
        return "red"
    end
    return "blue"
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
function gamedata.setPlayerClass(player, class)
    local info = gamedata.classes[class]
    player.weapon = sclone(info.weapon)
    player.class = class
    player.baseStats = sclone(info.baseStats)
    player.boostStats = sclone(info.boostStats)
    player.size = info.size * 1
    player.turretLength = info.turretLength
    player.turretSize = info.turretSize * 1
    player.classValid = true
    if player.teamValid then
        gamedata.createPlayerPolys(player)
    end
end

---@param player Player
function gamedata.respawnPlayer(player)
    player.alive = true
    local possibleSpawns = gamedata.map.spawns[player.team]
    local spawn = possibleSpawns[math.random(1, #possibleSpawns)]
    player.pos = vector.new(spawn[1], spawn[2], 0)
    player.angle = 0
    if player.id == os.computerID() then
        gamedata.mode = "PLAYING"
        view.x = spawn[1]
        view.y = spawn[2]
    end
    player.willRespawnAt = nil
end

---@param id integer
---@param name string
---@return Player
function gamedata.newPlayer(id, name)
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
        name = name,
        kills = 0,
        deaths = 0,
    }
    gamedata.players[id] = player
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
function gamedata.tickPlayer(player)
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

        for _, v in pairs(gamedata.map.walls) do
            if shapes.polyOverlap(playerPoly, v, 20) then
                local r = shapes.polygonCollision(playerPoly, v, translation)
                if r.willIntersect then
                    translation = translation + r.minimumTranslationVector
                end
            end
        end
        for _, v in ipairs(gamedata.map.doors) do
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

        player.pos.x = player.pos.x + translation.x
        player.pos.y = player.pos.y + translation.y

        tickPlayerWeapon(player)
    else
        local network = require "libs.gamenetwork"
        if player.willRespawnAt and player.willRespawnAt < os.epoch("utc") then
            player.willRespawnAt = nil
            network.queueGameEvent("player_respawn", { id = player.id })
        end
    end
end

---@param id integer
---@param owner integer
---@param pos Vector
---@param velocity Vector
---@return Bullet
function gamedata.newBullet(id, owner, pos, velocity)
    local player = gamedata.players[owner]
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
    gamedata.bullets[id] = bullet
    return bullet
end

---@param vec Vector
---@return number magnitude
---@return number degrees
function gamedata.getRay(vec)
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

function gamedata.tickBulletClient(i)
    local bullet = gamedata.bullets[i]

    local player = gamedata.players[bullet.owner]
    player.weapon.bulletParticleTick(player, bullet)
end

---@param player Player
---@param bid integer?
function gamedata.killPlayer(player, bid)
    local network = require "libs.gamenetwork"
    network.queueGameEvent("player_died",
        { id = player.id, bid = bid, willRespawnAt = os.epoch('utc') + gamesettings.respawnTimer })
end

---@param i integer
function gamedata.tickBulletServer(i)
    local network = require "libs.gamenetwork"
    local bullet = gamedata.bullets[i]
    bullet.vel = bullet.vel * friction
    if bullet.vel:length() < 0.4 or bullet.health <= 0 then
        network.queueGameEvent("bullet_destroy", { id = i })
        gamedata.bullets[i] = nil
        return
    end
    local translation = bullet.vel

    local bulletPoly = shapes.polygon(bullet.pos, shapes.getRectanglePointsCorner(2, 2), colors.white)

    local collisionOccured = false
    local function collide(poly)
        if shapes.polyOverlap(bulletPoly, poly, 20) then
            collisionOccured = true
            local r = shapes.polygonCollision(bulletPoly, poly, translation)
            if r.willIntersect then
                if bullet.remainingBounces == 0 then
                    network.queueGameEvent("bullet_destroy", { id = i })
                    gamedata.bullets[i] = nil
                    return
                end
                translation = translation + r.minimumTranslationVector * 1.2
                local normal = r.collisionNormal:normalize()
                bullet.vel = bullet.vel - normal * bullet.vel:dot(normal) * 2
                bullet.remainingBounces = bullet.remainingBounces - 1
            end
        end
    end

    for _, v in ipairs(gamedata.map.walls) do
        collide(v)
    end
    for _, v in ipairs(gamedata.map.doors) do
        collide(v)
    end
    local player = gamedata.players[bullet.owner]
    if bullet.created + 300 < os.epoch('utc') then
        for _, v in pairs(gamedata.players) do
            if v.alive then
                local colliding = false
                colliding = shapes.polygonCollision(bulletPoly, v.poly, translation).intersect
                if colliding then
                    gamedata.killPlayer(v, bullet.id)
                end
            end
        end
    end
    bullet.pos.x = bullet.pos.x + translation.x
    bullet.pos.y = bullet.pos.y + translation.y

    bullet.ticksToLive = bullet.ticksToLive - 1
    if bullet.ticksToLive == 0 then
        network.queueGameEvent("bullet_destroy", { id = i })
        gamedata.bullets[i] = nil
        return
    end
    if collisionOccured and gamedata.isServer then
        gamedata.queueGameEvent("bullet_bounce",
            { x = bullet.pos.x, y = bullet.pos.y, vx = bullet.vel.x, vy = bullet.vel.y })
    end
end

---@param pos Vector
---@param vel Vector
---@param lifetime number
---@param color color
function gamedata.newParticle(pos, vel, lifetime, color)
    gamedata.particles[#gamedata.particles + 1] = {
        pos = pos,
        vel = vel,
        lifetime = lifetime,
        creation = os.epoch("utc"),
        color = color
    }
end

---@param i integer
function gamedata.tickParticle(i)
    local particle = gamedata.particles[i]

    particle.pos = particle.pos + particle.vel
    particle.vel = particle.vel * friction
    if os.epoch('utc') > particle.creation + particle.lifetime then
        gamedata.particles[i] = nil
    end
end

gamedata.mapData = map.readFile("maps/default.json")
---@type LoadedMap
gamedata.map = map.loadMap(gamedata.mapData)

function gamedata.reset()
    gamedata.players = {}
end

---@param player Player
function gamedata.canFire(player)
    local weapon = player.weapon
    return player.alive and os.epoch('utc') - weapon.lastFireTime > weapon.fireDelay and weapon.shotsRemaining > 0
end

---@param magnitude number
---@param angle number
---@return Vector
local function ray(magnitude, angle)
    return vector.new(magnitude * trig.cos(angle), magnitude * trig.sin(angle), 0)
end
gamedata.ray = ray

---@param bid integer
---@param player Player
function gamedata.fire(bid, player, pos, vel)
    if not gamedata.canFire(player) then return end
    local weapon = player.weapon
    weapon.lastFireTime = os.epoch('utc')
    weapon.lastReloadTime = weapon.lastFireTime
    weapon.shotsRemaining = weapon.shotsRemaining - 1
    pos = pos or player.pos + ray(player.turretLength, player.turretAngle)
    vel = vel or ray(weapon.bulletVelocity, player.turretAngle) + ray(player.velocity, player.angle + 90)
    gamedata.newBullet(bid, player.id, pos, vel)
end

function gamedata.explosion(pos)
    for i = 1, 10 do
        -- orange flame particles
        local vel = math.random()
        local angle = math.random(0, 360)
        gamedata.newParticle(pos, gamedata.ray(vel, angle), 800, colors.orange)
    end
    for i = 1, 30 do
        -- smoke particles
        local vel = math.random() * 2
        local angle = math.random(0, 360)
        gamedata.newParticle(pos, gamedata.ray(vel, angle), 800, colors.gray)
    end
end

---@class Bullet
---@field pos Vector
---@field vel Vector
---@field remainingBounces integer
---@field health integer
---@field ticksToLive integer


--- Client connection process
-- 1. Client downloads map
-- 2. Client fetches player information (minimum info needed to transmit)
-- 3. Client fetches bullet/etc information
-- 4. Client is connected and starts listening for state updates

---@type Window
local win, box
---@param window Window
---@param pixelbox table
function gamedata.setupRendering(window, pixelbox)
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
gamedata.killer = nil

---@alias MenuMode "TEAM_SELECT"|"CLASS_SELECT"
---@type MenuMode
gamedata.menuMode = "TEAM_SELECT"

local function drawRectangle(x, y, w, h, color)
    local old = win.getBackgroundColor()
    win.setBackgroundColor(color)
    win.setCursorPos(x, y)
    local horiz = (" "):rep(w)
    win.write(horiz)
    win.setCursorPos(x, y + h - 1)
    win.write(horiz)
    for i = 1, h do
        win.setCursorPos(x, y + i - 1)
        win.write(" ")
        win.setCursorPos(x + w - 1, y + i - 1)
        win.write(" ")
    end
    win.setBackgroundColor(old)
end

---@type table<TeamID,table<ClassID,Player>>
local dummyPlayers = {}

for teamid, team in pairs(gamedata.teams) do
    dummyPlayers[teamid] = {}
    for classid, class in pairs(gamedata.classes) do
        local player = gamedata.newPlayer(-1, "DUMMY")
        player.alive = true
        gamedata.players[-1] = nil

        gamedata.setPlayerClass(player, classid)
        gamedata.setPlayerTeam(player, teamid)
        dummyPlayers[teamid][classid] = player
    end
end

---@param y number
---@param str string
---@param w integer
---@return number x
---@return number y
---@return string s
local function centerText(y, str, w, offx)
    return (w - #str) / 2 + (offx or 0), y, str
end

local function write(x, y, t)
    win.setCursorPos(x, y)
    win.write(t)
end

---@type string[]
local classList = {}
for classid in pairs(gamedata.classes) do
    classList[#classList + 1] = classid
end
local classCount = #classList

local _, redDummyTank = next(dummyPlayers.red)
local _, blueDummyTank = next(dummyPlayers.blue)
assert(redDummyTank and blueDummyTank, "Missing dummy tanks for menu renders!")
local function renderMenu()
    local hw = tw / 2
    if gamedata.menuMode == "TEAM_SELECT" then
        win.clear()
        redDummyTank.pos = vector.new(midpx / 2, midpy, 0)
        redDummyTank.angle = (redDummyTank.angle + 1) % 360
        redDummyTank.turretAngle = (redDummyTank.turretAngle - 1) % 360
        tickPlayerPolygons(redDummyTank)
        blueDummyTank.pos = vector.new(midpx * 3 / 2, midpy, 0)
        blueDummyTank.angle = (blueDummyTank.angle + 1) % 360
        blueDummyTank.turretAngle = (blueDummyTank.turretAngle - 1) % 360
        tickPlayerPolygons(blueDummyTank)
        renderPlayer(redDummyTank)
        renderPlayer(blueDummyTank)
        box:render()
        write(centerText(1, "Team Selection", tw))
        win.setTextColor(palette.colors.red)
        write(centerText(3, "Red", tw / 2))
        drawRectangle(1, 2, hw, th - 1, palette.colors.red)
        win.setTextColor(palette.colors.blue)
        write(centerText(3, "Blue", tw / 2, tw / 2 + 1))
        drawRectangle(hw + 1, 2, hw, th - 1, palette.colors.blue)
        win.setTextColor(palette.colors.white)
    else
        local team = gamedata.players[os.computerID()].team
        if not team then
            gamedata.menuMode = "TEAM_SELECT"
            return
        end
        win.clear()
        local buttonPixWidth = tw * 2 / classCount
        for classnumber, classid in ipairs(classList) do
            local player = dummyPlayers[team][classid]
            player.pos = vector.new(buttonPixWidth * (classnumber - 0.5) + 1, midpy, 0)
            player.angle = (player.angle + 1) % 360
            player.turretAngle = (player.turretAngle - 1) % 360
            tickPlayerPolygons(player)
            renderPlayer(player)
        end
        box:render()
        local buttonWidth = tw / classCount
        local color = gamedata.teams[team].color
        write(centerText(1, "Class Selection", tw))
        for classnumber, classid in ipairs(classList) do
            local x = buttonWidth * (classnumber - 1) + 1
            drawRectangle(x, 2, buttonWidth, th - 1, color)
            write(centerText(3, classid, buttonWidth, x))
        end
    end
end


---@param player Player
local function renderHud(player)
    -- win.setCursorPos(1, th)
    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.white)
    -- win.clearLine()
    local network = require("libs.gamenetwork")
    local timingOut = network.lastMessage + gamesettings.clientTimeoutWarning < os.epoch("utc")
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
    elseif gamedata.mode == "KILL_CAM" and gamedata.killer then
        local w, h = win.getSize()
        local str = ("Killed by %s"):format(gamedata.killer.name)
        win.setCursorPos((w - #str) / 2, h - 2)
        win.write(str)
    end
    local time = os.epoch("utc")
    if not player.alive and player.willRespawnAt and player.willRespawnAt > time then
        write(centerText(2, ("Respawning in %.1fs"):format((player.willRespawnAt - time) / 1000), tw))
    end
    if timingOut then
        local ot = win.getTextColor()
        win.setTextColor(colors.red)
        local ts = (("Lost Connection. Disconnecting in %.1fs"):format((network.lastMessage + gamesettings.clientTimeout - os.epoch("utc")) / 1000))
        win.setCursorPos(tw - #ts, 1)
        win.write(ts)
        win.setTextColor(ot)
    end
end

local function getSlopeChar(theta)
    theta = theta % 180
    if theta < 45 - 22 then
        return "-"
    elseif theta < 90 - 22 then
        return "\\"
    elseif theta < 135 - 22 then
        return "|"
    elseif theta < 180 - 22 then
        return "/"
    end
    return "-"
end

local function renderVisibilityAssistors()
    -- place a character on the center of every tank
    -- place an appropriately rotated character at the end of every tanks' barrel
    for _, v in pairs(gamedata.players) do
        if v.alive then
            local x, y = graphics.worldToScreenPos(v.pos.x, v.pos.y)
            win.setCursorPos(math.floor(x / 2 + 0.5), math.floor(y / 3 + 0.5))
            win.setBackgroundColor(gamedata.teams[v.team].accent)
            win.setTextColor(v.color)
            win.write("T")
            win.setBackgroundColor(colors.black)

            local theta = v.turretAngle
            local dx = trig.cos(theta) * v.turretLength * 1.2
            local dy = trig.sin(theta) * v.turretLength * 1.2
            win.setCursorPos(math.floor((x + dx) / 2 + 0.5), math.floor((y + dy) / 3 + 0.5))
            win.setTextColor(v.color)
            win.write(getSlopeChar(theta))
        end
    end
end

local renderTimeString = ("Render: %%d%s"):format(profile.timelabel)
local cid = os.getComputerID()
local function render()
    local render0 = os.epoch(profile.timeunit)
    win.setVisible(false)
    box:clear(colors.black)
    if gamedata.mode ~= "MENU" then
        map.renderMap(gamedata.map)
        for i, v in pairs(gamedata.particles) do
            graphics.setPixel(v.pos.x, v.pos.y, v.color)
        end
        for _, v in pairs(gamedata.players) do
            renderPlayer(v)
        end
        box:render()
        for _, v in pairs(gamedata.bullets) do
            local player = gamedata.players[v.owner]
            -- local bulletPoly = shapes.polygon(v.pos, shapes.getRectanglePointsCorner(2, 2), player.color)
            -- shapes.drawPolygon(bulletPoly)
            local x, y = graphics.worldToScreenPos(v.pos.x, v.pos.y)
            win.setCursorPos(math.floor(x / 2 + 0.5), math.floor(y / 3 + 0.5))
            win.setTextColor(player.color)
            win.write("\7")
        end
        renderVisibilityAssistors()
        renderHud(gamedata.players[cid])
        profile.set(renderTimeString, os.epoch(profile.timeunit) - render0)
        if profile.enableOverlay then
            profile.display(win)
        end
    else
        renderMenu()
    end
    win.setVisible(true)
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
    local mainPlayer = gamedata.players[os.getComputerID()]
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

function gamedata.updateViewpos()
    if gamedata.mode ~= "MENU" then
        local mainPlayer = gamedata.players[os.getComputerID()]
        if mainPlayer.alive then
            if aiming then
                targetView = mainPlayer.pos + (aimpos - vector.new(tw, th / 2 * 3, 0)) * 0.40
            else
                targetView.x = mainPlayer.pos.x
                targetView.y = mainPlayer.pos.y
            end
        elseif mainPlayer.spectating then
            targetView = gamedata.players[mainPlayer.spectating].pos
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
    else
        graphics.setViewCorner(0, 0)
    end
end

local function cycleSpectating()
    local player = gamedata.players[os.getComputerID()]
    local spectating = player.spectating
    spectating = next(gamedata.players, spectating)
    if not spectating then
        spectating = next(gamedata.players)
    end
end

local function handleMenuClick(x, y)
    local buttonWidth = tw / classCount
    for i, classid in ipairs(classList) do
        if x < buttonWidth * i + 1 then
            return i, classid
        end
    end
end

function gamedata.inputLoop()
    local network = require "libs.gamenetwork"
    while true do
        local player = gamedata.players[os.getComputerID()]
        local e, key, x, y = os.pullEvent()
        if gamedata.mode ~= "MENU" then
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
                    if math.abs(player.turretAngle - angle) > 5 then
                        network.queueGameEvent("player_aim", { id = player.id, angle = angle })
                        player.turretAngle = angle
                    end
                    aimpos = vector.new(x * 2, y * 3, 0)
                elseif key == 1 then
                    if gamedata.canFire(player) then
                        player.turretAngle = angle
                        network.queueGameEvent("player_fire_shot", {
                            id = player.id,
                            angle = angle
                        })
                        aiming = false
                    end
                    aimpos = vector.new(x * 2, y * 3, 0)
                end
            elseif e == "mouse_up" then
                if key == 2 then
                    aiming = false
                end
            end
            if gamedata.mode == "SPECTATING" then
                if e == "mouse_click" then
                    cycleSpectating()
                end
            end
        else
            if gamedata.menuMode == "TEAM_SELECT" then
                if e == "mouse_click" then
                    if x < tw / 2 then
                        network.queueGameEvent("player_set_team", { id = player.id, team = "red" })
                    else
                        network.queueGameEvent("player_set_team", { id = player.id, team = "blue" })
                    end
                    gamedata.mode = "PLAYING"
                elseif e == "char" then
                    if key == "." then
                        if player.alive then
                            gamedata.mode = "PLAYING"
                        else
                            gamedata.mode = "SPECTATING"
                        end
                    elseif key == "," then
                        gamedata.menuMode = "CLASS_SELECT"
                    end
                end
            else
                if e == "mouse_click" then
                    local _, classid = handleMenuClick(x, y)
                    if classid then
                        network.queueGameEvent("player_set_class", { id = player.id, class = classid })
                        gamedata.mode = "SPECTATING"
                    end
                elseif e == "char" then
                    if key == "." then
                        gamedata.menuMode = "TEAM_SELECT"
                    elseif key == "," then
                        if player.alive then
                            gamedata.mode = "PLAYING"
                        else
                            gamedata.mode = "SPECTATING"
                        end
                    end
                end
            end
        end
        if gamedata.mode ~= "MENU" then
            if e == "char" then
                if key == '.' then
                    gamedata.mode = "MENU"
                    gamedata.menuMode = "TEAM_SELECT"
                elseif key == "," then
                    gamedata.mode = "MENU"
                    gamedata.menuMode = "CLASS_SELECT"
                end
            end
        end
    end
end

local callbacks = {}
function gamedata.createCallback(time, func, rep)
    local id = os.startTimer(time)
    callbacks[id] = { func = func, time = time, rep = rep }
    return id
end

function gamedata.callbackHandlers()
    while true do
        local _, id = os.pullEvent("timer")
        local info = callbacks[id]
        if info then
            local nid
            if info.rep then
                nid = gamedata.createCallback(info.time, info.func, info.rep)
            end
            local ret = info.func()
            if info.rep and not ret then
                callbacks[nid] = nil
            end
            callbacks[id] = nil
        end
    end
end

function gamedata.startClientTicking()
    gamedata.createCallback(gamedata.tickTime, function()
        for _, player in pairs(gamedata.players) do
            tickPlayerWeapon(player)
            tickPlayerPolygons(player)
        end
        for i in pairs(gamedata.particles) do
            gamedata.tickParticle(i)
        end
        for i in pairs(gamedata.bullets) do
            gamedata.tickBulletClient(i)
        end
        return true
    end, true)
end

function gamedata.startClientDrawing()
    gamedata.createCallback(gamedata.tickTime, function()
        gamedata.updateViewpos()
        render()
        return true
    end, true)
end

local function tickBulletOnBulletCollisions()
    local remainingBullets = sclone(gamedata.bullets)
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

function gamedata.startServerTicking()
    gamedata.createCallback(gamedata.tickTime, function()
        for _, player in pairs(gamedata.players) do
            gamedata.tickPlayer(player)
        end
        tickBulletOnBulletCollisions()
        for i in pairs(gamedata.bullets) do
            gamedata.tickBulletServer(i)
        end
        return true
    end, true)
end

return gamedata

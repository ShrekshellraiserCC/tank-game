local palette = require "libs.palette"
local shapes = require "libs.shapes"
---@alias TeamID "red"|"blue"

---@class Team
---@field color color
---@field tankTexture Texture

---@type table<TeamID,Team>
local teams = {
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


---@param team TeamID
---@return Player
local function newPlayer(team)
    ---@class Player
    ---@field angle number this is so dumb, WHY
    ---@field velocity number
    ---@field lastFireTime number
    ---@field fireDelay number
    ---@field shotCapacity number
    ---@field shotsRemaining number
    ---@field reloadDelay number
    ---@field lastReloadTime number
    ---@field id integer
    ---@field targetAngle number
    ---@field turretAngle number
    ---@field boosting boolean
    ---@field targetVelocity number
    ---@field poly Polygon
    ---@field turretPoly Polygon
    ---@field team TeamID
    local player = {
        pos = vector.new(30, 30, 0),
        size = vector.new(4, 9, 0),
        turretLength = 8,
        turretSize = vector.new(5, 5, 0),
        color = teams[team].color,
        turretColor = teams[team].color,
        angle = 0,
        targetAngle = 0,
        turretAngle = 0,
        velocity = 0,
        targetVelocity = 0,
        boosting = false,
        maxAcceleration = 0.1,
        boostStats = {
            maxVelocity = 2,
            maxAngleVelocity = 128
        },
        baseStats = {
            maxVelocity = 1,
            maxAngleVelocity = 8,
        },
        lastFireTime = 0,
        fireDelay = 200,
        shotCapacity = 3,
        shotsRemaining = 3,
        reloadDelay = 800,
        lastReloadTime = 0,
        bulletVelocity = 3,
        team = team
    }
    player.poly = shapes.polygon(player.pos, shapes.getRectangleCorners(player.size.x, player.size.y), player.color)
    player.poly.texture = teams[team].tankTexture
    player.poly.angle = player.angle
    player.turretPoly = shapes.polygon(player.pos, shapes.getRectangleCorners(player.turretSize.x, player.turretSize.y),
        player.color)
    player.turretPoly.texture = teams[team].turretTexture
    player.turretPoly.angle = player.turretAngle
    return player
end

return {
    newPlayer = newPlayer,
    teams = teams
}

local pixelbox = require "pixelbox"
local shapes = require "shapes"
local graphics = require "graphics"
local trig = require "trig"

win = window.create(term.current(), 1, 1, term.getSize())
local box = pixelbox.new(win)
graphics.setBox(box)

local friction = 0.99

---@class Player
---@field angle number this is so dumb, WHY
---@field velocity number
---@field lastFireTime number
---@field fireDelay number
---@field shotCapacity number
---@field shotsRemaining number
---@field reloadDelay number
---@field lastReloadTime number
local mainPlayer = {
    pos = vector.new(30, 30, 0),
    size = vector.new(4, 9, 0),
    turretLength = 8,
    turretSize = vector.new(5, 5, 0),
    color = colors.red,
    turretColor = colors.green,
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
    fireDelay = 1,
    shotCapacity = 30,
    shotsRemaining = 3,
    reloadDelay = 1,
    lastReloadTime = 0,
    bulletVelocity = 3,
}

---@class Bullet
---@field pos Vector
---@field vel Vector
---@field remainingBounces integer
---@field health integer
---@field ticksToLive integer

local tw, th = term.getSize()
---@type Polygon[]
local bounds = {}
---@type Bullet[]
local bullets = {}

local function newBullet(pos, velocity)
    ---@class Bullet
    bullets[#bullets + 1] = {
        pos = pos,
        vel = velocity,
        remainingBounces = 1,
        health = 1,
        ticksToLive = 20 * 5,
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


---- COLLISIONS

---@param axis Vector
---@param poly Polygon
---@return number min
---@return number max
local function projectPolygon(axis, poly)
    local pointsVectors = {}
    for i, v in ipairs(poly.points) do
        pointsVectors[i] = vector.new(v.x, v.y, 0)
    end
    local dotProduct = axis:dot(pointsVectors[1])
    local min, max = dotProduct, dotProduct
    for i, v in ipairs(pointsVectors) do
        dotProduct = v:dot(axis)
        min = math.min(min, dotProduct)
        max = math.max(max, dotProduct)
    end
    return min, max
end

local function intervalDistance(minA, maxA, minB, maxB)
    if minA < minB then
        return minB - maxA
    end
    return minA - maxB
end

---@param polyA Polygon
---@param polyB Polygon
---@param velocity Vector
local function polygonCollision(polyA, polyB, velocity)
    local intersect = true
    local willIntersect = true

    collisionChecks = collisionChecks + 1
    local edgeCountA = #polyA.points
    local edgeCountB = #polyB.points
    local minIntervalDistance = math.huge
    local minTranslationVector = vector.new(0, 0, 0)
    local translationAxis = vector.new(0, 0, 0)
    local collisionNormal = vector.new(0, 0, 0)

    local function getEdge(poly, index)
        local currentPoint = poly.points[index]
        local nextPoint = poly.points[(index % #poly.points) + 1]
        return vector.new(nextPoint.x - currentPoint.x, nextPoint.y - currentPoint.y, 0),
            vector.new((nextPoint.y - currentPoint.y), -(nextPoint.x - currentPoint.x), 0)
    end

    for i = 1, edgeCountA + edgeCountB - 1 do
        local edge, normal
        if i <= edgeCountA then
            edge, normal = getEdge(polyA, i)
        else
            edge, normal = getEdge(polyB, i - edgeCountA)
        end

        edgeChecks = edgeChecks + 1

        local axis = vector.new(-edge.y, edge.x, 0)
        axis = axis:normalize()

        local minA, minB, maxA, maxB = 0, 0, 0, 0
        minA, maxA = projectPolygon(axis, polyA)
        minB, maxB = projectPolygon(axis, polyB)

        if intervalDistance(minA, maxA, minB, maxB) > 0 then
            intersect = false -- not currently intersecting
        end

        local velocityProjection = axis:dot(velocity)
        if velocityProjection < 0 then
            minA = minA + velocityProjection
        else
            maxA = maxA + velocityProjection
        end

        local distance = intervalDistance(minA, maxA, minB, maxB)
        if distance > 0 then
            willIntersect = false
        end
        if (not intersect) and (not willIntersect) then
            break
        end

        distance = math.abs(distance)
        if distance < minIntervalDistance then
            minIntervalDistance = distance
            translationAxis = axis
            collisionNormal = normal

            local d = polyA.center - polyB.center
            if d:dot(translationAxis) < 0 then
                translationAxis = translationAxis:unm()
            end
        end
    end
    if willIntersect then
        minTranslationVector = translationAxis * minIntervalDistance
    end
    return {
        willIntersect = willIntersect,
        minimumTranslationVector = minTranslationVector,
        intersect = intersect,
        translationAxis = translationAxis,
        collisionNormal = collisionNormal
    }
end


---- GAME LOGIC

local function createBounds(w, h)
    bounds = {}
    bounds[#bounds + 1] = shapes.polygon(shapes.getRectanglePointsCorner(-2, -2, w + 5, 3), colors.white)
    bounds[#bounds + 1] = shapes.polygon(shapes.getRectanglePointsCorner(-2, -2, 3, h + 5), colors.white)
    bounds[#bounds + 1] = shapes.polygon(shapes.getRectanglePointsCorner(w, -2, 3, h + 5), colors.white)
    bounds[#bounds + 1] = shapes.polygon(shapes.getRectanglePointsCorner(-2, h, w + 5, 3), colors.white)

    bounds[#bounds + 1] = shapes.polygon(shapes.getRectangleCorners(tw, th * 3 / 2, 30, 30), colors.white)
    -- bounds[#bounds + 1] = shapes.polygon(shapes.getCirclePoints(tw, th * 3 / 2, 15, 3), colors.white)
    shapes.debug.logPolygon(bounds[#bounds])
    bounds[#bounds].renderer = shapes.renderers.debugUV
    bounds[#bounds].texture = shapes.loadTexture("test_pattern_16.tex")
    -- bounds[#bounds].renderer = shapes.wireFrameRender
end
createBounds(tw * 2, th * 3)

---@param i integer
local function updateBullet(i)
    local bullet = bullets[i]
    bullet.vel = bullet.vel * friction
    local translation = bullet.vel

    local bulletPoly = shapes.polygon(shapes.getRectanglePointsCorner(bullet.pos.x, bullet.pos.y, 2, 2), colors.white)

    local collision0 = os.epoch(timeunit)
    for _, v in pairs(bounds) do
        if shapes.polyOverlap(bulletPoly, v, 20) then
            local r = polygonCollision(bulletPoly, v, translation)
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
                bullet.remainingBounces = bullet.remainingBounces - 1
            end
        end
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
local function updatePlayer(player)
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

    local playerPoly = shapes.polygon(shapes.getRectangleCorners(player.pos.x, player.pos.y, player.size.x,
        player.size.y, player.angle), colors.white)

    local collision0 = os.epoch(timeunit)
    for _, v in pairs(bounds) do
        if shapes.polyOverlap(playerPoly, v, 20) then
            local r = polygonCollision(playerPoly, v, translation)
            if r.willIntersect then
                translation = translation + r.minimumTranslationVector
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
    shapes.drawRectangle(player.pos.x, player.pos.y, player.size.x, player.size.y, player.color, player.angle, true)
    shapes.drawRectangle(player.pos.x, player.pos.y,
        player.turretSize.x, player.turretSize.y, player.turretColor, player.turretAngle, true)
    graphics.drawAngledLine(player.pos.x, player.pos.y, player.turretLength, player.turretAngle, player.turretColor)
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
    renderPlayer(mainPlayer)
    for _, v in pairs(bounds) do
        shapes.drawPolygon(v)
    end
    for _, v in pairs(bullets) do
        -- local sx, sy = graphics.worldToScreenPos(v.pos.x, v.pos.y)
        -- win.setCursorPos(trig.round(sx / 2), trig.round(sy / 3))
        -- win.setBackgroundColor(colors.black)
        -- win.setTextColor(colors.white)
        -- win.write("*")
        shapes.drawPolygon(shapes.polygon(shapes.getRectanglePointsCorner(v.pos.x, v.pos.y, 2, 2), colors.white))
    end
    box:render()
    shapes.renderers.debugUV(bounds[#bounds], flag)
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
        targetView = (mainPlayer.pos + aimpos) / 2
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
        updatePlayer(mainPlayer)
        for i in pairs(bullets) do
            updateBullet(i)
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
    newBullet(player.pos + ray(player.turretLength, player.turretAngle), ray(player.bulletVelocity, player.turretAngle))
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
            local angle = graphics.calculateAngle(tankposx / 2, tankposy / 3, x, y)
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

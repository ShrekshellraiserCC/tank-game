local network      = {}
local gamedata     = require "libs.gamedata"
local map          = require "libs.map"
local gamesettings = require "libs.gamesettings"

local hostid
local cid          = os.getComputerID()

local PROTOCOL     = "shrekin_tanks"

rednet.open(peripheral.getName(peripheral.find("modem")))

--- It is possible to be both a client and a server (for now)
network.isClient = false
network.isServer = false

--- Event bus concept
---@type {type:string,data:table}[]
local gameEvents = {}

-- Anytime something significant happens it is added to this table
-- Each tick this whole table is evaluated to update the state of the game
-- Clients can send information to the server, for it to then distribute

local function queueGameEventRaw(type, t)
    gameEvents[#gameEvents + 1] = { type = type, data = t }
    os.queueEvent("game_event")
end

local function sendGameEventToServer(type, t)
    rednet.send(hostid, { type = "game_event", event = type, data = t }, PROTOCOL)
end

---@type table<integer,{username:string,lastMessage:number}>
local connectedClients = {}

local function sendGameEventToClients(type, t)
    rednet.broadcast({ type = "game_event", event = type, data = t }, PROTOCOL)
end

local function vectorize(t)
    return vector.new(t.x, t.y, 0)
end

local validClientCreatedEvents = {
    player_movement_update = true,
    player_fire_shot = true,
    player_aim = true,
    player_set_team = true,
    player_set_class = true
}

local clientGameEventHandlers = {
    -- Events created by client
    player_movement_update = function(d)
        local player = gamedata.players[d.id]
        player.targetAngle = d.targetAngle
        player.targetVelocity = d.targetVelocity
        player.boosting = d.boosting
        player.pos = vectorize(d.pos)
        player.angle = d.angle
        player.velocity = d.velocity
    end,
    player_fire_shot = function(d)
        local player = gamedata.players[d.id]
        player.turretAngle = d.angle
        gamedata.fire(d.bid, player)
    end,
    player_aim = function(d)
        local player = gamedata.players[d.id]
        player.turretAngle = d.angle
    end,
    player_set_team = function(d)
        local player = gamedata.players[d.id]
        gamedata.setPlayerTeam(player, d.team)
        if player.alive then
            gamedata.killPlayer(player)
        end
    end,
    player_set_class = function(d)
        local player = gamedata.players[d.id]
        gamedata.setPlayerClass(player, d.class)
        if player.alive then
            gamedata.killPlayer(player)
        end
    end,
    -- Events created by server
    bullet_bounce = function(d)
        local bullet = gamedata.bullets[d.id]
        bullet.pos = vector.new(d.x, d.y, 0)
        bullet.vel = vector.new(d.vx, d.vy, 0)
    end,
    bullet_destroy = function(d)
        if gamedata.bullets[d.id] then
            gamedata.explosion(gamedata.bullets[d.id].pos)
        end
        gamedata.bullets[d.id] = nil
    end,
    player_join = function(d)
        gamedata.newPlayer(d.id, d.name)
        network.queueGameEvent("player_set_team", { id = d.id, team = gamedata.getUnbalancedTeam() })
        network.queueGameEvent("player_set_class", { id = d.id, class = "base" })
        network.queueGameEvent("player_respawn", { id = d.id })
    end,
    player_respawn = function(d)
        local player = gamedata.players[d.id]
        gamedata.respawnPlayer(player)
    end,
    player_died = function(d)
        local player = gamedata.players[d.id]
        if cid == d.id then
            if d.bid then
                gamedata.mode = "KILL_CAM"
            else
                gamedata.mode = "SPECTATING"
            end
        end
        player.willRespawnAt = player.willRespawnAt or d.willRespawnAt
        if player.alive then
            player.alive = false
            gamedata.explosion(player.pos)
            player.deaths = player.deaths + 1
            player.velocity = 0
        end
        if d.bid and gamedata.bullets[d.bid] then
            local owner = gamedata.bullets[d.bid].owner
            gamedata.killer = gamedata.players[owner]
            player.spectating = owner
            gamedata.bullets[d.bid] = nil
        end
    end,
    game_tick = function(d)
        if d.players then
            for _, v in ipairs(d.players) do
                local player = gamedata.players[v.id]
                player.pos = vectorize(v.pos)
                player.angle = v.angle
            end
        end
        if d.bullets then
            for _, v in ipairs(d.bullets) do
                gamedata.newBullet(v.id, v.owner, vectorize(v.pos), vectorize(v.vel))
                -- local bullet = gamedata.bullets[v.id]
                -- bullet.pos = vectorize(v.pos)
            end
        end
    end
}

---@param type string
---@param t table
function network.queueGameEvent(type, t)
    if network.isClient then
        sendGameEventToServer(type, t)
    end
    if network.isServer then
        -- queueGameEventRaw(type, t)
        sendGameEventToClients(type, t)
        -- if validClientCreatedEvents[type] then
        clientGameEventHandlers[type](t)
        -- end
    end
end

network.lastMessage = 0
local function clientConnection()
    while true do
        local sender, message = rednet.receive(PROTOCOL, 1)
        if sender == hostid and type(message) == 'table' then
            network.lastMessage = os.epoch("utc")
            if message.type == "game_event" then
                queueGameEventRaw(message.event, message.data)
            elseif message.type == "game_event_bundle" then
                for i, v in ipairs(message.data) do
                    queueGameEventRaw(v.type, v.data)
                end
            end
        elseif not sender and network.lastMessage + gamesettings.clientTimeout <= os.epoch("utc") then
            -- timeout
            return
        end
    end
end

---@param player Player
local function serializePlayer(player)
    local splayer = {}
    for k, v in pairs(player) do
        splayer[k] = v
    end
    splayer.poly = nil
    splayer.turretPoly = nil
    splayer.color = nil
    splayer.turretColor = nil
    splayer.turretSize = nil
    splayer.size = nil
    splayer.baseStats = nil
    splayer.boostStats = nil
    splayer.classValid = nil
    splayer.teamValid = nil

    return splayer
end

---@return Player
local function unserializePlayer(splayer)
    local player = {}
    for k, v in pairs(splayer) do
        player[k] = v
    end
    player.pos = vectorize(splayer.pos)
    if player.team then
        gamedata.setPlayerTeam(player, player.team)
    end
    if player.class then
        gamedata.setPlayerClass(player, player.class)
    end
    return player
end

local function serializePlayers()
    local splayers = {}
    for i, player in pairs(gamedata.players) do
        splayers[i] = serializePlayer(player)
    end
    return splayers
end

local serverEventHandlers = {
    player_fire_shot = function(d)
        d.bid = #gamedata.bullets + 1
        -- local player = gamedata.players[d.id]
        -- player.turretAngle = d.angle
        -- d.pos = player.pos + gamedata.ray(player.turretLength, player.turretAngle)
        -- d.vel = gamedata.ray(player.weapon.bulletVelocity, player.turretAngle) +
        --     gamedata.ray(player.velocity, player.angle + 90)
    end,
    player_movement_update = function(d)
        local player = gamedata.players[d.id]
        d.pos = player.pos
        d.velocity = player.velocity
        d.angle = player.angle
    end
}

---@param sender integer
---@param message table
local function serverHandleMessage(sender, message)
    if connectedClients[sender] then
        connectedClients[sender].lastMessage = os.epoch('utc')
        if message.type == "game_event" and validClientCreatedEvents[message.event] then
            if serverEventHandlers[message.event] then
                serverEventHandlers[message.event](message.data)
            end
            network.queueGameEvent(message.event, message.data)
        end
    end
    if message.type == "join" then
        print("Client connected")
        connectedClients[sender] = {
            username = message.username,
            lastMessage = os.epoch('utc')
        }
        gamedata.newPlayer(sender, message.username)
        rednet.send(sender, {
            type = "join",
            state = true,
            players = serializePlayers(),
            map = gamedata.mapData,
            bullets = gamedata.bullets,
        }, PROTOCOL)
        network.queueGameEvent("player_join", { id = sender, name = message.username })
    end
end

local tickNumber = 0
local lastSentTickTime = 0
local function serverTick()
    while true do
        sleep(gamedata.tickTime)
        local updatedPlayers = {}
        for _, player in pairs(gamedata.players) do
            if player.velocity ~= 0 then
                updatedPlayers[#updatedPlayers + 1] = {
                    id = player.id,
                    pos = player.pos,
                    angle = player.angle
                }
            end
        end
        local updatedBullets = {}
        for _, bullet in pairs(gamedata.bullets) do
            updatedBullets[#updatedBullets + 1] = {
                id = bullet.id,
                owner = bullet.owner,
                pos = bullet.pos,
                vel = bullet.vel
            }
        end
        local tickInfo = {}
        local substancialTick = false
        if #updatedPlayers > 0 then
            tickInfo.players = updatedPlayers
            substancialTick = true
        end
        if #updatedBullets > 0 then
            tickInfo.bullets = updatedBullets
            substancialTick = true
        end
        local needHeartbeat = os.epoch("utc") >= lastSentTickTime + gamesettings.heartbeat
        if substancialTick or needHeartbeat then
            tickNumber = tickNumber + 1
            if tickNumber % gamesettings.interpolation == 0 or needHeartbeat then
                sendGameEventToClients("game_tick", tickInfo)
                lastSentTickTime = os.epoch("utc")
            end
        end
    end
end

local serverHostname
local function serverConnection()
    rednet.host(PROTOCOL, serverHostname)
    print("Server started.")
    while true do
        local sender, message = rednet.receive(PROTOCOL)
        if type(message) == 'table' then
            serverHandleMessage(sender --[[@as number]], message)
        end
    end
end

local function clientGameEventHandler()
    while true do
        os.pullEvent("game_event")
        local event = table.remove(gameEvents, 1)
        assert(clientGameEventHandlers[event.type], ("Invalid event %s"):format(event.type))(event.data)
    end
end

local function connectToServer(username)
    print("Attempting to connect.")
    rednet.send(hostid, { type = "join", username = username }, PROTOCOL)
    while true do
        local sender, message = rednet.receive(PROTOCOL, 2)
        if sender == nil then
            return false
        elseif sender == hostid and type(message) == "table" and message.type == "join" then
            gamedata.players = {}
            for k, v in pairs(message.players) do
                gamedata.players[k] = unserializePlayer(v)
                print("Found player", k)
            end
            gamedata.mapData = message.map
            gamedata.map = map.loadMap(message.map)
            return message.state
        end
    end
end

---@param server integer?
---@param username string
function network.startClient(username, server)
    network.isClient = true
    if server then
        hostid = server
    else
        print("Looking up servers...")
        local servers = { rednet.lookup(PROTOCOL) }
        hostid = servers[1]
        print("Found", hostid)
    end
    assert(connectToServer(username), "Failed to connect to server")
    gamedata.startClientTicking()
    gamedata.startClientDrawing()
    parallel.waitForAny(clientGameEventHandler, clientConnection, gamedata.inputLoop, gamedata.callbackHandlers)
end

---@param hostname string
function network.startServer(hostname)
    network.isServer = true
    serverHostname = hostname
    gamedata.startServerTicking()
    parallel.waitForAny(serverConnection, serverTick, gamedata.callbackHandlers)
end

return network

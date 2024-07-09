local network  = {}
local gamedata = require "libs.gamedata"
local map      = require "libs.map"


local hostid
local cid      = os.getComputerID()

local PROTOCOL = "shrekin_tanks"

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
    player_aim = true
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
        gamedata.fire(player, vectorize(d.pos), vectorize(d.vel))
    end,
    player_aim = function(d)
        local player = gamedata.players[d.id]
        player.turretAngle = d.angle
    end,
    -- Events created by server
    bullet_bounce = function(d)
        local bullet = gamedata.bullets[d.id]
        bullet.pos = vector.new(d.x, d.y, 0)
        bullet.vel = vector.new(d.vx, d.vy, 0)
    end,
    player_join = function(d)
        gamedata.newPlayer(d.id)
    end,
    player_respawn = function(d)
        local player = gamedata.players[d.id]
        gamedata.respawnPlayer(player)
    end,
    player_change_team = function(d)
        local player = gamedata.players[d.id]
        gamedata.setPlayerTeam(player, d.team)
    end,
    player_die = function(d)

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

local function clientConnection()
    while true do
        local sender, message = rednet.receive(PROTOCOL, 5)
        if sender == hostid and type(message) == 'table' then
            if message.type == "game_event" then
                queueGameEventRaw(message.event, message.data)
            elseif message.type == "game_event_bundle" then
                for i, v in ipairs(message.data) do
                    queueGameEventRaw(v.type, v.data)
                end
            end
        elseif not sender then
            -- timeout
            -- return
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
    player.color = nil
    player.turretColor = nil

    return splayer
end

---@return Player
local function unserializePlayer(splayer)
    local player = {}
    for k, v in pairs(splayer) do
        player[k] = v
    end
    player.pos = vectorize(splayer.pos)
    player.size = vectorize(splayer.size)
    if player.team then
        gamedata.createPlayerPolys(player)
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
        gamedata.newPlayer(sender)
        rednet.send(sender, {
            type = "join",
            state = true,
            players = serializePlayers()
        }, PROTOCOL)
        network.queueGameEvent("player_join", { id = sender })
        network.queueGameEvent("player_change_team", { id = sender, team = sender == 2 and "red" or "blue" })
        network.queueGameEvent("player_respawn", { id = sender })
    end
end

local function serverTick()
    while true do
        sleep(gamedata.tickTime)
        if #gameEvents > 1 then
            rednet.broadcast({ type = "game_event_bundle", data = gameEvents }, PROTOCOL)
            gameEvents = {}
        elseif #gameEvents == 1 then
            local event = gameEvents[1]
            rednet.broadcast({ type = "game_event", event = event.type, data = event.data }, PROTOCOL)
            gameEvents = {}
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
    parallel.waitForAny(clientGameEventHandler, clientConnection, gamedata.gameLoop, gamedata.inputLoop)
end

---@param hostname string
function network.startServer(hostname)
    network.isServer = true
    serverHostname = hostname
    parallel.waitForAny(serverConnection, gamedata.gameLoop)
end

return network

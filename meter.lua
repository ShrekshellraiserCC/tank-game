local function countSize(t)
    local size = 0
    if type(t) == "string" then
        size = #t
    elseif type(t) == "table" then
        for k, v in pairs(t) do
            size = size + countSize(v)
        end
    elseif type(t) == "number" then
        size = 8
    elseif type(t) == "boolean" then
        size = 1
    else
        error(("Unsupported type %s"):format(type(t)))
    end
    return size
end

---@alias MessageEntry {epoch:number,size:number}
---@type MessageEntry[]
local entries = {}
local function log(message)
    table.insert(entries, 1, { size = countSize(message), epoch = os.epoch("utc") })
end
---@type MessageEntry[]
local messagesLast30Secs = {}
---@type MessageEntry[]
local messagesLast5Secs = {}
---@type MessageEntry[]
local messagesLastSec = {}
---@param entries MessageEntry[]
---@return number min
---@return number max
---@return number ave
---@return number total
local function calculateInfo(entries)
    local min, max, sum = math.huge, 0, 0
    local trueSize = #entries
    if #entries == 0 then
        entries[1] = { size = 0 }
    end
    for k, v in ipairs(entries) do
        if v.size > max then
            max = v.size
        end
        if v.size < min then
            min = v.size
        end
        sum = sum + v.size
    end
    return min, max, math.floor(sum / #entries), sum
end

local function calculate()
    messagesLast30Secs = {}
    messagesLast5Secs = {}
    messagesLastSec = {}
    local t = os.epoch("utc")
    local toremove = {}
    for k, v in ipairs(entries) do
        if v.epoch + 1000 >= t then
            table.insert(messagesLastSec, v)
            table.insert(messagesLast5Secs, v)
            table.insert(messagesLast30Secs, v)
        elseif v.epoch + 5000 >= t then
            table.insert(messagesLast5Secs, v)
            table.insert(messagesLast30Secs, v)
        elseif v.epoch + 30000 >= t then
            table.insert(messagesLast30Secs, v)
        else
            toremove[#toremove + 1] = k
        end
    end
    for i = #toremove, 1, -1 do
        local rem = toremove[i]
        table.remove(entries, rem)
    end
    print(("    |Count|Min  |Max  |Ave  |Total"))
    print(("1s  |%5d|%5d|%5d|%5d|%5d"):format(#messagesLastSec, calculateInfo(messagesLastSec)))
    print(("5s  |%5d|%5d|%5d|%5d|%5d"):format(#messagesLast5Secs, calculateInfo(messagesLast5Secs)))
    print(("30s |%5d|%5d|%5d|%5d|%5d"):format(#messagesLast30Secs, calculateInfo(messagesLast30Secs)))
end
rednet.open("top")
while true do
    local _, _, _, _, message = os.pullEvent("modem_message")
    log(message)
    term.clear()
    term.setCursorPos(1, 1)
    calculate()
end

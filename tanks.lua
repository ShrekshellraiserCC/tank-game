local pixelbox = require "libs.pixelbox"
local graphics = require "libs.graphics"
local palette  = require "libs.palette"
local gamedata = require "libs.gamedata"
local network  = require "libs.gamenetwork"

local win      = window.create(term.current(), 1, 1, term.getSize())
local box      = pixelbox.new(win)
graphics.setBox(box)


palette.apply(win)

gamedata.setupRendering(win, box)

local ok, err = xpcall(function()
    if arg[1] == "server" then
        network.startServer("pleasework")
    else
        print("Please enter a username: ")
        network.startClient(read() --[[@as string]])
    end
end, debug.traceback)

term.clear()
term.setCursorPos(1, 1)
if not ok then
    print(err)
end

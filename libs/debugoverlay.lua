local profile = {}

profile.timeunit = "utc"
profile.timelabel = "ms"
profile.enableOverlay = false

---@type {str:string,values:any[]}[]
local menuEntries = {}
local menuStrLut = {}
function profile.set(str, ...)
    local i = menuStrLut[str] or #menuEntries + 1
    menuStrLut[str] = i
    menuEntries[i] = { str = str, values = table.pack(...) }
end

profile.set("DEBUG")
function profile.display(win)
    if profile.enableOverlay then
        for i, v in ipairs(menuEntries) do
            win.setCursorPos(1, i)
            win.write(v.str:format(table.unpack(v.values)))
        end
    end
end

return profile

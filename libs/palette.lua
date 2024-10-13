local palette = {}

local newPalette = {
    white = 0xffffff,     -- 0

    blue = 0x0f35db,      -- b
    blueShade = 0x0A238F, -- 9
    red = 0xa30000,       -- e
    redShade = 0x730707,  -- 6
    black = 0,            -- f
}
---@class colorDefinition
palette.colors = {
    white = colors.white,    -- 0

    blueShade = colors.cyan, -- 9
    redShade = colors.pink,  -- 6
    blue = colors.blue,      -- b
    red = colors.red,        -- e
    black = colors.black,    -- f
}

---@param win Window
function palette.dump(win)
    local ct = {}
    for i = 0, 15 do
        local c = 2 ^ i
        local r, g, b = win.getPaletteColor(c)
        ct[i + 1] = { math.floor(r * 255), math.floor(g * 255), math.floor(b * 255) }
    end
    local f = assert(fs.open("palette.pal", "w"))
    f.write(textutils.serialiseJSON(ct))
    f.close()
end

function palette.apply(win)
    for k, v in pairs(palette.colors) do
        win.setPaletteColor(v, newPalette[k])
    end
end

return palette

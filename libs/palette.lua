local newPalette = {
    white = 0xffffff,     -- 0

    blue = 0x0f35db,      -- b
    blueShade = 0x1430a8, -- 9
    red = 0xa30000,       -- e
    redShade = 0x730707,  -- 6
    black = 0,            -- f
}
---@class colorDefinition
local colorlut = {
    white = colors.white,    -- 0

    blueShade = colors.cyan, -- 9
    redShade = colors.pink,  -- 6
    blue = colors.blue,      -- b
    red = colors.red,        -- e
    black = colors.black,    -- f
}

local function apply(win)
    for k, v in pairs(colorlut) do
        win.setPaletteColor(v, newPalette[k])
    end
end

return {
    colors = colorlut,
    apply = apply
}
local sidebar = {}

local padding = 1
local startY = 3

---@class SidebarEntry
---@field type string
---@field label string
---@field height integer
---@field indicies string[]
---@field y integer

---@class SidebarInput:SidebarEntry
---@field type "input"
---@field cursor integer?
---@field number boolean?
---@field cursorWin integer?
---@field min integer?
---@field max integer?

---@class SidebarDropdown:SidebarEntry
---@field type "dropdown"
---@field options string[]

---@param label string
---@return SidebarInput
function sidebar.label(label)
    local entry = {}
    entry.type = "label"
    entry.label = label
    entry.indicies = {}
    entry.height = 1
    return entry
end

---@param label string
---@param ... any
---@return SidebarInput
function sidebar.input(label, ...)
    local entry = {}
    entry.type = "input"
    entry.label = label
    entry.indicies = table.pack(...)
    entry.height = 2
    entry.cursor = 1
    return entry
end

---@param label string
---@param options {min:integer?,max:integer?}?
---@param ... any
---@return SidebarInput
function sidebar.numberInput(label, options, ...)
    local entry = sidebar.input(label, ...)
    entry.number = true
    options = options or {}
    entry.min = options.min
    entry.max = options.max
    return entry
end

---@param label string
---@param options string[]
---@param ... any
---@return SidebarDropdown
function sidebar.dropdown(label, options, ...)
    local entry = {}
    entry.type = "dropdown"
    entry.label = label
    entry.indicies = table.pack(...)
    entry.options = options
    entry.height = 2
    return entry
end

local fg, bg = colors.white, colors.gray
local hfg, hbg = colors.black, colors.white
local mfg, mbg = colors.black, colors.lightGray

---@param dev Window
---@param fg color?
---@param bg color?
---@return color
---@return color
local function color(dev, fg, bg)
    local ofg = dev.getTextColor()
    local obg = dev.getBackgroundColor()
    dev.setTextColor(fg or ofg)
    dev.setBackgroundColor(bg or obg)
    return ofg, obg
end

---Index into a given entry
---@param bar Sidebar
---@param entry SidebarEntry
local function index(bar, entry)
    local value = bar.data
    for _, v in ipairs(entry.indicies) do
        if not value then break end
        value = value[v]
    end
    return value
end

---Index into a given entry and set its value
---@param bar Sidebar
---@param entry SidebarEntry
local function setIndex(bar, entry, val)
    local value = bar.data
    for i = 1, #entry.indicies - 1 do
        value = value[entry.indicies[i]]
    end
    value[entry.indicies[#entry.indicies]] = val
    bar.onUpdate(bar.data)
end

local renderers = {
    ---@param win Window
    ---@param y number
    ---@param entry SidebarInput
    ---@param bar Sidebar
    input = function(win, y, entry, bar)
        local w, h = win.getSize()
        local tw = w - 3
        win.setCursorPos(3, y + 1)
        color(win, hfg, hbg)
        win.write((" "):rep(tw))
        win.setCursorPos(3, y + 1)
        local val = index(bar, entry)
        local sval = tostring(val)
        entry.cursor = math.min(entry.cursor, #sval + 1)
        local valx = math.max(1, entry.cursor - tw + 1)
        win.write(sval:sub(valx, valx + tw - 1))
        if bar.selected == entry then
            local x = math.min(tw, entry.cursor)
            entry.cursorWin = x
        end
    end,
    ---@param win Window
    ---@param y number
    ---@param entry SidebarDropdown
    ---@param bar Sidebar
    dropdown = function(win, y, entry, bar)
        local w, h = win.getSize()
        local tw = w - 3
        win.setCursorPos(3, y + 1)
        color(win, hfg, hbg)
        win.write((" "):rep(tw))
        win.setCursorPos(3, y + 1)
        local val = index(bar, entry)
        win.write(val)
        win.setCursorPos(tw + 2, y + 1)
        color(win, fg, bg)
        local ch = bar.selected == entry and "\30" or "\31"
        win.write(ch)
        if bar.selected == entry then
            for i, v in ipairs(entry.options) do
                win.setCursorPos(3, y + i + 1)
                win.write((" "):rep(tw))
                win.setCursorPos(3, y + i + 1)
                win.write(v)
            end
        end
    end
}

---@param win Window
---@param y number
---@param entry SidebarEntry
---@param bar Sidebar
local function renderEntry(win, y, entry, bar)
    local ofg, obg = color(win, mfg, mbg)
    entry.y = y
    win.setCursorPos(3, y)
    win.write(entry.label)
    if renderers[entry.type] then
        ---@diagnostic disable-next-line: param-type-mismatch
        renderers[entry.type](win, y, entry, bar)
    end
    color(win, ofg, obg)
end

local function clamp(n, min, max)
    return math.min(math.max(n or min or 0, min or -math.huge), max or math.huge)
end

local entryEventHandlers = {
    input = {
        char = function(bar, ch)
            local sinput = bar.selected --[[@as SidebarInput]]
            ---@type string|number
            local sval = tostring(index(bar, sinput))
            if sinput.number then
                if not tonumber(ch) then return end
            end
            sval = sval:sub(1, sinput.cursor) .. ch .. sval:sub(sinput.cursor + 1)
            sinput.cursor = sinput.cursor + 1
            if sinput.number then
                sval = clamp(tonumber(sval), sinput.min, sinput.max)
            end
            setIndex(bar, sinput, sval)
        end,
        key = function(bar, key)
            local sinput = bar.selected --[[@as SidebarInput]]
            ---@type string|number
            local sval = tostring(index(bar, sinput))
            if key == keys.backspace then
                sval = sval:sub(1, sinput.cursor - 2) .. sval:sub(sinput.cursor)
                sinput.cursor = math.max(1, sinput.cursor - 1)
                setIndex(bar, sinput, clamp(tonumber(sval), sinput.min, sinput.max))
            elseif key == keys.left then
                sinput.cursor = math.max(1, sinput.cursor - 1)
            elseif key == keys.right then
                sinput.cursor = math.min(#sval + 1, sinput.cursor + 1)
            end
        end,
        ---@param bar Sidebar
        ---@param entry SidebarInput
        ---@param button number
        ---@param x number
        ---@param y number
        ---@return boolean?
        click = function(bar, entry, button, x, y)
            if y == entry.y + 1 then
                bar.selected = entry
                entry.cursor = #tostring(index(bar, entry)) + 1
                return true
            end
        end
    },
    dropdown = {
        ---@param bar Sidebar
        ---@param entry SidebarDropdown
        ---@param button number
        ---@param x number
        ---@param y number
        ---@return boolean?
        click = function(bar, entry, button, x, y)
            if y == entry.y + 1 then
                bar.selected = entry
                return true
            elseif bar.selected == entry then
                if y > entry.y + 1 and y < entry.y + 2 + #entry.options then
                    setIndex(bar, entry, entry.options[y - entry.y - 1])
                    return true
                end
            end
        end
    }
}

local eventHandlers = {
    mouse_click = function(bar, button, x, y)
        local tw, th = bar.parentWin.getSize()
        local toggleX = tw
        if bar.active then
            toggleX = tw - bar.width
        end
        if x == toggleX then
            bar.active = not bar.active
            return true
        end
        if not bar.active then return false end
        if x < toggleX then
            bar.selected = nil
            return false
        end

        if bar.selected then
            if entryEventHandlers[bar.selected.type] and entryEventHandlers[bar.selected.type].click then
                if entryEventHandlers[bar.selected.type].click(bar, bar.selected, button, x, y) then
                    return true
                end
            end
        end
        local py = startY
        for i, v in ipairs(bar.scheme) do
            if v ~= bar.selected then
                if entryEventHandlers[v.type] and entryEventHandlers[v.type].click then
                    if entryEventHandlers[v.type].click(bar, v, button, x, y) then
                        return true
                    end
                end
            end
            py = py + v.height + padding
        end

        bar.selected = nil
        return true
    end,
    char = function(bar, ch)
        local selected = bar.selected
        if selected then
            if entryEventHandlers[selected.type] then
                entryEventHandlers[selected.type].char(bar, ch)
            end
            return true
        end
    end,
    key = function(bar, code)
        local selected = bar.selected
        if selected then
            if entryEventHandlers[selected.type] then
                entryEventHandlers[selected.type].key(bar, code)
            end
            return true
        end
    end,
    mouse_scroll = function(bar, dir, x, y)
        local selected = bar.selected
        if selected then
            if selected.type == "input" then
                local sinput = selected --[[@as SidebarInput]]
                local value = index(bar, sinput) or 0
                setIndex(bar, sinput,
                    math.max(math.min(value - dir, selected.max or math.huge), selected.min or -math.huge))
            end
            return true
        end
    end
}

---@param parentWin Window
---@param width number
---@return Sidebar
function sidebar.new(parentWin, width)
    ---@class Sidebar
    ---@field selected SidebarEntry?
    local bar = {}
    bar.width = width
    bar.parentWin = parentWin
    bar.active = false
    bar.scheme = {}
    do
        local tw, th = parentWin.getSize()
        bar.win = window.create(parentWin, tw, 1, width + 1, th)
        bar.lpos = tw
    end

    ---@param scheme SidebarEntry[]
    ---@generic T:table
    ---@param data T
    ---@param onUpdate fun(data: T)
    function bar.update(scheme, data, onUpdate)
        if scheme ~= bar.scheme then
            bar.selected = nil
        end
        bar.scheme = scheme
        bar.data = data
        bar.onUpdate = onUpdate
    end

    function bar.render()
        local win = bar.win
        local tw, th = parentWin.getSize()
        if bar.active then
            bar.lpos = tw - width
        else
            bar.lpos = tw
        end
        win.reposition(bar.lpos, 1)
        local ofg, obg = color(win, mfg, mbg)
        win.clear()
        local selY
        local y = startY
        for i, v in ipairs(bar.scheme) do
            if v == bar.selected then
                selY = y
            else
                renderEntry(win, y, v, bar)
            end
            y = y + v.height + padding
        end
        if selY then
            renderEntry(win, selY, bar.selected, bar)
        end
        color(win, fg, bg)
        local arrowCh = bar.active and "\26" or "\27"
        local third = math.ceil(th / 3)
        for dy = 1, th do
            win.setCursorPos(1, dy)
            if dy >= third and dy <= third * 2 then
                win.write(arrowCh)
            else
                win.write(" ")
            end
        end
        win.setVisible(true)
        win.setVisible(false)
        color(win, ofg, obg)
    end

    ---@param win Window parent window that contains the bar
    function bar.showCursor(win)
        local selected = bar.selected
        if selected and selected.type == "input" then
            local input = selected --[[@as SidebarInput]]
            color(win, hfg, hbg)
            win.setCursorBlink(true)
            win.setCursorPos(input.cursorWin + bar.lpos + 1, input.y + 1)
        end
    end

    ---@param e table
    ---@return boolean consumed
    function bar.onEvent(e)
        if eventHandlers[e[1]] then
            return eventHandlers[e[1]](bar, table.unpack(e, 2, e.n))
        end
        return false
    end

    return bar
end

return sidebar

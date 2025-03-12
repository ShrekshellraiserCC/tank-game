local fakebox = {}

---@param terminal term|Window
function fakebox.new(terminal)
    local fb = {}
    local tw, th = terminal.getSize()
    local win = window.create(terminal, 1, 1, tw, th, false)
    function fb:clear(color)
        win.setBackgroundColor(color)
        win.clear()
    end

    function fb:set_pixel(x, y, color)
        win.setBackgroundColor(color)
        win.setCursorPos(x, y)
        win.write(" ")
    end

    function fb:resize(w, h, color)
        if color then
            win.setBackgroundColor(color)
        end
        win.reposition(1, 1, w, h)
    end

    function fb:render()
        win.setVisible(true)
        win.setVisible(false)
    end

    return fb
end

return fakebox

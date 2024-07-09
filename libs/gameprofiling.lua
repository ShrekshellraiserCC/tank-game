local profile = {}

profile.collisionChecks = 0
profile.edgeChecks = 0
profile.collisiondt = 0
profile.framedt = 0
profile.totaldt = 0
profile.renderdt = 0
profile.frameCount = 0
profile.totalRenderDt = 0
profile.totalCollisionDt = 0
profile.timeunit = "utc"
profile.timelabel = "ms"
profile.enableOverlay = false

function profile.display(win)
    if profile.enableOverlay then
        win.setCursorPos(1, 1)
        win.write(("Frame %d"):format(profile.frameCount))
        win.setCursorPos(1, 2)
        win.write(("collisionChecks %d"):format(profile.collisionChecks))
        win.setCursorPos(1, 3)
        win.write(("edgeChecks %d"):format(profile.edgeChecks))
        win.setCursorPos(1, 4)
        win.write(("render dt %d%s (ave %.2f%s)"):format(profile.renderdt, profile.timelabel,
            profile.totalRenderDt / profile.frameCount, profile.timelabel))
        win.setCursorPos(1, 5)
        win.write(("collision dt %d%s (ave %.2f%s)"):format(profile.collisiondt, profile.timelabel,
            profile.totalCollisionDt / profile.frameCount,
            profile.timelabel))
        win.setCursorPos(1, 6)
        win.write(("frame dt %d%s | %.2fFPS (ave %.2f%s | %.2fFPS)"):format(profile.framedt, profile.timelabel,
            1 / (profile.framedt / 1000), profile.totaldt / profile.frameCount, profile.timelabel,
            1 / (profile.totaldt / 1000 / profile.frameCount)))
    end
end

return profile

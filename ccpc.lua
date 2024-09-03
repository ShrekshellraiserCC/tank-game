---@meta

periphemu = {}

---@param side string
---@param type string
---@param path string?
---@return boolean
function periphemu.create(side, type, path) end

---@param side string
---@return boolean
function periphemu.remove(side) end

---@return string[]
function periphemu.names() end

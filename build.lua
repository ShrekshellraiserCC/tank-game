-- Very simple Lua program packager.
-- This program takes in a single filename, your entry point.
-- Then it will scan that program for all of its requires, and all of its require-es requires.
-- After doing this for all required files it packages them up into a single file.

-- There are a few special rules you MUST follow for this program to work
-- 1) The FIRST line of ALL files you import must be an initialization of your module's table.
--- For example, `local data = {}`
--- 1.a) This variable name MUST be the same variable name used everywhere this module is.
-- 2) The LAST code line of your file MUST be a return, returning this module table.
--- For example, `return data`
-- 3) EVERYWHERE a file is imported it MUST be imported using the same module name AND variable name.

if #arg < 2 then
    print("Usage: build input output")
    return
end

local inputfn = arg[1]
local outputfn = arg[2]

local matchRequireStr = "local ([%a_%d]+) *= *require%(? *['\"]([%a%d%p]+)['\"]%)?"
local matchReturnStr = "^return ([%a_%d]+)"

local fileCacheStr = "(.+= *)map.readFile%(\"([%a%d%p]+)\"%)"

---@class RequiredFile
---@field variable string
---@field module string
---@field filename string
---@field content string
---@field firstline string
---@field requires table<string,string> module,module

---@type RequiredFile[]
local requiredFiles = {}

---@type table<string,RequiredFile>
local moduleLUT = {}

---@type table<string,RequiredFile>
local filenameLUT = {}

local function moduleToFilename(module)
    return module:gsub("%.", "/") .. ".lua"
end

---@type string[]
local toProcess = {}

filenameLUT[inputfn] = {
    requires = {},
    filename = inputfn,
    content = "",
    firstline = "",
    module = "",
    variable = "",
}

---@param byfn string
---@param var string
---@param module string
local function requireFile(byfn, var, module)
    if filenameLUT[byfn] then
        filenameLUT[byfn].requires[module] = module
    end
    if moduleLUT[module] then
        assert(moduleLUT[module].variable == var,
            ("Module %s imported by two different names [%s,%s]."):format(module, moduleLUT[module].variable, var))
        return
    end
    local fn = moduleToFilename(module)
    local required = {
        variable = var,
        module = module,
        filename = fn,
        requires = {}
    }
    requiredFiles[#requiredFiles + 1] = required
    moduleLUT[module] = required
    filenameLUT[fn] = required
    toProcess[#toProcess + 1] = fn
end

local function readFile(fn)
    local f = assert(fs.open(fn, "r"))
    local s = f.readAll()
    f.close()
    return s
end

local function processFile(fn, specialCase)
    local output = ""
    local f = assert(fs.open(fn, "r"))
    local s = f.readLine(true)
    local firstline = nil
    if not specialCase then
        firstline = s
        s = f.readLine(true)
    end
    local foundReturn = false
    while s do
        local var, module = s:match(matchRequireStr)
        local cachedVar, cacheFn = s:match(fileCacheStr)
        if var and module then
            requireFile(fn, var, module)
        elseif cachedVar and cacheFn then
            output = output .. cachedVar .. textutils.serialize(readFile(cacheFn)) .. "\n"
        elseif not s:match(matchReturnStr) then
            output = output .. s
        end
        foundReturn = s:match(matchReturnStr)
        s = f.readLine(true)
    end
    f.close()
    if not specialCase then
        assert(foundReturn, ("Did not find a return statement at the end of %s."):format(fn))
    end
    return firstline, output
end

local moduleIncludeOrder = {}

-- https://en.wikipedia.org/wiki/Topological_sorting#Depth-first_search
---@param module RequiredFile
local function visit(module)
    if module.permanant then
        return
    elseif module.temporary then
        print("Warning: Cyclic dependency tree")
        print("This may or may not be a problem.")
        return
    end
    module.temporary = true

    for mod, info in pairs(module.requires) do
        local depModule = moduleLUT[mod]
        if depModule then
            visit(depModule)
        elseif not depModule.optional then
            error(("Module %s requires %s, which is not present."):format(module.filename, depModule.filename))
        end
    end

    module.temporary = nil
    module.permanant = true
    table.insert(moduleIncludeOrder, module)
end

local function getUnmarked()
    for k, v in pairs(requiredFiles) do
        if not v.permanant then
            return v
        end
    end
    return nil
end

local unmarked = getUnmarked()
while unmarked do
    visit(unmarked)
    unmarked = getUnmarked()
end

for k, v in pairs(requiredFiles) do
    v.permanant = nil
end

local function buildFile(fn)
    local _, baseFile = processFile(fn, true)
    while #toProcess > 0 do
        local processingfn = table.remove(toProcess, 1)
        local firstline, content = processFile(processingfn)
        filenameLUT[processingfn].firstline = firstline --[[@as string]]
        filenameLUT[processingfn].content = content
    end
    visit(filenameLUT[fn])
    local f = assert(fs.open(outputfn, "w"))
    for k, v in ipairs(moduleIncludeOrder) do
        f.writeLine(v.firstline)
    end
    for k, v in ipairs(moduleIncludeOrder) do
        f.writeLine(v.content)
    end
    f.writeLine(baseFile)
    f.close()
end

buildFile(inputfn)

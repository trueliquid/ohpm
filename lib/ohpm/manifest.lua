--Reads and checks what packages say about themselves. Touches neither the network nor the disk.
local serialization = require("serialization")

local manifest = {}

local manifestName = "package.cfg"

--Turns "owner/repo@ref" into a table. The key is lower case because GitHub names ignore case.
function manifest.parseSpec(text)
    text = tostring(text)
    local name, ref = text:match("^([^@]*)@(.*)$")
    local owner, repo = (name or text):match("^([%w%-]+)/([%w%-_%.]+)$")
    if not owner or repo == "." or repo == ".." then
        error("Not a valid package, expected owner/repo or owner/repo@ref: " .. text, 0)
    end
    if ref and not ref:match("^[%w%-_%./]+$") then
        error("Not a valid branch, tag or commit: " .. ref, 0)
    end
    return {owner = owner, repo = repo, ref = ref, label = owner .. "/" .. repo, key = (owner .. "/" .. repo):lower()}
end

local function validPath(path)
    if type(path) ~= "string" or path == "" or path:match("[%c\\]") or path:sub(1, 1) == "/" then return false end
    for segment in (path .. "/"):gmatch("([^/]*)/") do
        if segment == "" or segment == "." or segment == ".." then return false end
    end
    return true
end

--Targets are relative to /home. Dot folders are refused so that no package can replace .shrc or
--ohpm's own trust list, which would otherwise skip the warning for later installs.
local function validTarget(path)
    return validPath(path) and path:sub(1, 1) ~= "."
end

--Returns the manifest's files as a list sorted by target.
local function checkFields(fields, label)
    local function bad(problem) error(label .. " has a bad " .. manifestName .. ": " .. problem, 0) end
    if type(fields) ~= "table" then bad("it is not a table") end
    if type(fields.name) ~= "string" or fields.name == "" then bad("name is missing") end
    if type(fields.version) ~= "string" or fields.version == "" then bad("version is missing") end
    if type(fields.files) ~= "table" then bad("files is missing") end
    local files = {}
    for source, target in pairs(fields.files) do
        if not validPath(source) then bad("invalid source path " .. tostring(source)) end
        if not validTarget(target) then bad("invalid target path " .. tostring(target)) end
        files[#files + 1] = {source = source, target = target}
    end
    if #files == 0 then bad("files is empty") end
    table.sort(files, function(a, b) return a.target < b.target end)
    for index = 2, #files do
        if files[index].target == files[index - 1].target then bad("two files use " .. files[index].target) end
    end
    if fields.dependencies ~= nil and type(fields.dependencies) ~= "table" then bad("dependencies is not a list") end
    return files
end

--Returns the manifest's fields and its files as a sorted list. label names the package in errors.
function manifest.parse(text, label)
    local fields, reason = serialization.unserialize(text)
    if fields == nil then
        error(label .. " has a bad " .. manifestName .. ": " .. tostring(reason), 0)
    end
    return fields, checkFields(fields, label)
end

return manifest

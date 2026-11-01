--Installs ohpm itself. It downloads the library to /tmp, using package.cfg to find its files, and
--uses that to install ohpm as a normal package, so ohpm can update and remove itself afterwards.
local filesystem = require("filesystem")
local serialization = require("serialization")
local shell = require("shell")

local repo = "trueliquid/ohpm"
local rawBase = os.getenv("OHPM_RAW_BASE") or "https://raw.githubusercontent.com"
local bootstrapDir = "/tmp/ohpm-bootstrap"

local function fetch(source, path)
    filesystem.makeDirectory(filesystem.path(path))
    shell.execute("wget", nil, "-fq", rawBase .. "/" .. repo .. "/HEAD/" .. source, path)
end

--OpenOS keeps required libraries between programs, so the copy in /tmp must not stay loaded.
local function unloadOhpm()
    for name in pairs(package.loaded) do
        if name == "ohpm" or name:match("^ohpm%.") then package.loaded[name] = nil end
    end
end

--Returns the library from bootstrapDir, or nil if it did not all arrive.
local function loadBootstrap()
    fetch("package.cfg", bootstrapDir .. "/package.cfg")
    local file = io.open(bootstrapDir .. "/package.cfg", "r")
    local manifest = file and serialization.unserialize(file:read("*a") or "")
    if file then file:close() end
    if type(manifest) ~= "table" then return nil end
    for source, target in pairs(manifest.files) do
        if target:match("^lib/") then fetch(source, bootstrapDir .. "/" .. target) end
    end
    local path = package.path
    package.path = bootstrapDir .. "/lib/?.lua;" .. bootstrapDir .. "/lib/?/init.lua;" .. path
    unloadOhpm()
    local ok, ohpm = pcall(require, "ohpm")
    package.path = path
    return ok and type(ohpm) == "table" and ohpm or nil
end

local ohpm = loadBootstrap()
local ok, reason = true, nil
if ohpm then
    ok, reason = pcall(function()
        local plan = ohpm.planInstall(repo)
        if #plan == 0 then
            print("ohpm is already installed. Use ohpm update to get a newer version.")
            return
        end
        ohpm.apply(plan)
        print("Installed ohpm. Run ohpm with no arguments to see what it can do.")
    end)
end
unloadOhpm()
shell.execute("rm", nil, "-rf", bootstrapDir)

if not ohpm then
    io.stderr:write("Could not download ohpm\n")
    return 1
elseif not ok then
    io.stderr:write("Could not install ohpm: " .. tostring(reason) .. "\n")
    return 1
end

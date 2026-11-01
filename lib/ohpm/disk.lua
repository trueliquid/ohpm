--All of ohpm's file access. Targets are paths relative to the root that packages install under.
local filesystem = require("filesystem")
local serialization = require("serialization")

local disk = {}

--OHPM_ROOT exists for the tests, which install into a scratch folder.
local root = os.getenv("OHPM_ROOT") or "/home"
local stateDir = root .. "/.ohpm"
local stagingDir = stateDir .. "/tmp"

function disk.statePath(name)
    return stateDir .. "/" .. name
end

--Writes through a second file, so a crash leaves either the old version or the new one.
function disk.writeTable(path, value)
    filesystem.makeDirectory(stateDir)
    local file, reason = io.open(path .. ".new", "w")
    if not file then error("Could not write " .. path .. ": " .. tostring(reason), 0) end
    local written = file:write(serialization.serialize(value))
    file:close()
    if not written then error("Could not write " .. path .. ". Is the disk full?", 0) end
    filesystem.remove(path)
    if not filesystem.rename(path .. ".new", path) then error("Could not write " .. path, 0) end
end

--Returns nil if there is no file. An unreadable one raises, because treating it as empty would
--forget every installed package.
function disk.readTable(path)
    local file = io.open(path, "r") or io.open(path .. ".new", "r")
    if not file then return nil end
    local text = file:read("*a")
    file:close()
    local value = serialization.unserialize(text or "")
    if value == nil then error("Could not read " .. path, 0) end
    return value
end

function disk.hasTable(path)
    return filesystem.exists(path) or filesystem.exists(path .. ".new")
end

function disk.removeTable(path)
    filesystem.remove(path)
    filesystem.remove(path .. ".new")
end

local function removeTree(path)
    if filesystem.isDirectory(path) then
        for name in filesystem.list(path) do
            removeTree(filesystem.concat(path, name))
        end
    end
    filesystem.remove(path)
end

function disk.clearStaging()
    removeTree(stagingDir)
end

function disk.prepareStaging()
    filesystem.makeDirectory(stagingDir)
end

--Returns a sink for net.downloadFile that writes one file into staging. Its path field says where.
function disk.stagedFile(index)
    local path = stagingDir .. "/" .. index
    local sink = {path = path}
    local file

    function sink.open()
        local reason
        file, reason = io.open(path, "wb")
        if not file then error("Could not write " .. path .. ": " .. tostring(reason), 0) end
    end

    function sink.write(chunk)
        if not file:write(chunk) then error("Could not write " .. path .. ". Is the disk full?", 0) end
    end

    function sink.close()
        file:close()
        return filesystem.size(path)
    end

    return sink
end

function disk.targetExists(target)
    return filesystem.exists(filesystem.concat(root, target))
end

--Replaces a target with a staged file. A staged file that is gone has already been moved, which
--happens when a crash interrupted this and it runs again.
function disk.moveToTarget(from, target)
    if not filesystem.exists(from) then return end
    local path = filesystem.concat(root, target)
    filesystem.makeDirectory(filesystem.path(path))
    filesystem.remove(path)
    if not filesystem.rename(from, path) then
        error("Could not write " .. path .. ". Fix that and run ohpm again to finish the install.", 0)
    end
end

--Deletes a target, then any folders that leaves empty, stopping at the root.
function disk.removeTarget(target)
    local path = filesystem.concat(root, target)
    filesystem.remove(path)
    local parent = filesystem.path(path)
    while #filesystem.canonical(parent) > #root and filesystem.isDirectory(parent) and not filesystem.list(parent)() do
        filesystem.remove(parent)
        parent = filesystem.path(filesystem.canonical(parent))
    end
end

return disk

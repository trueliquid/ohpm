--ohpm's own records: which packages are installed and which GitHub users are trusted.
local disk = require("ohpm.disk")

local store = {}

local installedPath = disk.statePath("installed.cfg")
local trustedPath = disk.statePath("trusted.cfg")

--Returns the installed packages as a table of records by key.
function store.installed()
    return disk.readTable(installedPath) or {}
end

function store.saveInstalled(installed)
    disk.writeTable(installedPath, installed)
end

local function loadTrusted()
    return disk.readTable(trustedPath) or {}
end

local function checkOwner(owner)
    if not tostring(owner):match("^[%w%-]+$") then error("Not a valid GitHub user: " .. tostring(owner), 0) end
    return owner:lower()
end

--Returns the trusted users as a sorted list.
function store.trusted()
    local owners = {}
    for owner in pairs(loadTrusted()) do
        owners[#owners + 1] = owner
    end
    table.sort(owners)
    return owners
end

function store.trust(owner)
    local trusted = loadTrusted()
    trusted[checkOwner(owner)] = true
    disk.writeTable(trustedPath, trusted)
end

--Returns false if the user was not trusted.
function store.untrust(owner)
    local trusted, key = loadTrusted(), checkOwner(owner)
    if not trusted[key] then return false end
    trusted[key] = nil
    disk.writeTable(trustedPath, trusted)
    return true
end

--Returns the users in a plan who are not trusted yet, as a sorted list.
function store.untrustedOwners(plan)
    local trusted, found, owners = loadTrusted(), {}, {}
    for _, item in ipairs(plan) do
        local owner = item.owner:lower()
        if not trusted[owner] and not found[owner] then
            found[owner] = true
            owners[#owners + 1] = owner
        end
    end
    table.sort(owners)
    return owners
end

return store

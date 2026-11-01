--Command line for ohpm. The work is in lib/ohpm.
local ohpm = require("ohpm")
local shell = require("shell")

local usage = [[
Usage: ohpm <command>
  install <owner/repo[@ref]>  Install a package and what it needs
  remove <owner/repo>         Remove a package
  update [owner/repo]         Update one package, or all of them
  list                        Show installed packages
  info <owner/repo[@ref]>     Show a package
  trust list                  Show trusted GitHub users
  trust add <user>            Install from a user without asking
  trust remove <user>         Ask again for a user
]]

local function printPackage(item)
    local version = item.manifest.version
    if item.previous then version = item.previous.version .. " -> " .. version end
    print(item.label .. " " .. version .. " at commit " .. item.commit:sub(1, 7))
    for _, file in ipairs(item.files) do
        print("  " .. file.target)
    end
    if item.manifest.dependencies and #item.manifest.dependencies > 0 then
        print("Requires: " .. table.concat(item.manifest.dependencies, ", "))
    end
end

--Trusted users are skipped, and so is the question if that leaves nobody. Anything but y or t cancels,
--which includes having no terminal to answer from.
local function confirm(plan)
    local owners = ohpm.untrustedOwners(plan)
    if #owners == 0 then return true end
    local names = table.concat(owners, ", ")
    print("")
    print("Warning: ohpm does not ensure that the code it downloads is safe to run.")
    if #owners > 1 then print("This install includes code from: " .. names) end
    print("Are you sure you want to continue?")
    print("  [y] Yes, this time only")
    print("  [t] Yes, and always trust " .. (#owners > 1 and names or '"' .. names .. '"'))
    print("  [N] No")
    io.write("> ")
    local answer = (io.read("*l") or ""):lower()
    if answer == "t" then
        for _, owner in ipairs(owners) do
            ohpm.trust(owner)
        end
        return true
    end
    return answer == "y"
end

--Shows the plan, asks if needed and applies it. verb goes in the closing line for each package.
local function run(plan, verb)
    for _, item in ipairs(plan) do
        printPackage(item)
    end
    if not confirm(plan) then
        print("Cancelled")
        return
    end
    local count = 0
    for _, item in ipairs(plan) do
        count = count + #item.files
    end
    io.write("Downloading " .. count .. (count == 1 and " file... " or " files... "))
    local ok, reason = pcall(ohpm.apply, plan)
    print(ok and "done" or "failed")
    if not ok then error(reason, 0) end
    for _, item in ipairs(plan) do
        print(verb .. " " .. item.label)
    end
end

local commands = {}

function commands.install(spec)
    if not spec then error("install needs a package, such as owner/repo", 0) end
    local plan = ohpm.planInstall(spec)
    if #plan == 0 then
        print(spec .. " is already installed. Use ohpm update to get a newer version.")
    else
        run(plan, "Installed")
    end
end

function commands.remove(spec)
    if not spec then error("remove needs a package, such as owner/repo", 0) end
    ohpm.remove(spec)
    print("Removed " .. spec)
end

function commands.update(spec)
    local plan = ohpm.planUpdate(spec)
    if #plan == 0 then
        print(spec and spec .. " is up to date" or "Everything is up to date")
    else
        run(plan, "Updated")
    end
end

function commands.list()
    local keys, installed = {}, ohpm.installed()
    for key in pairs(installed) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local record = installed[key]
        local pinned = record.ref and " (" .. record.ref .. ")" or ""
        print(record.owner .. "/" .. record.repo .. " " .. record.version .. " at " .. record.commit:sub(1, 7) .. pinned)
    end
    if #keys == 0 then print("No packages installed") end
end

local function printList(title, values)
    if values and #values > 0 then
        print(title .. ": " .. table.concat(values, ", "))
    end
end

function commands.info(spec)
    if not spec then error("info needs a package, such as owner/repo", 0) end
    local record = ohpm.record(spec)
    if record then
        print(record.owner .. "/" .. record.repo .. " (" .. record.name .. ")")
        print("Installed: " .. record.version .. " at commit " .. record.commit:sub(1, 7))
        print("Files: " .. table.concat(record.files, ", "))
        printList("Requires", record.dependencies)
    else
        local found = ohpm.lookup(spec)
        print(found.label .. " (" .. found.manifest.name .. ")")
        print("Not installed. Available: " .. found.manifest.version .. " at commit " .. found.commit:sub(1, 7))
        for _, file in ipairs(found.files) do
            print("  " .. file.target)
        end
        printList("Requires", found.manifest.dependencies)
    end
end

function commands.trust(action, owner)
    if action == "list" then
        local owners = ohpm.trusted()
        print(#owners > 0 and table.concat(owners, "\n") or "No trusted users")
    elseif action == "add" and owner then
        ohpm.trust(owner)
        print("Trusted " .. owner)
    elseif action == "remove" and owner then
        print(ohpm.untrust(owner) and "No longer trusted: " .. owner or owner .. " was not trusted")
    else
        error("Usage: ohpm trust list, ohpm trust add <user>, ohpm trust remove <user>", 0)
    end
end

local args = shell.parse(...)
local command = commands[args[1]]
if not command then
    io.write(usage)
    return args[1] and 1 or 0
end

local ok, reason = pcall(function()
    ohpm.recover()
    command(table.unpack(args, 2))
end)
if not ok then
    io.stderr:write("ohpm: " .. tostring(reason) .. "\n")
    return 1
end

--Changes what is installed. Installs go through a journal, so a crash never leaves one half done.
local disk = require("ohpm.disk")
local manifest = require("ohpm.manifest")
local net = require("ohpm.net")
local store = require("ohpm.store")

local transaction = {}

local journalPath = disk.statePath("journal.cfg")

--Applies the journal. It holds everything needed to finish, so it is safe to run again after a crash.
local function finishJournal()
    local journal = disk.readTable(journalPath)
    if not journal then return false end
    for _, target in ipairs(journal.removes) do
        disk.removeTarget(target)
    end
    for _, move in ipairs(journal.moves) do
        disk.moveToTarget(move.from, move.to)
    end
    local installed = store.installed()
    for key, record in pairs(journal.records) do
        installed[key] = record
    end
    store.saveInstalled(installed)
    disk.removeTable(journalPath)
    disk.clearStaging()
    return true
end

--Finishes an install that a crash interrupted, or clears a download that never got that far.
function transaction.recover()
    if disk.hasTable(journalPath) then
        local ok, journal = pcall(disk.readTable, journalPath)
        if ok and journal then
            finishJournal()
            return true
        end
        disk.removeTable(journalPath)
    end
    disk.clearStaging()
    return false
end

--Downloads everything into staging, then moves it into place through the journal, so a failed
--download changes nothing.
function transaction.apply(plan)
    transaction.recover()
    disk.prepareStaging()
    local moves, removes, records = {}, {}, {}
    local ok, failure = pcall(function()
        for _, item in ipairs(plan) do
            local kept, targets = {}, {}
            for _, file in ipairs(item.files) do
                local sink = disk.stagedFile(#moves + 1)
                net.downloadFile(item.owner, item.repo, item.commit, file.source, sink)
                moves[#moves + 1] = {from = sink.path, to = file.target}
                targets[#targets + 1] = file.target
                kept[file.target] = true
            end
            for _, target in ipairs(item.previous and item.previous.files or {}) do
                if not kept[target] then removes[#removes + 1] = target end
            end
            records[item.key] = {
                owner = item.owner, repo = item.repo, ref = item.ref, commit = item.commit,
                name = item.manifest.name, version = item.manifest.version,
                files = targets, dependencies = item.dependencies
            }
        end
        disk.writeTable(journalPath, {moves = moves, removes = removes, records = records})
    end)
    if not ok then
        disk.clearStaging()
        error(failure, 0)
    end
    finishJournal()
end

--The package stays on record until its files are gone, so a crash here can just be run again.
function transaction.remove(text)
    transaction.recover()
    local spec = manifest.parseSpec(text)
    local installed = store.installed()
    local record = installed[spec.key]
    if not record then error(spec.label .. " is not installed", 0) end
    local dependents = {}
    for key, other in pairs(installed) do
        for _, dependency in ipairs(other.dependencies) do
            if dependency == spec.key then dependents[#dependents + 1] = key end
        end
    end
    if #dependents > 0 then
        table.sort(dependents)
        error(spec.label .. " is needed by " .. table.concat(dependents, ", "), 0)
    end
    for _, target in ipairs(record.files) do
        disk.removeTarget(target)
    end
    installed[spec.key] = nil
    store.saveInstalled(installed)
end

return transaction

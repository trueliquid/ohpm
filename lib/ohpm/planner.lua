--Works out what an install or update has to do, without changing anything.
local disk = require("ohpm.disk")
local manifest = require("ohpm.manifest")
local net = require("ohpm.net")
local store = require("ohpm.store")

local planner = {}

local function checkConflicts(plan, installed)
    local owners, planned = {}, {}
    for key, record in pairs(installed) do
        for _, target in ipairs(record.files) do
            owners[target] = key
        end
    end
    for _, item in ipairs(plan) do
        for _, file in ipairs(item.files) do
            local target = file.target
            if planned[target] then
                error(planned[target] .. " and " .. item.label .. " both install " .. target, 0)
            end
            planned[target] = item.label
            if owners[target] and owners[target] ~= item.key then
                error(item.label .. " would overwrite " .. target .. ", which belongs to " .. owners[target], 0)
            elseif not owners[target] and disk.targetExists(target) then
                error(item.label .. " would overwrite " .. target .. ", which already exists", 0)
            end
        end
    end
end

--Dependencies come first in the returned list. With refresh, the requested packages are checked
--for new commits. Otherwise a package that is already installed is left alone, so an empty list
--means there is nothing to do.
local function buildPlan(specs, refresh)
    local installed = store.installed()
    local plan, planned, path, inPath = {}, {}, {}, {}

    local function visit(spec, refreshing)
        if inPath[spec.key] then
            error("Dependency cycle: " .. table.concat(path, " -> ") .. " -> " .. spec.key, 0)
        end
        local existing, record = planned[spec.key], installed[spec.key]
        if existing then
            if spec.ref and net.findCommit(spec.owner, spec.repo, spec.ref) ~= existing.commit then
                error("Two packages need different versions of " .. spec.label, 0)
            end
            return
        end
        if record and not refreshing then
            if spec.ref and spec.ref ~= record.ref then
                error(spec.label .. " is already installed at a different version. Remove it first.", 0)
            end
            return
        end
        local ref = spec.ref or (record and record.ref)
        local commit = net.findCommit(spec.owner, spec.repo, ref)
        if record and record.commit == commit then return end
        local fields, files = manifest.parse(net.fetchManifest(spec.owner, spec.repo, commit), spec.label)
        local item = {
            key = spec.key, owner = spec.owner, repo = spec.repo, label = spec.label, ref = ref,
            commit = commit, manifest = fields, files = files, previous = record, dependencies = {}
        }
        planned[spec.key] = item
        path[#path + 1] = spec.key
        inPath[spec.key] = true
        for _, dependency in ipairs(fields.dependencies or {}) do
            local parsed = manifest.parseSpec(dependency)
            item.dependencies[#item.dependencies + 1] = parsed.key
            visit(parsed, false)
        end
        path[#path] = nil
        inPath[spec.key] = nil
        plan[#plan + 1] = item
    end

    for _, spec in ipairs(specs) do
        visit(spec, refresh)
    end
    checkConflicts(plan, installed)
    return plan
end

--Plans installing the package named by text, such as "owner/repo@v1". Empty if it is already installed.
function planner.install(text)
    return buildPlan({manifest.parseSpec(text)}, false)
end

--Plans updating one installed package, or all of them without an argument.
function planner.update(text)
    local installed, specs = store.installed(), {}
    if text then
        local spec = manifest.parseSpec(text)
        if spec.ref then error("update takes no @ref: " .. text, 0) end
        local record = installed[spec.key]
        if not record then error(spec.label .. " is not installed", 0) end
        specs[1] = {owner = record.owner, repo = record.repo, key = spec.key, label = record.owner .. "/" .. record.repo}
    else
        for key, record in pairs(installed) do
            specs[#specs + 1] = {owner = record.owner, repo = record.repo, key = key, label = record.owner .. "/" .. record.repo}
        end
        table.sort(specs, function(a, b) return a.key < b.key end)
    end
    return buildPlan(specs, true)
end

return planner

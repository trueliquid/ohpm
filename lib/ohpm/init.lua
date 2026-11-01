--The public face of ohpm, the Open Horizons Package Manager. Installs packages from public GitHub repos.
--Nothing in here asks the user anything: bin/ohpm.lua shows a plan and decides whether to apply it.
--Failures are raised with error(message, 0), so the message is always fit to show as it is.
local manifest = require("ohpm.manifest")
local net = require("ohpm.net")
local planner = require("ohpm.planner")
local store = require("ohpm.store")
local transaction = require("ohpm.transaction")

local ohpm = {}

ohpm.planInstall = planner.install
ohpm.planUpdate = planner.update
ohpm.apply = transaction.apply
ohpm.remove = transaction.remove
ohpm.recover = transaction.recover
ohpm.installed = store.installed
ohpm.trusted = store.trusted
ohpm.trust = store.trust
ohpm.untrust = store.untrust
ohpm.untrustedOwners = store.untrustedOwners

--Returns the record of an installed package, or nil.
function ohpm.record(text)
    return store.installed()[manifest.parseSpec(text).key]
end

--Reads a package from GitHub without installing it.
function ohpm.lookup(text)
    local spec = manifest.parseSpec(text)
    local commit = net.findCommit(spec.owner, spec.repo, spec.ref)
    local fields, files = manifest.parse(net.fetchManifest(spec.owner, spec.repo, commit), spec.label)
    return {label = spec.label, commit = commit, manifest = fields, files = files}
end

return ohpm

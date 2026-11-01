--Everything ohpm asks of the outside world. This module never touches the disk, and only the three
--functions at the bottom are public, so another package source only has to provide those.
local component = require("component")
local computer = require("computer")

local net = {}

--The OHPM_ variables exist for the tests, which point these at a fake GitHub.
local gitBase = os.getenv("OHPM_GIT_BASE") or "https://github.com"
local rawBase = os.getenv("OHPM_RAW_BASE") or "https://raw.githubusercontent.com"

local manifestName = "package.cfg"
local maxManifestSize = 65536
local connectTimeout = 15 --Seconds
local stallTimeout = 30 --Seconds without any data
local maxAttempts = 3
local retryDelay = 2 --Seconds, multiplied by the attempt count
local requestHeaders = {["User-Agent"] = "ohpm"}
local rateLimited = "GitHub is rate limiting this IP address (HTTP 429). Wait a while and try again."

local function header(headers, name)
    for key, value in pairs(headers or {}) do
        if tostring(key):lower() == name then
            return type(value) == "table" and value[1] or value
        end
    end
    return nil
end

--Returns the open handle with its HTTP code and headers, or nil and a reason in the fourth value.
--finishConnect also fails on HTTP errors, so the code always comes from response.
local function connect(url)
    local ok, handle, reason = pcall(component.internet.request, url, nil, requestHeaders)
    if not ok then return nil, nil, nil, tostring(handle) end
    if not handle then return nil, nil, nil, tostring(reason) end
    local started = computer.uptime()
    while true do
        local finished, connected, failure = pcall(handle.finishConnect)
        if not finished or connected ~= false then
            local answered, code, _, headers = pcall(handle.response)
            if answered and code then return handle, code, headers end
            if not finished or connected == nil then
                pcall(handle.close)
                return nil, nil, nil, tostring(failure or connected)
            end
        end
        if computer.uptime() - started > connectTimeout then
            pcall(handle.close)
            return nil, nil, nil, "timed out"
        end
        os.sleep(0.05)
    end
end

--Calls onChunk with each piece of the body until the body ends or onChunk returns false.
--A broken connection raises a table, which request takes as a reason to try again.
local function stream(handle, onChunk)
    local lastData = computer.uptime()
    while true do
        local ok, chunk, reason = pcall(handle.read, math.huge)
        if not ok then error({retry = tostring(chunk)}) end
        if chunk == nil then
            if reason then error({retry = tostring(reason)}) end
            return
        elseif #chunk > 0 then
            lastData = computer.uptime()
            if onChunk(chunk) == false then return end
            os.sleep(0)
        elseif computer.uptime() - lastData > stallTimeout then
            error({retry = "download stalled"})
        else
            os.sleep(0.05)
        end
    end
end

--Runs onResponse(handle, headers) on a successful response and returns what it returns.
--Network failures and 5xx are tried again. failures maps other HTTP codes to the message to raise.
local function request(url, failures, onResponse)
    local problem
    for attempt = 1, maxAttempts do
        if attempt > 1 then os.sleep(retryDelay * (attempt - 1)) end
        local handle, code, headers, reason = connect(url)
        if code and code >= 200 and code < 300 then
            local ok, result = pcall(onResponse, handle, headers)
            pcall(handle.close)
            if ok then return result end
            if type(result) ~= "table" then error(result, 0) end
            problem = result.retry
        else
            if handle then pcall(handle.close) end
            if code == 429 then error(rateLimited, 0) end
            if code and code < 500 then
                error(failures[code] or "GitHub refused the request (HTTP " .. code .. "): " .. url, 0)
            end
            problem = code and "HTTP " .. code or reason
        end
    end
    error("Could not reach GitHub (" .. tostring(problem) .. "): " .. url, 0)
end

local function encodePath(path)
    return (path:gsub("[^%w%-_%.~/]", function(character)
        return string.format("%%%02X", character:byte())
    end))
end

local function isCommit(ref)
    return #ref == 40 and ref:match("^%x+$") ~= nil
end

--The Git endpoint is what git clone reads. It lists every ref as packets, each starting with its
--length in 4 hex digits, and a length of 0 marks the end of a section. Unlike the GitHub API it
--needs no JSON and does not use the API quota.
local function readRefs(handle, onRef)
    local buffer, sections, finished = "", 0, false
    stream(handle, function(chunk)
        buffer = buffer .. chunk
        while #buffer >= 4 do
            local length = tonumber(buffer:sub(1, 4), 16)
            if not length then error("GitHub sent an unreadable ref list", 0) end
            if length == 0 then
                sections = sections + 1
                buffer = buffer:sub(5)
                if sections == 2 then
                    finished = true
                    return false
                end
            elseif #buffer < length then
                return
            else
                local commit, name = buffer:sub(5, length):match("^(%x+) ([^\0\n]+)")
                buffer = buffer:sub(length + 1)
                if commit and onRef(commit, name) == false then
                    finished = true
                    return false
                end
            end
        end
    end)
    if not finished then error({retry = "ref list ended early"}) end
end

--Returns the commit that ref points at, or the default branch's commit without a ref.
function net.findCommit(owner, repo, ref)
    if ref and isCommit(ref) then return ref:lower() end
    local label = owner .. "/" .. repo
    local url = gitBase .. "/" .. owner .. "/" .. repo .. ".git/info/refs?service=git-upload-pack"
    local failures = {
        [401] = label .. " was not found, or it is private",
        [404] = label .. " was not found, or it is private"
    }
    return request(url, failures, function(handle)
        local head, branch, tag, peeled
        readRefs(handle, function(commit, name)
            if not ref then
                head = commit
                if name == "HEAD" then return false end
                head = nil
            elseif name == "refs/heads/" .. ref then
                branch = commit
            elseif name == "refs/tags/" .. ref then
                tag = commit
            elseif name == "refs/tags/" .. ref .. "^{}" then
                peeled = commit --An annotated tag, and this line holds its real commit
                return false
            elseif name > "refs/tags/" .. ref .. "^{}" then
                return false --Refs are sorted, so it cannot appear after this
            end
        end)
        local commit = peeled or tag or branch or head
        if commit then return commit end
        if ref then error(label .. " has no branch or tag called " .. ref, 0) end
        error(label .. " is empty", 0)
    end)
end

--Returns the text of the package's manifest at a commit.
function net.fetchManifest(owner, repo, commit)
    local label = owner .. "/" .. repo
    local url = rawBase .. "/" .. label .. "/" .. commit .. "/" .. manifestName
    local failures = {[404] = label .. " has no " .. manifestName .. " at commit " .. commit:sub(1, 7)}
    return request(url, failures, function(handle)
        local chunks, size = {}, 0
        stream(handle, function(chunk)
            size = size + #chunk
            if size > maxManifestSize then error(label .. ": " .. manifestName .. " is too large", 0) end
            chunks[#chunks + 1] = chunk
        end)
        return table.concat(chunks)
    end)
end

--Sends a file to sink, which has open(), write(chunk), and close() returning the size it stored.
--Each attempt calls open again, so a retry starts the file from nothing.
function net.downloadFile(owner, repo, commit, source, sink)
    local label = owner .. "/" .. repo
    local url = rawBase .. "/" .. label .. "/" .. commit .. "/" .. encodePath(source)
    local failures = {[404] = label .. " lists " .. source .. " but that file does not exist"}
    request(url, failures, function(handle, headers)
        local size = 0
        sink.open()
        local ok, failure = pcall(stream, handle, function(chunk)
            size = size + #chunk
            sink.write(chunk)
        end)
        local stored = sink.close()
        if not ok then error(failure, 0) end
        if stored ~= size then error("Could not store " .. source .. ". Is the disk full?", 0) end
        local expected = tonumber(header(headers, "content-length"))
        if expected and expected ~= size then
            error({retry = "got " .. size .. " of " .. expected .. " bytes"})
        end
    end)
end

return net

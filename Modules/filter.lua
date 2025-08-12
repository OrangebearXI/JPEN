local utf8util = require('utf8util')
local fmt      = require('fmt')

local M = {}
local rules = {}
local base_folder = ''

local function default_dirs()
    local home = os.getenv('USERPROFILE') or ''
    return {
        home..'/Documents/My Games/FINAL FANTASY XI/ffxiuser',
        home..'/OneDrive/Documents/My Games/FINAL FANTASY XI/ffxiuser',
    }
end

local function resolve_path(settings)
    if settings.prohibited_dir and settings.prohibited_dir ~= '' then
        return settings.prohibited_dir .. '/prohibited.txt'
    end
    for _,d in ipairs(default_dirs()) do
        local p = d .. '/prohibited.txt'
        local f = io.open(p,'r'); if f then f:close(); return p end
    end
    return nil
end

local function parse_flags_and_term(line)
    local f, rest = line:match('^%(([%a]+)%)%s*(.+)$')
    if not f then return {i=false,s=false}, (line or '') end
    local flags = {i=false,s=false}
    f = f:lower()
    if f:find('i',1,true) then flags.i = true end
    if f:find('s',1,true) then flags.s = true end
    return flags, rest
end

local function normalize(s, flags)
    s = utf8util.ensure_utf8(s)
    s = utf8util.fold_width(s)
    if flags.s then s = s:gsub('%s+','') end
    if flags.i then s = s:lower() end
    return s
end

function M.load(settings)
    rules = {}
    local path = resolve_path(settings); if not path then return end
    local f = io.open(path, 'r'); if not f then return end
    local count = 0
    for line in f:lines() do
        line = (line or ''):gsub('^%s+',''):gsub('%s+$','')
        if line ~= '' then
            local flags, term = parse_flags_and_term(line)
            term = (term or ''):gsub('^%s+',''):gsub('%s+$','')
            if term ~= '' then
                rules[#rules + 1] = {flags = flags, pat = normalize(term, flags)}
                count = count + 1
                if count >= 100 then break end
            end
        end
    end
    f:close()
end

function M.count() return #rules end

local function channel_is_filtered(mode, settings)
    local ch = fmt.chan_name(mode):gsub('^%l', string.upper)
    return not not settings.filter_channels[ch]
end

function M.is_filtered(mode, text, settings)
    if not settings.filter_enabled or not channel_is_filtered(mode, settings) then return false end
    if #rules == 0 then return false end
    for i = 1, #rules do
        local r = rules[i]
        local hay = normalize(text, r.flags)
        if hay:find(r.pat, 1, true) then return true end
    end
    return false
end

return M

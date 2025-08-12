local res = require('resources')
local M = {}

local CHAT_COLORS = {
    say        = {255,255,255},
    party      = { 51,153,255},
    shout      = {255,128,  0},
    yell       = {255,255,  0},
    linkshell  = { 90,220,110},
    linkshell2 = {180,240,120},
    tell       = {255,128,255},
    diag       = {200,200,200},
    unknown    = {200,200,200},
}

local chan_label_cache = {}

local function chan_name(mode)
    if type(mode) == 'string' then return mode:lower() end
    local r = res.chat[mode]
    if r and r.english then return r.english:lower() end
    return 'unknown'
end

function M.color_for_mode(mode)
    local key = chan_name(mode)
    return CHAT_COLORS[key] or CHAT_COLORS.unknown
end

function M.colorize_text(rgb, text)
    return string.format('\\cs(%d,%d,%d)%s\\cr', rgb[1], rgb[2], rgb[3], text or '')
end

function M.chan_label(mode)
    local key = chan_name(mode)
    local v = chan_label_cache[key]
    if v then return v end
    local rgb = M.color_for_mode(mode)
    local ch  = key:gsub('^%l', string.upper)
    v = string.format('\\cs(%d,%d,%d)[%s]\\cr', rgb[1], rgb[2], rgb[3], ch)
    chan_label_cache[key] = v
    return v
end

function M.colorize_translated(mode, text)
    if not text or text == '' then return '' end
    if text:find('^%[Offline%]') or text:find('^%[jpen%]') then return '\\cs(160,160,160)'..text..'\\cr' end
    return M.colorize_text(M.color_for_mode(mode), text)
end

function M.timestamp()
    return string.format('\\cs(255,255,255)[%s]\\cr', os.date('%H:%M'))
end

function M.to_ascii(s)
    if not s or s=='' then return '' end
    s = s:gsub('“','"'):gsub('”','"'):gsub('’',"'"):gsub('–','-'):gsub('—','-')
    return (s:gsub('[\128-\255]','?'))
end

function M.chan_name(mode) return chan_name(mode) end

return M

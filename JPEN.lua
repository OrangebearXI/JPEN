_addon.name     = 'jpen'
_addon.author   = 'Orangebear'
_addon.version  = '1.00'
_addon.commands = {'jpen'}

-- Your modules live in JPEN/Modules
local base = windower.addon_path
package.path = table.concat({
    package.path,
    base .. 'Modules/?.lua',
}, ';')

local packets   = require('packets')
local config    = require('config')
local socket    = require('socket')

local utf8util  = require('utf8util')
local fmt       = require('fmt')
local ui_mod    = require('ui')
local cache_mod = require('cache')
local filter    = require('filter')
local net       = require('net_deepl')
if type(net) ~= 'table' or type(net.translate_batch) ~= 'function' then
    windower.add_to_chat(167, '[jpen] net_deepl failed to load, translate_batch missing.')
end

local defaults = {
    enabled = true,
    max_lines = 5,

    font = 'Segoe UI',
    size = 10,
    line_gap = 2,
    pos = {x = 795, y = 1095},

    api_key = '',
    batch_size = 5,
    tick_ms = 200,
    backoff_ms = 3000,
    cache_size = 200,

    filter_enabled = true,
    prohibited_dir = '',
    filter_channels = {Yell=true, Shout=true, Assist=true, AssistE=true},

    box_width = 520,
    box_pad_x = 8,
    box_pad_y = 8,
    overscan_y = 6,

    bg = { enabled = true, path = '', alpha = 255 },
}

local settings = config.load(defaults)

-- helpers
local function file_exists(p)
    local f = io.open(p, 'rb')
    if f then f:close() return true end
    return false
end

local function from_resources(name)
    local roots = {'Resources','resources'}
    for _, r in ipairs(roots) do
        local p = windower.addon_path .. r .. '/' .. name
        if file_exists(p) then return p end
    end
    return nil
end

-- default to bg4.png unless user has a valid custom path
if not settings.bg.path or settings.bg.path == '' or not file_exists(settings.bg.path) then
    settings.bg.path = from_resources('bg4.png')
                    or from_resources('bg.png')
                    or from_resources('bg3.png')
                    or from_resources('bg2.png')
                    or from_resources('bg1.png')
                    or ''
    config.save(settings)
end

-- state
local lines, zoning = {}, false

local ui = ui_mod.new({
    font = settings.font,
    size = settings.size,
    line_gap = settings.line_gap,
    pos = {x = settings.pos.x, y = settings.pos.y},
    box_width = settings.box_width,
    box_pad_x = settings.box_pad_x,
    box_pad_y = settings.box_pad_y,
    overscan_y = settings.overscan_y,
    bg_path = settings.bg.path,
    bg_alpha = settings.bg.alpha or 255,
    bg_enabled = settings.bg.enabled,
})

local lru = cache_mod.new(settings.cache_size)

-- offline dict used only on HTTP failure
local dict = {}
local function load_dict()
    local f = io.open(windower.addon_path .. 'data/dict.tsv', 'r')
    if not f then return end
    for line in f:lines() do
        local jp, en = line:match('^(.-)\t(.-)$')
        if jp and en and jp ~= '' and en ~= '' then dict[jp] = en end
    end
    f:close()
end
load_dict()
local function dict_translate(s) return dict[s] end

-- line push
local function push_line(mode, sender, text)
    local out = ('%s %s %s : %s'):format(
        fmt.timestamp(),
        fmt.chan_label(mode),
        sender or 'Unknown',
        fmt.colorize_translated(mode, fmt.to_ascii(text or ''))
    )
    lines[#lines + 1] = out
    if settings.max_lines and settings.max_lines > 0 and #lines > settings.max_lines then
        table.remove(lines, 1)
    end
    local b = {}
    for i = #lines, 1, -1 do b[#b + 1] = lines[i] end
    ui:set_text(table.concat(b, '\n'), settings.bg.enabled)
end

-- duplicate guard
local recent = {}
local function seen_recent(mode, sender, text)
    local now = socket.gettime()
    local key = tostring(mode) .. '|' .. tostring(sender) .. '|' .. tostring(text)
    local t0 = recent[key]
    recent[key] = now
    if t0 and now - t0 < 2.0 then return true end
    if math.random(1, 50) == 1 then
        for k, ts in pairs(recent) do if now - ts > 6.0 then recent[k] = nil end end
    end
    return false
end

-- queue and HTTP driver
local q, busy, api_down_until = {}, false, 0
local last_tick = 0

local function network_tick()
    local now = socket.gettime() * 1000
    if now - last_tick < settings.tick_ms then return end
    last_tick = now
    if not settings.enabled or busy or now < api_down_until or #q == 0 then return end

    busy = true
    local batch = {}
    for i = 1, math.min(settings.batch_size, #q) do
        batch[#batch + 1] = table.remove(q, 1)
    end

    -- DeepL first
    local texts = {}
    for i = 1, #batch do texts[i] = batch[i].text end
    local parts, err = net.translate_batch(settings.api_key, texts)
    if parts then
        for i, tr in ipairs(parts) do
            local it = batch[i]
            lru.put(it.text, tr)
            push_line(it.mode, it.sender, tr)
        end
        busy = false
        return
    end

    -- fallback
    for _, it in ipairs(batch) do
        local off = dict_translate(it.text)
        if off then push_line(it.mode, it.sender, '[Offline] ' .. off)
        else push_line(it.mode, it.sender, '[Offline] Translation unavailable') end
    end
    api_down_until = now + settings.backoff_ms
    busy = false
end

-- filtering
filter.load(settings)

-- capture
local function handle_message(mode, sender, msg_raw)
    if not mode or not msg_raw or msg_raw == '' then return end
    if not settings.enabled then return end
    if utf8util.ascii_only(msg_raw) and not msg_raw:find('\xFD', 1, true) then return end
    local expanded = utf8util.ensure_utf8(windower.convert_auto_trans(msg_raw))
    if filter.is_filtered(mode, expanded, settings) then return end
    if not utf8util.is_japanese(expanded) then return end
    if seen_recent(mode, sender, expanded) then return end
    local cached = lru.get(expanded)
    if cached then push_line(mode, sender, cached); return end
    q[#q + 1] = {mode = mode, sender = sender, text = expanded}
end

windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x017 or not settings.enabled then return end
    local p = packets.parse('incoming', data); if not p then return end
    local name = p['Sender Name'] or p.Sender or p['Sender'] or p['Name'] or 'Unknown'
    handle_message(p.Mode, name, p.Message)
end)

local function parse_outgoing_channel(line)
    local l = line:lower()
    if l:find('^/p%s') or l:find('^/party%s') then
        return 'Party', line:match('^/%S+%s+(.+)$')
    elseif l:find('^/s%s') or l:find('^/say%s') then
        return 'Say', line:match('^/%S+%s+(.+)$')
    elseif l:find('^/sh%s') or l:find('^/shout%s') then
        return 'Shout', line:match('^/%S+%s+(.+)$')
    elseif l:find('^/y%s') or l:find('^/yell%s') then
        return 'Yell', line:match('^/%S+%s+(.+)$')
    elseif l:find('^/l2%s') then
        return 'Linkshell2', line:match('^/%S+%s+(.+)$')
    elseif l:find('^/l%s') then
        return 'Linkshell', line:match('^/%S+%s+(.+)$')
    elseif l:find('^/t%s') or l:find('^/tell%s') then
        local _, msg = line:match('^/%S+%s+(%S+)%s+(.+)$')
        return 'Tell', msg
    end
end

windower.register_event('outgoing text', function(text)
    if not settings.enabled or not text or text == '' then return end
    local ch, msg = parse_outgoing_channel(text); if not ch or not msg or msg == '' then return end
    if utf8util.ascii_only(msg) and not msg:find('\xFD', 1, true) then return end
    local expanded = utf8util.ensure_utf8(windower.convert_auto_trans(msg))
    if filter.is_filtered(ch, expanded, settings) then return end
    if not utf8util.is_japanese(expanded) then return end
    local me = windower.ffxi.get_player()
    handle_message(ch, me and me.name or 'You', expanded)
end)

-- frame driver
windower.register_event('prerender', function()
    ui:on_prerender(zoning)
    network_tick()
end)

-- zoning
local function set_zoning(v)
    zoning = v and true or false
    if zoning then
        ui:hide()
    else
        if #lines > 0 and settings.enabled then
            local b = {}
            for i = #lines, 1, -1 do b[#b + 1] = lines[i] end
            ui:set_text(table.concat(b, '\n'), settings.bg.enabled)
        end
    end
end

windower.register_event('zone change', function()
    set_zoning(true)
    if coroutine and coroutine.schedule then
        coroutine.schedule(function() set_zoning(false) end, 3)
    else
        set_zoning(false)
    end
end)

-- commands
local function safe(s) return fmt.to_ascii(s or ''):gsub('[\r\n]',' ') end

windower.register_event('addon command', function(cmd, ...)
    cmd = (cmd or ''):lower()
    local args = {...}

    if cmd == 'on' then
        settings.enabled = true; config.save(settings)
        set_zoning(false)
    elseif cmd == 'off' then
        settings.enabled = false; config.save(settings)
        ui:hide()
    elseif cmd == 'clear' then
        lines = {}; ui:hide()
    elseif cmd == 'addkey' then
        local key = table.concat(args, ' ')
        if key ~= '' then settings.api_key = key; config.save(settings); windower.add_to_chat(207, '[jpen] API key saved.')
        else windower.add_to_chat(167, '[jpen] Usage: //jpen addkey YOUR_KEY') end
    elseif cmd == 'addprohibited' then
        local folder = table.concat(args, ' '):gsub('^\"(.*)\"$', '%1')
        if folder == '' then windower.add_to_chat(207, '[jpen] Usage: //jpen addprohibited C:\\path\\to\\ffxiuser'); return end
        settings.prohibited_dir = folder; config.save(settings); filter.load(settings)
        windower.add_to_chat(207, ('[jpen] prohibited loaded. rules=%d'):format(filter.count()))
    elseif cmd == 'reloadfilter' then
        filter.load(settings)
        windower.add_to_chat(207, ('[jpen] filter reloaded. rules=%d'):format(filter.count()))
    elseif cmd == 'filter' then
        local v = (args[1] or ''):lower()
        if v == 'on' or v == 'off' then
            settings.filter_enabled = (v == 'on'); config.save(settings)
            windower.add_to_chat(207, ('[jpen] filter %s'):format(settings.filter_enabled and 'on' or 'off'))
        else
            windower.add_to_chat(207, '[jpen] filter on|off')
        end
    elseif cmd == 'bg' then
        local name = table.concat(args, ' '):lower()
        if name == '' or name == 'on' then
            settings.bg.enabled = true; config.save(settings)
            ui:set_bg_enabled(true)
            windower.add_to_chat(207, '[jpen] Background enabled.')
        elseif name == 'off' then
            settings.bg.enabled = false; config.save(settings)
            ui:set_bg_enabled(false)
            windower.add_to_chat(207, '[jpen] Background disabled.')
        else
            local n = name:gsub('%.png$',''); if n == '' then n = 'bg' end
            local p = from_resources(n .. '.png') or (windower.addon_path .. 'Resources/' .. n .. '.png')
            settings.bg.path = p; settings.bg.enabled = true; config.save(settings)
            ui:set_bg_path(p)
            windower.add_to_chat(207, '[jpen] Background set to '..n..'.png')
        end
    elseif cmd == 'bgpath' then
        local p = table.concat(args, ' ')
        if p == '' then windower.add_to_chat(207, '[jpen] Usage: //jpen bgpath <file.png>'); return end
        settings.bg.path = p; settings.bg.enabled = true; config.save(settings)
        ui:set_bg_path(p)
        windower.add_to_chat(207, '[jpen] Background path set.')
    elseif cmd == 'bgalpha' then
        local n = tonumber(args[1] or '')
        if n and n >= 0 and n <= 255 then
            settings.bg.alpha = n; config.save(settings)
            ui:set_bg_alpha(n)
            windower.add_to_chat(207, '[jpen] Background alpha set to '..n..'.')
        else
            windower.add_to_chat(167, '[jpen] Usage: //jpen bgalpha 0-255')
        end
    elseif cmd == 'max' then
        local n = tonumber(args[1] or '')
        if n and n >= 1 and n <= 20 then
            settings.max_lines = n; config.save(settings)
            windower.add_to_chat(207, ('[jpen] max_lines set to %d'):format(n))
        else
            windower.add_to_chat(167, '[jpen] Usage: //jpen max 1-20')
        end
    elseif cmd == 'pad' then
        local n = tonumber(args[1] or '')
        if n and n >= 0 and n <= 8 then
            settings.overscan_y = n; config.save(settings)
            ui:set_box({
                box_width = settings.box_width,
                box_pad_x = settings.box_pad_x,
                box_pad_y = settings.box_pad_y,
                overscan_y = settings.overscan_y,
            })
            windower.add_to_chat(207, ('[jpen] overscan_y set to %d'):format(n))
        else
            windower.add_to_chat(167, '[jpen] Usage: //jpen pad 0-8')
        end
    elseif cmd == 'dims' then
        local pos, ext = ui:info()
        local h = ui:text_height_for_current()
        windower.add_to_chat(207, ('[jpen] anchor=(%d,%d) width=%d height=%d measured_text_h=%d')
            :format(pos.x, pos.y, settings.box_width, h, ext.h or 0))
    elseif cmd == 'test' then
        local raw = table.concat(args, ' '); if raw == '' then raw = 'テストです。こんにちは。よろしくお願いします。' end
        local t = utf8util.ensure_utf8(raw)
        local me = windower.ffxi.get_player()
        handle_message('Diag', me and me.name or 'You', t)
    else
        windower.add_to_chat(207,'[jpen] Commands: //jpen on | off | clear | addkey KEY | addprohibited <folder> | reloadfilter | filter on|off | test [jp] | bg on|off|<name> | bgpath <file> | bgalpha 0-255 | max N | pad N | dims')
    end
end)

-- lifecycle
windower.register_event('load', function()
    ui:warm()
    if #lines > 0 and settings.enabled then
        local b = {}
        for i = #lines, 1, -1 do b[#b + 1] = lines[i] end
        ui:set_text(table.concat(b, '\n'), settings.bg.enabled)
    end
end)

windower.register_event('unload', function() ui:hide() end)

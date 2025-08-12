-- Windower4 addon: jpen
_addon.name = 'jpen'
_addon.author = 'ash+echo'
_addon.version = '0.70'
_addon.commands = {'jpen'}

local packets = require('packets')
local texts   = require('texts')
local config  = require('config')
local res     = require('resources')
local https   = require('ssl.https')
local ltn12   = require('ltn12')
local socket  = require('socket')

local defaults = {
    enabled = true,
    max_lines = 7,
    font = 'Segoe UI',
    size = 10,
    pos = {x = 100, y = 300},
    api_key = '',
    batch_size = 5,
    tick_ms = 120,
    backoff_ms = 3000,
    cache_size = 200,
    filter_enabled = true,
    prohibited_dir = '',
    filter_channels = {Yell=true, Shout=true, Assist=true, AssistE=true},
    box_width = 520,
    box_pad_x = 8,
    box_pad_y = 8,
    bg = { enabled = true, path = '', alpha = 255, plate_color = {30,30,30} },
}
local settings = config.load(defaults)
if settings.bg.path == '' then
    settings.bg.path = windower.addon_path .. 'resources/bg.png'
end

local ui = texts.new()
ui:font(settings.font)
ui:size(settings.size)
ui:pos(settings.pos.x, settings.pos.y)
ui:bg_alpha(0)
ui:draggable(true)

local lines, zoning = {}, false
local function trim(s) return s and s:gsub('%s+$',''):gsub('^%s+','') or '' end

local function utf8_valid(s)
    local i, n = 1, #s
    while i <= n do
        local b1 = s:byte(i); if not b1 then return true end
        if b1 < 0x80 then i=i+1
        elseif b1 < 0xC2 then return false
        elseif b1 < 0xE0 then local b2=s:byte(i+1); if not b2 or b2<0x80 or b2>0xBF then return false end; i=i+2
        elseif b1 < 0xF0 then local b2,b3=s:byte(i+1),s:byte(i+2); if not b2 or not b3 or b2<0x80 or b2>0xBF or b3<0x80 or b3>0xBF then return false end; i=i+3
        elseif b1 < 0xF5 then local b2,b3,b4=s:byte(i+1),s:byte(i+2),s:byte(i+3); if not b2 or not b3 or not b4 or b2<0x80 or b2>0xBF or b3<0x80 or b3>0xBF or b4<0x80 or b4>0xBF then return false end; i=i+4
        else return false end
    end
    return true
end
local function ensure_utf8(s)
    if not s or s=='' then return '' end
    if utf8_valid(s) then return s end
    if windower and windower.from_shift_jis then
        local ok,out = pcall(windower.from_shift_jis, s)
        if ok and out and utf8_valid(out) then return out end
    end
    return s
end

local function utf8_iter(s)
    local i, n = 1, #s
    return function()
        if i > n then return nil end
        local b1 = s:byte(i); if not b1 then return nil end
        local cp
        if b1 < 0x80 then cp=b1; i=i+1
        elseif b1 < 0xE0 then local b2=s:byte(i+1) or 0; cp=(b1-0xC0)*0x40+(b2-0x80); i=i+2
        elseif b1 < 0xF0 then local b2=s:byte(i+1) or 0; local b3=s:byte(i+2) or 0; cp=(b1-0xE0)*0x1000+(b2-0x80)*0x40+(b3-0x80); i=i+3
        else local b2=s:byte(i+1) or 0; local b3=s:byte(i+2) or 0; local b4=s:byte(i+3) or 0; cp=(b1-0xF0)*0x40000+(b2-0x80)*0x1000+(b3-0x80)*0x40+(b4-0x80); i=i+4
        end
        return cp
    end
end

local function u8(n)
    if n < 0x80 then return string.char(n)
    elseif n < 0x800 then return string.char(0xC0+math.floor(n/0x40), 0x80+(n%0x40))
    elseif n < 0x10000 then return string.char(0xE0+math.floor(n/0x1000), 0x80+(math.floor(n/0x40)%0x40), 0x80+(n%0x40))
    else return string.char(0xF0+math.floor(n/0x40000), 0x80+(math.floor(n/0x1000)%0x40), 0x80+(math.floor(n/0x40)%0x40), 0x80+(n%0x40)) end
end
local function fold_width(s)
    local out = {}
    for cp in utf8_iter(s) do
        if cp == 0x3000 then cp = 0x20
        elseif cp >= 0xFF01 and cp <= 0xFF5E then cp = cp - 0xFEE0 end
        out[#out+1] = u8(cp)
    end
    return table.concat(out)
end

local function is_japanese(s)
    if not s or s=='' then return false end
    for cp in utf8_iter(s) do
        if (cp >= 0x3040 and cp <= 0x309F)
        or (cp >= 0x30A0 and cp <= 0x30FF)
        or (cp >= 0x31F0 and cp <= 0x31FF)
        or (cp >= 0x3400 and cp <= 0x9FFF)
        or (cp >= 0x3000 and cp <= 0x303F)
        or (cp >= 0xFF66 and cp <= 0xFF9D) then
            return true
        end
    end
    return false
end

local function chan_name(mode)
    if type(mode) == 'string' then return mode:lower() end
    local r = res.chat[mode]
    if r and r.english then return r.english:lower() end
    return 'unknown'
end

local CHAT_COLORS = {
    say        = {255,255,255},
    party      = {51, 153, 255},
    shout      = {255,128,  0},
    yell       = {255,255,  0},
    linkshell  = { 90, 220, 110},
    linkshell2 = {180, 240, 120},
    tell       = {255,128,255},
    diag       = {200,200,200},
    unknown    = {200,200,200},
}
local function colorize_text(rgb, text) return string.format('\\cs(%d,%d,%d)%s\\cr', rgb[1], rgb[2], rgb[3], text or '') end
local function color_for_mode(mode) local key = chan_name(mode) return CHAT_COLORS[key] or CHAT_COLORS.unknown end
local function colorize_translated(mode, text)
    if not text or text == '' then return '' end
    if text:find('^%[Offline%]') or text:find('^%[jpen%]') then return '\\cs(160,160,160)'..text..'\\cr' end
    return colorize_text(color_for_mode(mode), text)
end
local function timestamp_tag()
    return string.format('\\cs(255,255,255)[%s]\\cr', os.date('%H:%M'))
end

local function to_ascii(s) if not s or s=='' then return '' end s=s:gsub('“','"'):gsub('”','"'):gsub('’',"'"):gsub('–','-'):gsub('—','-') return (s:gsub('[\128-\255]','?')) end

-- Background using primitives
local plate_id = 'jpen_plate'
local bg_id    = 'jpen_bg'

local function prim_exists(name) return windower.prim.get_position(name) ~= nil end

local function box_dims()
    local x,y = ui:pos()
    local w = settings.box_width
    local line_h = math.floor(settings.size*1.3)
    local h = math.max(1, settings.max_lines)*line_h + settings.box_pad_y*2
    return math.floor(x) - settings.box_pad_x, math.floor(y) - settings.box_pad_y, w, h
end

local function plate_ensure()
    if not prim_exists(plate_id) then windower.prim.create(plate_id) end
end
local function plate_update()
    if zoning or not settings.enabled or #lines==0 then windower.prim.set_visibility(plate_id,false) return end
    plate_ensure()
    local x,y,w,h = box_dims()
    local c = settings.bg.plate_color or {30,30,30}
    windower.prim.set_color(plate_id, 255, c[1], c[2], c[3])
    windower.prim.set_size(plate_id, w, h)
    windower.prim.set_position(plate_id, x, y)
    windower.prim.set_visibility(plate_id, settings.bg.enabled)
end
local function plate_hide() if prim_exists(plate_id) then windower.prim.set_visibility(plate_id,false) end end

local function bg_ensure()
    if not prim_exists(bg_id) then windower.prim.create(bg_id) end
    windower.prim.set_texture(bg_id, settings.bg.path)
    windower.prim.set_color(bg_id, settings.bg.alpha or 255, 255, 255, 255)
end
local function bg_update()
    if zoning or not settings.bg.enabled or not settings.enabled or #lines==0 then
        if prim_exists(bg_id) then windower.prim.set_visibility(bg_id, false) end
        return
    end
    bg_ensure()
    local x,y,w,h = box_dims()
    windower.prim.set_size(bg_id, w, h)
    windower.prim.set_position(bg_id, x, y)
    windower.prim.set_visibility(bg_id, true)
end
local function bg_hide() if prim_exists(bg_id) then windower.prim.set_visibility(bg_id,false) end end
local function bg_set_name(name)
    local n = trim(name):gsub('%.png$',''); if n=='' then n='bg' end
    settings.bg.path = windower.addon_path .. 'resources/' .. n .. '.png'
    settings.bg.enabled = true
    config.save(settings)
    bg_ensure(); bg_update(); plate_update()
    windower.add_to_chat(207, '[jpen] Background set to '..n..'.png')
end

local function refresh_ui()
    if zoning or #lines == 0 or not settings.enabled then
        ui:hide(); plate_hide(); bg_hide()
    else
        local out = {}
        for i=#lines,1,-1 do out[#out+1] = lines[i] end
        ui:text(table.concat(out, '\n'))
        ui:show()
        plate_update(); bg_update()
    end
end

local function push_line(mode, sender, translated)
    local chan_rgb = color_for_mode(mode)
    local ch_name  = chan_name(mode):gsub('^%l', string.upper)
    local chan_label = colorize_text(chan_rgb, '['..ch_name..']')
    local label = ('%s %s %s : %s'):format(
        timestamp_tag(),
        chan_label,
        sender or 'Unknown',
        colorize_translated(mode, translated or '')
    )
    lines[#lines+1] = label
    if #lines > settings.max_lines then table.remove(lines,1) end
    refresh_ui()
end

-- Cache
local cache, order = {}, {}
local function cache_get(k) local v=cache[k]; if not v then return nil end for i=#order,1,-1 do if order[i]==k then table.remove(order,i) break end end table.insert(order,1,k); return v end
local function cache_put(k,v) if cache[k] then cache[k]=v for i=#order,1,-1 do if order[i]==k then table.remove(order,i) break end end table.insert(order,1,k) return end cache[k]=v table.insert(order,1,k) while #order>settings.cache_size do local old=table.remove(order) cache[old]=nil end end

-- Offline dict
local dict = {}
local function load_dict() local f=io.open(windower.addon_path..'data/dict.tsv','r'); if not f then return end for line in f:lines() do local jp,en=line:match('^(.-)\t(.-)$'); if jp and en and jp~='' and en~='' then dict[jp]=en end end f:close() end
load_dict()
local function dict_translate(s) if dict[s] then return dict[s] end if #s<=20 then for k,v in pairs(dict) do if s==k then return v end end end return nil end

-- Minimal JSON
local have_json,json=pcall(require,'json')
local function decode_json(body) if have_json and json and json.decode then local ok,obj=pcall(json.decode,body); if ok then return obj end end
    local i,n=1,#body
    local function skip() while true do local c=body:sub(i,i); if c==' ' or c=='\n' or c=='\r' or c=='\t' then i=i+1 else break end end end
    local function uch(n) if n<0x80 then return string.char(n) elseif n<0x800 then return string.char(0xC0+math.floor(n/0x40),0x80+(n%0x40)) else return string.char(0xE0+math.floor(n/0x1000),0x80+(math.floor(n/0x40)%0x40),0x80+(n%0x40)) end end
    local function strval() i=i+1 local out={} while i<=n do local c=body:sub(i,i) if c=='"' then i=i+1 return table.concat(out) end if c=='\\' then local d=body:sub(i+1,i+1) if d=='"' or d=='\\' or d=='/' then out[#out+1]=d i=i+2 elseif d=='b' then out[#out+1]='\b' i=i+2 elseif d=='f' then out[#out+1]='\f' i=i+2 elseif d=='n' then out[#out+1]='\n' i=i+2 elseif d=='r' then out[#out+1]='\r' i=i+2 elseif d=='t' then out[#out+1]='\t' i=i+2 elseif d=='u' then local h=tonumber(body:sub(i+2,i+5),16); i=i+6 if h then out[#out+1]=uch(h) end else i=i+1 end else out[#out+1]=c i=i+1 end end return table.concat(out) end
    local function numval() local s=i while i<=n and body:sub(i,i):match('[%+%-%d%.eE]') do i=i+1 end return tonumber(body:sub(s,i-1)) end
    local function parse() skip() local c=body:sub(i,i) if c=='{' then i=i+1 local t={} skip() if body:sub(i,i)=='}' then i=i+1 return t end while true do skip() local k=strval() skip() i=i+1 t[k]=parse() skip() local ch=body:sub(i,i) if ch=='}' then i=i+1 break end i=i+1 end return t elseif c=='[' then i=i+1 local a={} skip() if body:sub(i,i)==']' then i=i+1 return a end while true do a[#a+1]=parse() skip() local ch=body:sub(i,i) if ch==']' then i=i+1 break end i=i+1 end return a elseif c=='"' then return strval() elseif c=='t' then i=i+4 return true elseif c=='f' then i=i+5 return false elseif c=='n' then i=i+4 return nil else return numval() end end
    return parse()
end

-- Term filter
local filter_rules = {}
local function default_dir_candidates()
    local home = os.getenv('USERPROFILE') or ''
    return {
        home..'/Documents/My Games/FINAL FANTASY XI/ffxiuser',
        home..'/OneDrive/Documents/My Games/FINAL FANTASY XI/ffxiuser',
    }
end
local function resolve_prohibited_path()
    local base = settings.prohibited_dir
    if base and base ~= '' then return base..'/prohibited.txt' end
    for _,d in ipairs(default_dir_candidates()) do
        local p = d..'/prohibited.txt'
        local f = io.open(p,'r'); if f then f:close(); return p end
    end
    return nil
end
local function parse_flags_and_term(line)
    local f, rest = line:match('^%(([%a]+)%)%s*(.+)$')
    if not f then return {i=false,s=false}, trim(line) end
    local flags = {i=false,s=false}
    f = f:lower()
    if f:find('i',1,true) then flags.i = true end
    if f:find('s',1,true) then flags.s = true end
    return flags, trim(rest)
end
local function normalize_with_flags(s, flags)
    s = ensure_utf8(s); s = fold_width(s)
    if flags.s then s = s:gsub('%s+','') end
    if flags.i then s = s:lower() end
    return s
end
local function load_filter()
    filter_rules = {}
    local path = resolve_prohibited_path(); if not path then return end
    local f = io.open(path,'r'); if not f then return end
    local count = 0
    for line in f:lines() do
        line = trim(line or '')
        if line ~= '' then
            local flags, term = parse_flags_and_term(line)
            if term ~= '' then
                count = count + 1
                filter_rules[#filter_rules+1] = {flags=flags, pat=normalize_with_flags(term, flags)}
                if count >= 100 then break end
            end
        end
    end
    f:close()
end
load_filter()

local function channel_is_filtered(mode)
    local ch = chan_name(mode):gsub('^%l', string.upper)
    return not not settings.filter_channels[ch]
end
local function is_filtered(mode, text)
    if not settings.filter_enabled or not channel_is_filtered(mode) then return false end
    if #filter_rules == 0 then return false end
    for i=1,#filter_rules do
        local r = filter_rules[i]
        local hay = normalize_with_flags(text, r.flags)
        if hay:find(r.pat, 1, true) then return true end
    end
    return false
end

-- Queue + HTTP
local q,busy,api_down_until={},false,0
local last_tick=0
local function urlencode(str) str=tostring(str or ''):gsub('\n','\r\n'):gsub('([^%w _%%%-%.~])',function(c) return string.format('%%%02X',string.byte(c)) end) return str:gsub(' ','+') end
local function deepl_http(params) local resp={} local ok,code=https.request{ url='https://api-free.deepl.com/v2/translate', method='POST',
    headers={['Content-Type']='application/x-www-form-urlencoded; charset=UTF-8',['Content-Length']=tostring(#params),['Authorization']='DeepL-Auth-Key '..(settings.api_key or ''),['Accept-Encoding']='identity',['Host']='api-free.deepl.com',['User-Agent']='Windower4-jpen/0.70',['Connection']='close'},
    source=ltn12.source.string(params), sink=ltn12.sink.table(resp)} return ok,tonumber(code),table.concat(resp or '') end
local function deepl_once(text_utf8) if (settings.api_key or '')=='' then return nil,'no_key',nil end
    local req=table.concat({'target_lang=EN','source_lang=JA','text='..urlencode(text_utf8)},'&')
    local ok,code,body=deepl_http(req) if not ok or code~=200 then return nil,tostring(code or 'http'),body end
    local obj=decode_json(body) if obj and obj.translations and obj.translations[1] and obj.translations[1].text then return obj.translations[1].text,nil,body end
    return nil,'parse',body
end

-- De-dupe
local recent = {}
local function seen_recent(mode, sender, text)
    local now = socket.gettime()
    local key = tostring(mode)..'|'..tostring(sender)..'|'..tostring(text)
    local t0 = recent[key]
    recent[key] = now
    if t0 and now - t0 < 2.0 then return true end
    if math.random(1,50) == 1 then for k,ts in pairs(recent) do if now - ts > 6.0 then recent[k]=nil end end end
    return false
end

local function enqueue(mode, sender, jp_utf8)
    if is_filtered(mode, jp_utf8) then return end
    if seen_recent(mode, sender, jp_utf8) then return end
    local cached=cache_get(jp_utf8); if cached then push_line(mode, sender, cached); return end
    q[#q+1]={mode=mode, sender=sender, text=jp_utf8}
end

local function deepl_translate(batch)
    local texts_t={} for i=1,#batch do texts_t[i]=batch[i].text end
    local combined=table.concat(texts_t,'\n')
    local raw,err=deepl_once(combined) if not raw then return nil,err end
    local parts={} for s in tostring(raw):gmatch('([^\n]+)') do parts[#parts+1]=to_ascii(s) end
    if #parts ~= #batch then return nil,'split' end
    return parts
end

local function on_prerender()
    if not settings.enabled then
        plate_hide(); bg_hide(); return
    end
    local now=socket.gettime()*1000
    if now-last_tick<settings.tick_ms then
        plate_update(); bg_update(); return
    end
    last_tick=now
    plate_update(); bg_update()
    if busy or now<api_down_until or #q==0 then return end
    busy=true
    local batch={} for i=1,math.min(settings.batch_size,#q) do batch[#batch+1]=table.remove(q,1) end
    local result,err=deepl_translate(batch)
    if result then
        for i,tr in ipairs(result) do local it=batch[i]; cache_put(it.text,tr); push_line(it.mode,it.sender,tr) end
        busy=false; return
    end
    for _,it in ipairs(batch) do local off=dict_translate(it.text); if off then push_line(it.mode,it.sender,'[Offline] '..to_ascii(off)) else push_line(it.mode,it.sender,'[Offline] Translation unavailable') end end
    api_down_until=now+settings.backoff_ms
    busy=false
end
windower.register_event('prerender', on_prerender)

-- Zoning hide/show
local function set_zoning(v)
    zoning = v and true or false
    refresh_ui()
end
windower.register_event('zone change', function()
    set_zoning(true)
    if coroutine and coroutine.schedule then
        coroutine.schedule(function() set_zoning(false) end, 3)
    else
        -- fallback, will show again when next line arrives
        set_zoning(false)
    end
end)

-- Incoming chat
local function handle_message(mode, sender, msg_raw)
    if not mode or not msg_raw or msg_raw=='' then return end
    local name = sender and sender ~= '' and sender or 'Unknown'
    local expanded = ensure_utf8(windower.convert_auto_trans(msg_raw or ''))
    if is_filtered(mode, expanded) then return end
    if not is_japanese(expanded) then return end
    enqueue(mode, name, expanded)
end
windower.register_event('incoming chunk', function(id, data)
    if id ~= 0x017 or not settings.enabled then return end
    local p = packets.parse('incoming', data); if not p then return end
    local name = p['Sender Name'] or p.Sender or p['Sender'] or p['Name'] or 'Unknown'
    handle_message(p.Mode, name, p.Message)
end)

-- Outgoing text
local function parse_outgoing_channel(line)
    local l=line:lower()
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
        local who,msg=line:match('^/%S+%s+(%S+)%s+(.+)$'); return 'Tell', msg
    end
end
windower.register_event('outgoing text', function(text)
    if not settings.enabled or not text or text=='' then return end
    local ch,msg=parse_outgoing_channel(text)
    if not ch or not msg or msg=='' then return end
    if is_filtered(ch, msg) then return end
    local expanded = ensure_utf8(windower.convert_auto_trans(msg))
    if not is_japanese(expanded) then return end
    local me=windower.ffxi.get_player()
    enqueue(ch, me and me.name or 'You', expanded)
end)

-- Utils
local function file_exists(p) local f=io.open(p,'rb'); if f then f:close(); return true end return false end
local function hex_bytes(s, maxn) local t={} for i=1,math.min(maxn or 64,#s) do t[#t+1]=string.format('%02X',s:byte(i)) end return table.concat(t,' ') end
local function safe(s) return to_ascii(s or ''):gsub('[\r\n]',' ') end

-- Commands
windower.register_event('addon command', function(cmd, ...)
    cmd=(cmd or ''):lower(); local args={...}
    if cmd=='on' then
        settings.enabled=true; config.save(settings); refresh_ui()
    elseif cmd=='off' then
        settings.enabled=false; config.save(settings); refresh_ui()
    elseif cmd=='clear' then
        lines = {}; refresh_ui()
    elseif cmd=='addkey' then
        local key=trim(table.concat(args,' ')); if key~='' then settings.api_key=key; config.save(settings); windower.add_to_chat(207,'[jpen] API key saved.') else windower.add_to_chat(167,'[jpen] Usage: //jpen addkey YOUR_KEY') end
    elseif cmd=='addprohibited' then
        local folder = trim(table.concat(args,' ')):gsub('^"(.*)"$','%1')
        if folder=='' then windower.add_to_chat(207,'[jpen] Usage: //jpen addprohibited C:\\path\\to\\ffxiuser'); return end
        settings.prohibited_dir = folder; config.save(settings); load_filter()
        windower.add_to_chat(207,('[jpen] prohibited set. rules=%d path=%s'):format(#filter_rules, tostring(resolve_prohibited_path() or '(not found)')))
    elseif cmd=='reloadfilter' then
        load_filter(); windower.add_to_chat(207,('[jpen] filter reloaded. rules=%d path=%s'):format(#filter_rules, tostring(resolve_prohibited_path() or '(not found)')))
    elseif cmd=='filter' then
        local v=(args[1] or ''):lower()
        if v=='on' or v=='off' then settings.filter_enabled=(v=='on'); config.save(settings); windower.add_to_chat(207,('[jpen] filter %s'):format(settings.filter_enabled and 'on' or 'off'))
        else windower.add_to_chat(207,'[jpen] filter on|off') end
    elseif cmd=='diag' then
        local key=settings.api_key or ''
        local resp={} local ok,code=https.request{ url='https://api-free.deepl.com/v2/usage', method='GET',
            headers={['Authorization']='DeepL-Auth-Key '..key,['Accept-Encoding']='identity',['Host']='api-free.deepl.com',['User-Agent']='Windower4-jpen/0.70',['Connection']='close'},
            sink=ltn12.sink.table(resp)}
        windower.add_to_chat(207,('[jpen] https ok=%s code=%s bytes=%d rules=%d path=%s'):format(tostring(ok),tostring(code),#(table.concat(resp)),#filter_rules,tostring(resolve_prohibited_path() or '(none)')))
    elseif cmd=='test' then
        local raw=trim(table.concat(args,' ')); if raw=='' then raw='テストです。こんにちは。よろしくお願いします。' end
        local t=ensure_utf8(raw); local me=windower.ffxi.get_player(); enqueue('Diag', me and me.name or 'You', t); refresh_ui()
    elseif cmd=='tdiag' then
        local raw=trim(table.concat(args,' ')); if raw=='' then raw='テスト' end
        local t=ensure_utf8(raw); local out,err,body=deepl_once(t)
        if out then windower.add_to_chat(207,('[jpen] tdiag text="%s" bytes=%s'):format(safe(out),hex_bytes(out))); push_line('Diag','Diag',to_ascii(out))
        else windower.add_to_chat(167,('[jpen] translate failed code=%s body=%s'):format(tostring(err),safe(body or ''))) end
    elseif cmd=='raw' then
        local raw=trim(table.concat(args,' ')); if raw=='' then raw='テスト' end
        local t=ensure_utf8(raw); local req=table.concat({'target_lang=EN','source_lang=JA','text='..urlencode(t)},'&'); local ok,code,body=deepl_http(req)
        windower.add_to_chat(207,('[jpen] raw code=%s body_hex=%s'):format(tostring(code),hex_bytes(body or '',64))); windower.add_to_chat(207,('[jpen] raw body_ascii=%s'):format(safe(body or '')))
    elseif cmd=='bg' then
        local name = trim(table.concat(args,' ')):lower()
        if name == '' or name == 'on' then
            settings.bg.enabled = true; config.save(settings); refresh_ui(); windower.add_to_chat(207,'[jpen] Background enabled.')
        elseif name == 'off' then
            settings.bg.enabled = false; config.save(settings); refresh_ui(); windower.add_to_chat(207,'[jpen] Background disabled.')
        else
            bg_set_name(name)
        end
    elseif cmd=='bgpath' then
        local p = trim(table.concat(args, ' '))
        if p=='' then windower.add_to_chat(207,'[jpen] Usage: //jpen bgpath <file.png>'); return end
        settings.bg.path = p; settings.bg.enabled = true; config.save(settings); refresh_ui()
        windower.add_to_chat(207,'[jpen] Background path set.')
    elseif cmd=='bgalpha' then
        local n = tonumber(args[1] or '')
        if n and n >= 0 and n <= 255 then
            settings.bg.alpha = n; config.save(settings)
            if prim_exists(bg_id) then windower.prim.set_color(bg_id, n, 255,255,255) end
            windower.add_to_chat(207, '[jpen] Background alpha set to '..n..'.')
        else
            windower.add_to_chat(167, '[jpen] Usage: //jpen bgalpha 0-255')
        end
    elseif cmd=='dims' then
        local _,_,w,h = box_dims()
        windower.add_to_chat(207, ('[jpen] Box size width=%d height=%d'):format(w,h))
    elseif cmd=='bgdiag' then
        local p = settings.bg.path or '(nil)'
        windower.add_to_chat(207, ('[jpen] bgdiag path=%s exists=%s enabled=%s'):format(
            tostring(p), tostring(file_exists(p)), tostring(settings.bg.enabled)))
    else
        windower.add_to_chat(207,'[jpen] Commands: //jpen on | off | clear | addkey KEY | addprohibited <folder> | reloadfilter | filter on|off | test [jp] | diag | tdiag [jp] | raw [jp] | bg on|off|<name> | bgpath <file> | bgalpha 0-255 | dims | bgdiag')
    end
end)

windower.register_event('load', function() refresh_ui() end)
windower.register_event('unload', function() ui:hide(); plate_hide(); bg_hide() end)

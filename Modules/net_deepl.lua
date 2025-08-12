local https = require('ssl.https')
local ltn12 = require('ltn12')

local M = {}

local function urlencode(str)
    str = tostring(str or ''):gsub('\n','\r\n'):gsub('([^%w _%%%-%.~])', function(c)
        return string.format('%%%02X', string.byte(c))
    end)
    return str:gsub(' ','+')
end

local have_json, json = pcall(require, 'json')
local function decode_json(body)
    if have_json and json and json.decode then
        local ok, obj = pcall(json.decode, body)
        if ok then return obj end
    end
    local t = body:match('"text"%s*:%s*"([^"]-)"')
    if t then return { translations = { { text = t } } } end
end

local function deepl_http(api_key, params)
    local buf = {}
    local ok, code = https.request{
        url    = 'https://api-free.deepl.com/v2/translate',
        method = 'POST',
        headers = {
            ['Content-Type']  = 'application/x-www-form-urlencoded; charset=UTF-8',
            ['Content-Length'] = tostring(#params),
            ['Authorization']  = 'DeepL-Auth-Key ' .. (api_key or ''),
            ['Accept-Encoding'] = 'identity',
            ['Host']           = 'api-free.deepl.com',
            ['User-Agent']     = 'Windower4-jpen',
        },
        source = ltn12.source.string(params),
        sink   = ltn12.sink.table(buf),
    }
    return ok, tonumber(code), table.concat(buf or {})
end

local function translate_once(api_key, text_utf8)
    if (api_key or '') == '' then return nil, 'no_key' end
    local req = 'target_lang=EN&source_lang=JA&text=' .. urlencode(text_utf8)
    local ok, code, body = deepl_http(api_key, req)
    if not ok or code ~= 200 then return nil, tostring(code or 'http') end
    local obj = decode_json(body)
    local t = obj and obj.translations and obj.translations[1] and obj.translations[1].text
    if not t then return nil, 'parse' end
    return t, nil
end

function M.translate_batch(api_key, texts)
    if type(texts) ~= 'table' or #texts == 0 then return {}, nil end
    local combined = table.concat(texts, '\n')
    local raw, err = translate_once(api_key, combined)
    if not raw then return nil, err end
    local out = {}
    for s in tostring(raw):gmatch('([^\n]+)') do out[#out+1] = s end
    -- be forgiving if the API collapses trailing newlines
    while #out < #texts do out[#out+1] = '' end
    return out, nil
end

return M

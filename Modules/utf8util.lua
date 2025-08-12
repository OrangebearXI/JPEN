local M = {}

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

function M.ensure_utf8(s)
    if not s or s=='' then return '' end
    if utf8_valid(s) then return s end
    if windower and windower.from_shift_jis then
        local ok,out = pcall(windower.from_shift_jis, s)
        if ok and out and utf8_valid(out) then return out end
    end
    return s
end

function M.ascii_only(s)
    for i = 1, #s do if s:byte(i) >= 0x80 then return false end end
    return true
end

function M.utf8_iter(s)
    local i, n = 1, #s
    return function()
        if i > n then return nil end
        local b1 = s:byte(i); if not b1 then return nil end
        local cp
        if b1 < 0x80 then cp=b1; i=i+1
        elseif b1 < 0xE0 then local b2=s:byte(i+1) or 0; cp=(b1-0xC0)*0x40+(b2-0x80); i=i+2
        elseif b1 < 0xF0 then local b2=s:byte(i+1) or 0; local b3=s:byte(i+2) or 0; cp=(b1-0xE0)*0x1000+(b2-0x80)*0x40+(b3-0x80); i=i+3
        else local b2=s:byte(i+1) or 0; local b3=s:byte(i+2) or 0; local b4=s:byte(i+3) or 0; cp=(b1-0xF0)*0x40000+(b2-0x80)*0x1000+(b3-0x80)*0x40+(b4-0x80); i=i+4 end
        return cp
    end
end

local function u8(n)
    if n < 0x80 then
        return string.char(n)
    elseif n < 0x800 then
        return string.char(0xC0 + math.floor(n / 0x40),
                           0x80 + (n % 0x40))
    elseif n < 0x10000 then
        return string.char(0xE0 + math.floor(n / 0x1000),
                           0x80 + (math.floor(n / 0x40) % 0x40),
                           0x80 + (n % 0x40))
    else
        return string.char(0xF0 + math.floor(n / 0x40000),
                           0x80 + (math.floor(n / 0x1000) % 0x40),
                           0x80 + (math.floor(n / 0x40) % 0x40),
                           0x80 + (n % 0x40))
    end
end

function M.fold_width(s)
    local out = {}
    for cp in M.utf8_iter(s) do
        if cp == 0x3000 then
            cp = 0x20
        elseif cp >= 0xFF01 and cp <= 0xFF5E then
            cp = cp - 0xFEE0
        end
        out[#out+1] = u8(cp)
    end
    return table.concat(out)
end

function M.is_japanese(s)
    if not s or s=='' then return false end
    for cp in M.utf8_iter(s) do
        if (cp >= 0x3040 and cp <= 0x309F) or
           (cp >= 0x30A0 and cp <= 0x30FF) or
           (cp >= 0x31F0 and cp <= 0x31FF) or
           (cp >= 0x3400 and cp <= 0x9FFF) or
           (cp >= 0x3000 and cp <= 0x303F) or
           (cp >= 0xFF66 and cp <= 0xFF9D) then
            return true
        end
    end
    return false
end

return M

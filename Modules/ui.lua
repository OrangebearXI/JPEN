local texts = require('texts')
local socket = require('socket')

local M = {}

function M.new(opts)
    local self = {}

    local t = texts.new()
    t:font(opts.font)
    t:size(opts.size)
    t:pos(opts.pos.x, opts.pos.y)
    t:bg_alpha(0)
    t:draggable(true)

    local bg_id = 'jpen_bg'
    local bg_created = false

	local width     = opts.box_width
	local pad_x     = opts.box_pad_x
	local private_pad_y = opts.box_pad_y
	local overscan  = opts.overscan_y or 0
    local line_gap  = opts.line_gap
    local fsize     = opts.size

    local last_text = ''
    local measured_h, wait_ticks = 0, 0
    local force_ticks = 0
    local need_bg = false
    local show_bg = opts.bg_enabled and true or false

    local last = {x=nil,y=nil,w=nil,h=nil, visible=false}
    local cached_pos = {x=opts.pos.x, y=opts.pos.y}
    local pos_due = 0
    local bg_alpha = opts.bg_alpha or 255
    local bg_path  = opts.bg_path or ''

    local function one_line_height()
        return math.ceil(fsize * 1.35) + line_gap
    end

    local function mark(force)
        need_bg = true
        if force then force_ticks = 2 end
    end

    local function get_pos()
        local now = socket.gettime()
        if now >= pos_due then
            cached_pos.x, cached_pos.y = t:pos()
            pos_due = now + 0.5
        end
        return cached_pos.x, cached_pos.y
    end

    local function ensure_bg()
        if not bg_created then
            windower.prim.create(bg_id)
            bg_created = true
        end
    end

    local function warm()
        if not bg_path or bg_path == '' then return end
        ensure_bg()
        windower.prim.set_texture(bg_id, bg_path)
        local x,y = get_pos()
        local h = math.max(one_line_height(), measured_h > 0 and measured_h or one_line_height())
        local x0 = math.floor(x) - pad_x
        local y0 = math.floor(y) - private_pad_y
        windower.prim.set_size(bg_id, width, h + private_pad_y * 2 + overscan)
        windower.prim.set_position(bg_id, x0, y0)
        windower.prim.set_color(bg_id, bg_alpha, 255,255,255)
        windower.prim.set_visibility(bg_id, false)
        last.x, last.y, last.w, last.h = x0, y0, width, h
        last.visible = false
        mark(true)
    end

    local function bg_update()
        if not need_bg and force_ticks == 0 then return end
        if not show_bg or last_text == '' then
            if bg_created then windower.prim.set_visibility(bg_id, false) end
            last.visible = false
            need_bg = false
            return
        end
        ensure_bg()
        if bg_path and bg_path ~= '' then windower.prim.set_texture(bg_id, bg_path) end

        local x,y = get_pos()
        local h = (measured_h > 0 and measured_h or one_line_height())
        local x0 = math.floor(x) - pad_x
        local y0 = math.floor(y) - private_pad_y
        local oh = h + private_pad_y * 2 + overscan

        if not last.visible then windower.prim.set_visibility(bg_id, true); force_ticks = 2 end
        if force_ticks > 0 or last.x ~= x0 or last.y ~= y0 or last.w ~= width or last.h ~= oh then
            windower.prim.set_size(bg_id, width, oh)
            windower.prim.set_position(bg_id, x0, y0)
            last.x, last.y, last.w, last.h = x0, y0, width, oh
        end
        if force_ticks > 0 then force_ticks = force_ticks - 1 end
        last.visible = true
        need_bg = false
    end

    function self:set_text(text, bg_enable)
        show_bg = not not bg_enable
        if not text or text == '' then
            measured_h, wait_ticks = 0, 0
            if last_text ~= '' then t:text(''); last_text = '' end
            t:hide()
            if bg_created then windower.prim.set_visibility(bg_id, false) end
            last.visible = false
            return
        end
        if text ~= last_text then
            t:text(text)
            last_text = text
            measured_h = 0
            wait_ticks = 2
            mark(true)
        end
        t:show()
    end

    function self:on_prerender(zoning)
        if zoning then return end
        if wait_ticks > 0 then
            wait_ticks = wait_ticks - 1
            if wait_ticks == 0 then
                local _, eh = t:extents()
                if eh and eh > 0 then
                    local lines = 1
                    for _ in last_text:gmatch('\n') do lines = lines + 1 end
                    measured_h = math.max(math.ceil(eh), lines * one_line_height())
                    mark(true)
                end
            end
        end
        bg_update()
    end

    function self:warm() warm() end
    function self:hide() self:set_text('', show_bg) end

    function self:set_bg_path(p)
        bg_path = p or ''
        warm()
    end
    function self:set_bg_alpha(a)
        bg_alpha = a or 255
        ensure_bg()
        windower.prim.set_color(bg_id, bg_alpha, 255,255,255)
        mark(true)
    end
    function self:set_bg_enabled(v)
        show_bg = not not v
        mark(true)
    end

    function self:set_box(o)
        width    = o.box_width or width
        pad_x    = o.box_pad_x or pad_x
        private_pad_y = o.box_pad_y or private_pad_y
        overscan = o.overscan_y or overscan
        mark(true)
    end

    function self:info()
        local x,y = t:pos()
        local _, eh = t:extents()
        return {x=x,y=y}, {h=eh}
    end

    function self:text_height_for_current()
        local _, eh = t:extents(); eh = eh or 0
        local lines = 1
        for _ in last_text:gmatch('\n') do lines = lines + 1 end
        local h = measured_h > 0 and measured_h or (lines * one_line_height())
        return h + private_pad_y * 2 + overscan
    end

    return self
end

return M

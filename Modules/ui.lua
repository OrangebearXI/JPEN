local texts  = require('texts')
local socket = require('socket')

local M = {}

function M.new(opts)
    local self = {}

    -- texts object
    local t = texts.new()
    t:font(opts.font)
    t:size(opts.size)
    t:pos(opts.pos.x, opts.pos.y)
    t:bg_alpha(0)
    t:draggable(true)

    -- background primitive
    local bg_id        = 'jpen_bg'
    local bg_created   = false
    local last_tex_path = nil

    -- layout
    local width         = opts.box_width
    local pad_x         = opts.box_pad_x
    local private_pad_y = opts.box_pad_y
    local overscan      = opts.overscan_y or 6          -- base bottom gap
    local bottom_per_line = opts.bottom_per_line or 1    -- extra bottom px per additional line
    local line_gap      = opts.line_gap
    local fsize         = opts.size

    -- state
    local last_text   = ''
    local measured_h  = 0
    local wait_ticks  = 0
    local force_ticks = 0
    local show_bg     = opts.bg_enabled and true or false

    local last = { x=nil, y=nil, w=nil, h=nil, visible=false }
    local bg_alpha = opts.bg_alpha or 255
    local bg_path  = opts.bg_path or ''

    ----------------------------------------------------------------
    -- Calibrate true per-line height for this font and size
    ----------------------------------------------------------------
    local line_h = nil
    local function calibrate_line_height()
        local probe = texts.new()
        probe:font(opts.font)
        probe:size(opts.size)
        probe:bg_alpha(0)
        probe:pos(-4000, -4000)
        probe:text('Ag')
        probe:show()
        local _, eh = probe:extents()
        probe:hide()
        local heuristic = math.ceil(fsize * 1.35)
        line_h = math.max((eh and math.ceil(eh) or 0), heuristic) + (line_gap or 0)
    end
    calibrate_line_height()

    local function count_lines(s)
        local n = 1
        for _ in s:gmatch('\n') do n = n + 1 end
        return n
    end

    ----------------------------------------------------------------
    -- Helpers
    ----------------------------------------------------------------
    local function round(x) return math.floor(x + 0.5) end
    local function get_pos()
        local tx, ty = t:pos()
        local rx, ry = round(tx), round(ty)
        if rx ~= tx or ry ~= ty then
            t:pos(rx, ry)
        end
        return rx, ry
    end

    local function ensure_bg()
        if not bg_created then
            windower.prim.create(bg_id)
            bg_created = true
        end
    end

    -- Pre-size even if texture path not set yet
    local function warm()
        ensure_bg()
        if bg_path and bg_path ~= '' then
            windower.prim.set_texture(bg_id, bg_path)
            last_tex_path = bg_path
        end
        local x, y = get_pos()
        local lines = 1
        local oh   = line_h + private_pad_y * 2 + overscan + bottom_per_line * (lines - 1)
        local x0   = x - pad_x
        local y0   = y - private_pad_y

        windower.prim.set_size(bg_id, width, oh)
        windower.prim.set_position(bg_id, x0, y0)
        windower.prim.set_color(bg_id, bg_alpha, 255, 255, 255)
        windower.prim.set_visibility(bg_id, false)

        last.x, last.y, last.w, last.h = x0, y0, width, oh
        last.visible = false
        force_ticks  = 2
    end

    -- Resize and move first, then reveal. Retarget texture only on change.
    local function bg_update()
        if not show_bg or last_text == '' then
            if bg_created then windower.prim.set_visibility(bg_id, false) end
            last.visible = false
            return
        end

        ensure_bg()
        if bg_path and bg_path ~= '' and bg_path ~= last_tex_path then
            windower.prim.set_texture(bg_id, bg_path)
            last_tex_path = bg_path
            force_ticks = 2
        end

        local x, y = get_pos()
        local h    = (measured_h > 0) and measured_h or line_h
        local lines = count_lines(last_text)
        local oh   = h + private_pad_y * 2 + overscan + bottom_per_line * (lines - 1)
        local x0   = x - pad_x
        local y0   = y - private_pad_y

        local need_resize = (force_ticks > 0)
                         or last.x ~= x0 or last.y ~= y0
                         or last.w ~= width or last.h ~= oh
        if need_resize then
            windower.prim.set_size(bg_id, width, oh)
            windower.prim.set_position(bg_id, x0, y0)
            last.x, last.y, last.w, last.h = x0, y0, width, oh
        end

        if not last.visible then
            windower.prim.set_visibility(bg_id, true)
            force_ticks = 2
        end

        if force_ticks > 0 then force_ticks = force_ticks - 1 end
        last.visible = true
    end

    ----------------------------------------------------------------
    -- Public API
    ----------------------------------------------------------------
    -- Provisional size from line count, refine next frame via extents()
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
            local lines = count_lines(last_text)
            measured_h  = math.max(lines * line_h, line_h)
            wait_ticks  = 1
            force_ticks = 2
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
                    local lines = count_lines(last_text)
                    local min_h = math.max(lines * line_h, line_h)
                    measured_h  = math.max(math.ceil(eh), min_h)
                    force_ticks = 2
                end
            end
        end

        bg_update()
    end

    -- controls
    function self:warm() warm() end
    function self:hide() self:set_text('', show_bg) end

    function self:set_bg_path(p)
        bg_path = p or ''
        warm()
    end

    function self:set_bg_alpha(a)
        bg_alpha = a or 255
        ensure_bg()
        windower.prim.set_color(bg_id, bg_alpha, 255, 255, 255)
        force_ticks = 2
    end

    function self:set_bg_enabled(v)
        show_bg = not not v
        force_ticks = 2
    end

    function self:set_box(o)
        width            = o.box_width or width
        pad_x            = o.box_pad_x or pad_x
        private_pad_y    = o.box_pad_y or private_pad_y
        overscan         = o.overscan_y or overscan
        bottom_per_line  = (o.bottom_per_line ~= nil) and o.bottom_per_line or bottom_per_line
        force_ticks      = 2
    end

    function self:info()
        local x, y = t:pos()
        local _, eh = t:extents()
        return {x=x,y=y}, {h=eh}
    end

    function self:text_height_for_current()
        local _, eh = t:extents(); eh = eh or 0
        local lines = count_lines(last_text)
        local h = measured_h > 0 and measured_h or (lines * line_h)
        return h + private_pad_y * 2 + overscan + bottom_per_line * (lines - 1)
    end

    return self
end

return M

local M = {}

function M.new(capacity)
    local self = {}
    local cap = capacity or 200
    local map, order = {}, {}

    function self.get(k)
        local v = map[k]; if not v then return nil end
        for i = #order, 1, -1 do
            if order[i] == k then table.remove(order, i) break end
        end
        table.insert(order, 1, k)
        return v
    end

    function self.put(k, v)
        if map[k] then
            map[k] = v
            for i = #order, 1, -1 do
                if order[i] == k then table.remove(order, i) break end
            end
            table.insert(order, 1, k)
            return
        end
        map[k] = v
        table.insert(order, 1, k)
        while #order > cap do
            local old = table.remove(order)
            map[old] = nil
        end
    end

    function self.set_capacity(n)
        cap = math.max(1, tonumber(n) or cap)
    end

    return self
end

return M

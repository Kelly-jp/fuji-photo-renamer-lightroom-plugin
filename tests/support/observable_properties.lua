local function properties(initial)
    local values, observers = {}, {}
    for key, value in pairs(initial or {}) do values[key] = value end
    local methods = {}
    function methods:addObserver(key, owner, callback)
        observers[key] = observers[key] or {}
        observers[key][owner] = callback
    end
    function methods:removeObserver(key, owner) if observers[key] then observers[key][owner] = nil end end
    local proxy
    proxy = setmetatable({}, {
        __index = function(_, key) return methods[key] or values[key] end,
        __newindex = function(_, key, value)
            if values[key] == value then return end
            values[key] = value
            for owner, callback in pairs(observers[key] or {}) do callback(owner, proxy, key, value) end
        end,
    })
    return proxy, function()
        local total = 0
        for _, entries in pairs(observers) do for _ in pairs(entries) do total = total + 1 end end
        return total
    end
end
return properties

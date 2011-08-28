--[[
    MasterLua Authserver Text Database backend
]]

local function external_load(conf)
    users = {}
    local users_lc= {}
    dofile(conf.file)

    for domain,user in pairs(users) do
        users_lc[domain] = {}
        for name,conf in pairs(user) do
            users_lc[domain][name:lower()] = conf
        end
    end

    users = {}

    return users_lc, nil
end

local function external_close()
    users = {}
end

return { load = external_load, close = external_close}

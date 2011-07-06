local port = 25787
local ip = "0.0.0.0"
local sauermaster_host = "localhost"
local sauermaster_port = 25787
local debug_mode = true

local challenges = {}
local users = {}

-- Add 'suckerserv' domain
users["suckerserv"] =  {}
-- Add 'suckerserv:admin' domain, useless if using SuckerServ trunk, just activate auth/privileges module
users["suckerserv:admin"] =  {}

-- Add 'piernov' user in 'suckerserv' domain with public key '+6bf4eb8e23fa8447098eeaca4f4f5eafce25cedd4a5616a0' and right 'admin'
users["suckerserv"]["piernov"] = {"+6bf4eb8e23fa8447098eeaca4f4f5eafce25cedd4a5616a0", "admin"}
-- Copy 'piernov' user to 'suckerserv:admin' domain, useless if using SuckerServ trunk, just activate auth/privileges module
users["suckerserv:admin"]["piernov"] = users["suckerserv"]["piernov"] 
              
require("net")
require("crypto")
local _ = require "script/package/underscore"
local master = {}
master.server = net.tcp_acceptor(ip, port)
master.client = net.tcp_client()

-- function readData(client)
-- print("test")
    -- master.client:async_read_until("\n", function(data)
    -- print("test")
        -- if data then
        -- print("test")
            -- print(data)
            -- irc:readData(irc.client)
        -- else
            -- master:handleError("Read error")
        -- end
    -- end)
-- end

-- master.client:async_connect(sauermaster_host, sauermaster_port, function(errmsg) 
    -- if errmsg then
        -- master:handleError(errmsg)
        -- return
    -- end
-- end)

-- Generate chalauth challenge from a public key
function generate_challenge(key)
    local key = crypto.sauerecc.key(key)
    local gen_challenge = key:generate_challenge()
    return gen_challenge
end

-- Print debug messages
local function print_debug(msg)
    if debug_mode then
        print(string.format("MASTER DEBUG %s", msg))
    end
end

--Handle any errors.
function master:handleError(errmsg, retry)
    if not errmsg then return end
    retry = retry or WAIT_TO_RECONNECT
    print_debug("[Error] : " .. errmsg)
end

-- Send a response to the client
function sendmsg(msg)
    print_debug("[Output] : " .. msg)
    if not allow_stream then return end
    masterserver:async_send(msg .. "\n", function(success) end)
end

-- Accept client connection and read data sent
local function accept_next(master_server)
	master_server:async_accept(function(server)
		masterserver = server

		print_debug("[Input] : " .. "connection accepted")
		allow_stream = true
		master:readData()
			
		accept_next(master.server)
    end)
end

-- Read data from client
function master:readData()
	masterserver:async_read_until("\n", function(data)
        if data then
            master:processData(master.server, data)
            master:readData(master.server)
        else
            master:handleError("Read error")
        end
	end)
end

--Process data read from the client.
function master:processData(server, data)

    print_debug("[Input] : " .. data)
    
	-- List handler
	if data.find(data,"list") then
		sendmsg(script)
        masterserver:close()
	end
    
	-- ReqAuth Handler
	if string.match(data,"reqauth %d+ %w+ .*") then
        local arguments = _.to_array(string.gmatch(data, "[^ \n]+"))
        local request_id, name, domain = tonumber(arguments[2]), arguments[3], (arguments[4] or "")
        if not users[domain] then print_debug("[AUTH] auth n°"..request_id.." Domain "..domain.." doesn't exist!")  return end
        if not users[domain][name] or not users[domain][name][1] then print_debug("[AUTH] auth n°"..request_id.." User "..name.." doesn't exist!") return end
        challenges[request_id] = generate_challenge(users[domain][name][1])
        local challenge_str = challenges[request_id]:to_string()
        print_debug(string.format("[AUTH] Attempting auth n°%d for '%s@%s' from %s", request_id, name, domain or "", ip or "localhost"))
        sendmsg(string.format("chalauth %i %s", request_id, challenge_str))
    end
    
    -- ConfAuth Handler
    if string.match(data, "confauth %d+ .+") then
        local arguments = _.to_array(string.gmatch(data, "[^ \n]+"))
        local request_id, answer = tonumber(arguments[2]), arguments[3]
        if not challenges[request_id] then return end
        local challenge_expected_answer = challenges[request_id]:expected_answer(answer)
        if challenge_expected_answer then 
            sendmsg(string.format("succauth %d", request_id))
            print_debug(string.format("[AUTH] Succeded auth n°%d with answer %s", request_id, answer))
        else
            sendmsg(string.format("failauth %d", request_id))
            print_debug(string.format("[AUTH] Failed auth n°%d with answer %s", request_id, answer))
        end
        table.remove(challenges, request_id)
    end
    
    -- QueryId Handler
    if string.match(data, "QueryId %d+ %w+ .*") then
        local arguments = _.to_array(string.gmatch(data, "[^ \n]+"))
        local request_id, name, domain = tonumber(arguments[2]), arguments[3], (arguments[4] or "")
        if not users[domain] then 
            sendmsg(string.format("DomainNotFound %d", request_id))
            print_debug(string.format("[AUTH] auth n°%s: Domain '%s' doesn't exist!", request_id, domain))
            return 
        end
        if not users[domain][name] or not users[domain][name][1] then
            sendmsg(string.format("NameNotFound %d", request_id))
            print_debug(string.format("[AUTH] auth n°%s: User '%s' doesn't exist in domain '%s' !", request_id, name, domain))
            return 
        end
        sendmsg(string.format("FoundId %d %s", request_id, users[domain][name][2]))
        print_debug(string.format("[AUTH] auth n°%s: User '%s' found in domain '%s' with '%s' rights", request_id, name, domain, users[domain][name][2]))
    end

end 

print("*-*+*-* Sauerbraten MasterServer listening on " .. ip .. ":" .. port .." *-*+*-*")
file = assert(io.open("sauer_masterscript", "r"))
script = file:read("*all")
master.server:listen()

accept_next(master.server)

    -- master.client:async_send("list", function(errmsg)
        -- if errmsg then
            -- master:handleError(errmsg)
            -- return 
        -- end
    -- end)
    
    -- readData(master.client)

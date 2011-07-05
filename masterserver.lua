local port = 25787
local ip = "0.0.0.0"
local sauermaster_host = "localhost"
local sauermaster_port = 25787
local debug_mode = true

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



        for k,v in pairs(crypto) do print(k,v) end
                for k,v in pairs(crypto.sauerecc) do print(k,v) end
print(crypto.sauerecc.key("test"))

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
    print_debug("[handleError] : " .. errmsg)
end

-- Send a response to the client
function sendmsg(msg)
	if not allow_stream then return end
    masterserver:async_send(msg, function(success) end)
end

-- Accept client connection and read data sent
local function accept_next(master_server)
	master_server:async_accept(function(server)
		masterserver = server

		print_debug("[Server Input] : " .. "connection accepted")
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
            -- master:readData(master.client)
        else
            master:handleError("Read error")
        end
	end)
end

--Process data read from the client.
function master:processData(server, data)

    print_debug("[Server Input] : " .. data)
    
	-- List handler
	if data.find(data,"list") then
		sendmsg(script)
        print_debug("[Server Output] : " .. script)
        masterserver:close()
	end
    
	-- ReqAuth Handler
	if string.match(data,"reqauth (.+) (.+)") then
        local arguments = _.to_array(string.gmatch(data, "[^ \n]+"))
        local request_id = tonumber(arguments[2])
        local name = arguments[3]
        local domain = arguments[4] or ""
        local challenge = crypto.tigersum(math.random())
        print(challenge)
        print(strinf.format("%s: attempting \"%s\"@\"%s\" as %u from %s", ct or "-", name, domain or "", request_id, ip or "localhost"))
        for k,v in ipairs(arguments) do print(k,v) end
        for k,v in pairs(crypto) do print(k,v) end
        sendmsg(string.format("chalauth %i %s", request_id, challenge))
    end
    
    -- ConfAuth Handler
    if string.match(data, "confauth (.+) (.+)") then
        local arguments = _.to_array(string.gmatch(data, "[^ \n]+"))
        for k,v in ipairs(arguments) do print(k,v) end
    end
end 

print("*-*+*-* Sauerbraten MasterServer listening on " .. ip .. ":" .. port .." *-*+*-*")
file = assert(io.open("sauer_masterscript", "r"))
script = file:read("*all")
master.server:listen()

accept_next(master.server)

-- local key = crypto.sauerecc.key(user.public_key)

    -- master.client:async_send("list", function(errmsg)
        -- if errmsg then
            -- master:handleError(errmsg)
            -- return 
        -- end
    -- end)
    
    -- readData(master.client)
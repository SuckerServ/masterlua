package.path = package.path .. ";script/package/?.lua" -- Required to load the underscore library
package.cpath = package.cpath .. ";lib/lib?.so" -- Requiered to load the liblua_mysql.so library

--[[ Confiruation Part ]]--

local port = 28787                         -- Port to bind to
local ip = "0.0.0.0"                       -- IP address to bind to
local sauermaster_host = "sauerbraten.org" -- Host of the main masterserver to get the serverlist
local sauermaster_port = 28787             -- Port of the main masterserver
local debug_mode = true                    -- Print debug information

local db = {} -- Initialize the db table

db.type = "text" -- Type of the database: "text" or "mysql"

db.mysql = dofile("mysql.lua") -- Load the MySQL backend
db.text = dofile("text.lua")

-- MySQL Configuration
db.mysql.host = "localhost"             -- Host of the MySQL server
db.mysql.port = "3306"                  -- Port of the MySQL server
db.mysql.name = "suckerserv_authserver" -- Name of the dedicated database
db.mysql.user = "suckerserv"            -- User that have a read access to the database
db.mysql.pass = "suckerserv"            -- Password for the above user
db.mysql.install = false                -- If true, add the content of the "mysql_schema.sql" to the database
db.mysql.schema = "mysql_schema.sql"    -- MySQL database schema file to install if db.mysql.install is true

-- Text database configuration
db.text.file = "auth_db" -- Text database file

--[[ Script Part ]]--

local challenges = {} -- Table used to store challenge when auth is requested
local users = {}      -- Main users database
local conoutf = {}    -- Table used to store console output functions

require("net")    -- Load the network library
require("crypto") -- Load the cryptographic library to resolve challenges for authentification

local _ = require "underscore"                           -- Load the underscore library to split arguments
local master = {}                                        -- Initialize the master table for the listening server
master.server, socket_error = net.tcp_acceptor(ip, port) -- Bind the IP and Port to the listener. If it fails, error is saved in "socket_error" and printed, then the script halt
local sauermaster = {}                                   -- Initialize the sauermaster table for the masterserver client to get the server list
sauermaster.client = net.tcp_client()                    -- Initialize the masterserver client

-- Print error messages
function conoutf.error(msg, ...)
    msg = string.format(msg, ...)
    if debug_mode then
        print(string.char(27) .. "[" .. "31" .. "m" .. string.char(27) .. "[" .. "1" .. "m" .. os.date("%x %X") .. " [Error]   | " .. msg .. string.char(27) .. "[" .. "0" .. "m")
    end
end

-- Print info messages
function conoutf.warning(msg, ...)
    msg = string.format(msg, ...)
    if debug_mode then
        print(string.char(27) .. "[" .. "33" .. "m" .. os.date("%x %X") .. " [Warning] | " .. msg .. string.char(27) .. "[" .. "0" .. "m")
    end
end

-- Print info messages
function conoutf.info(msg, ...)
    msg = string.format(msg, ...)
    if debug_mode then
        print(string.char(27) .. "[" .. "34" .. "m" .. os.date("%x %X") .. " [Info]    | " .. msg .. string.char(27) .. "[" .. "0" .. "m")
    end
end

-- Print debug messages
function conoutf.debug(msg, ...)
    msg = string.format(msg, ...)
    if debug_mode then
        print(string.char(27) .. "[" .. "32" .. "m" .. os.date("%x %X") .. " [Debug]   | " .. msg .. string.char(27) .. "[" .. "0" .. "m")
    end
end

-- A function used to calculate the size of a table as array of dictionary
local function table_size(t)
  local max = 0
  for k,v in pairs(t) do
    max = max + 1
  end
  return max
end

-- Load the database and print its content
function db.load()
    users, err = db[db.type].load(db[db.type])

    if err
    then
        conoutf.warning(err)
        conoutf.warning("Using text database")
        db.type = "text"
        db.load()
    else
        conoutf.info("Loaded "..db.type.." database")

        for domain,user in pairs(users) do
            conoutf.debug(domain..":")
            for name,conf in pairs(user) do
                conoutf.debug("    "..name..": ")
                for k,v in pairs(conf) do
                    conoutf.debug("        "..v.."; ")
                end
            end
        end
    end
    
    if table_size(users) < 1 then
        conoutf.warning("Users table have less than one domain defined, you'll not able to use authserver functions")
    end
end

-- Unload the database
function db.unload()
    db[db.type].close()
    users = {}
end

-- Reload database - Unused for now
function db.reload()
    db.unload()
    db.load()
end

--Handle any errors.
function master:handleError(errmsg, retry)
    if not errmsg then return end
    retry = retry or WAIT_TO_RECONNECT
    conoutf.error(errmsg)
end

-- Get server list from Sauerbraten Master Server
local function send_serverlist()
    -- Connect and send list request
    function sauermaster:connectServer(client)
        sauermaster.client:close()
        sauermaster.client = net.tcp_client()
        sauermaster.client:async_connect(sauermaster_host, sauermaster_port, function(errmsg) 
            if errmsg then
                master:handleError(errmsg)
                return
            end
            local localAddress = sauermaster.client:local_endpoint()
            conoutf.debug(string.format("[Client] : Local socket address %s:%s", localAddress.ip, localAddress.port))
            sauermaster.client:async_send("list\n", function(errmsg)
                if errmsg then
                    master:handleError(errmsg)
                    return 
                end
                sauermaster:readData(sauermaster.client) 
            end)
        end)
    end

    --Main Data Loop
    function sauermaster:readData(client)
        sauermaster.client:async_read_until("\n", function(data)
            if data then
                sauermaster:processData(client, data)
                sauermaster:readData(sauermaster.client)
            else
                sendmsg("]")
                for i,line in ipairs(_.to_array(string.gmatch(script, "[^\n]+"))) do
                    sendmsg(line)
                end
                sauermaster.client:close()
                masterserver:close()
            end
        end)
    end

    --Process data read from the server and send it to the client.
    function sauermaster:processData(client, data)
        if data == "" then return end
        data = string.gsub(data, "addserver ", "")
        data = string.gsub(data, "\n", "")
        conoutf.debug("[Client] : "..data)
        sendmsg('"'..data..'"')
    end

    -- Initiate Connection
    sauermaster:connectServer(sauermaster.client)
end

-- Generate chalauth challenge from a public key
local function generate_challenge(key)
    local key = crypto.sauerecc.key(key)
    local gen_challenge = key:generate_challenge()
    return gen_challenge
end

-- Send a response to the client
local function sendmsg(msg)
    local remote_endpoint = masterserver:remote_endpoint(server)
    conoutf.debug("[Output] | (%s:%s) : %s\n", remote_endpoint.ip, remote_endpoint.port, msg)
    if not allow_stream then return end
    masterserver:async_send(msg .. "\n", function(success) end)
end

-- Main loop: Accept client connection, read received data, repeat
local function accept_next(master_server)
    master_server:async_accept(function(server)
        masterserver = server
        local remote_endpoint = masterserver:remote_endpoint(server)
        conoutf.debug("[Input]  | (%s:%s) : Connection accepted", remote_endpoint.ip, remote_endpoint.port)
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

-- Process data read from the client.
function master:processData(server, data)

    local remote_endpoint = masterserver:remote_endpoint(server)
    conoutf.debug("[Input]  | (%s:%s) : %s", remote_endpoint.ip, remote_endpoint.port, string.gsub(data, "\n$", ""))
    
	-- List handler
	if data.find(data,"list") then
        sendmsg("serverlist = [")
        send_serverlist(masterserver)
	end
    
	-- ReqAuth Handler
	if string.match(data,"reqauth %d+ %w+ .*") then
        local arguments = _.to_array(string.gmatch(data, "[^ \n]+"))
        local request_id, name, domain = tonumber(arguments[2]), arguments[3]:lower(), (arguments[4] or "")
        if not users[domain] then conoutf.debug(string.format("[Auth]   | (%s:%s) : auth n°%s: Domain '%s' doesn't exist!", remote_endpoint.ip, remote_endpoint.port, request_id, domain)) return end
        if not users[domain][name] or not users[domain][name][1] then conoutf.debug(string.format("[Auth]   | (%s:%s) : auth n°%s: User '%s' doesn't exist in domain '%s' !", remote_endpoint.ip, remote_endpoint.port, request_id, name, domain)) return end
        challenges[request_id] = generate_challenge(users[domain][name][1])
        local challenge_str = challenges[request_id]:to_string()
        conoutf.debug("[Auth]   | (%s:%s) : Attempting auth n°%d for %s@%s", remote_endpoint.ip, remote_endpoint.port, request_id, name, domain or '')
        sendmsg(string.format("chalauth %i %s", request_id, challenge_str))
    end
    
    -- ConfAuth Handler
    if string.match(data, "confauth %d+ .+") then
        local arguments = _.to_array(string.gmatch(data, "[^ \n]+"))
        local request_id, answer = tonumber(arguments[2]), arguments[3]
        if not challenges[request_id] then return end
        local challenge_expected_answer = challenges[request_id]:expected_answer(answer)
        if challenge_expected_answer then 
            conoutf.debug(string.format("[Auth]   | (%s:%s) : Succeded auth n°%d with answer %s", remote_endpoint.ip, remote_endpoint.port, request_id, answer))
            sendmsg(string.format("succauth %d", request_id))
        else
            conoutf.debug(string.format("[Auth]   | (%s:%s) : Failed auth n°%d with answer %s", remote_endpoint.ip, remote_endpoint.port, request_id, answer))
            sendmsg(string.format("failauth %d", request_id))
        end
        table.remove(challenges, request_id)
    end
    
    -- QueryId Handler
    if string.match(data, "QueryId %d+ %w+ .*") then
        local arguments = _.to_array(string.gmatch(data, "[^ \n]+"))
        local request_id, name, domain = tonumber(arguments[2]), arguments[3]:lower(), (arguments[4] or "")
        if not users[domain] then 
            conoutf.debug(string.format("[Auth]   | (%s:%s) : auth n°%s: Domain '%s' doesn't exist!", remote_endpoint.ip, remote_endpoint.port, request_id, domain))
            sendmsg(string.format("DomainNotFound %d", request_id))
            return 
        end
        if not users[domain][name] or not users[domain][name][1] then
            conoutf.debug(string.format("[Auth]   | (%s:%s) : auth n°%s: User '%s' doesn't exist in domain '%s' !", remote_endpoint.ip, remote_endpoint.port, request_id, name, domain))
            sendmsg(string.format("NameNotFound %d", request_id))
            return 
        end
        conoutf.debug(string.format("[Auth]   | (%s:%s) : auth n°%s: User '%s' found in domain '%s' with '%s' rights", remote_endpoint.ip, remote_endpoint.port, request_id, name, domain, users[domain][name][2]))
        sendmsg(string.format("FoundId %d %s", request_id, users[domain][name][2]))
    end

end 

-- Open the script to send to the client requesting server list
file = assert(io.open("sauer_masterscript", "r"))
script = file:read("*all")

-- Check if the port was correctly binded
if not master.server then
    conoutf.error("Failed to open a listen socket on " .. ip .. ":" .. port .. ": " .. socket_error)
    return false
else
    master.server:listen()
end

conoutf.info("Sauerbraten MasterServer listening on " .. ip .. ":" .. port)

-- Load the database
db.load()

conoutf.info("Ready")

-- Enter the main loop
accept_next(master.server)

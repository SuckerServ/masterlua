--[[
    MasterLua Authserver MySQL Database backend, based on the one of Hopmod Authserver and some functions from the stats module of Hopmod
]]

require "luasql_mysql"

local connection = {}
connection.settings = {}

local msg = {}
msg.no_domain = "Domain, %s does not exist."
msg.domain = "Domain, %s already exists."
msg.no_user = "User, %s@%s does not exist."
msg.user = "User, %s@%s already exists."
msg.same = "%s is named %s."
msg.mysql = {}
msg.mysql.unknown = "Connection to the mysql database at %s:%s failed."
msg.mysql.no_insert = "Inserting %s failed."
msg.mysql.no_delete = "Deleting %s failed."
msg.mysql.no_update = "Updating %s failed."
msg.mysql.no_select = "Fetching %s failed."

local function readWholeFile(filename)
    local file, err = io.open(filename)
    if not file then error(err) end
    return file:read("*a")
end

local function execute_statement(statement)
    local cursor, errorinfo = connection:execute(statement)
    if not cursor then
        connection:close()
        connection = nil
        return nil, errorinfo
    end
    return cursor
end

local function add_user(name, domain_id, pubkey, domain)

    if not mysql.exec(connection, "START TRANSACTION")
    then 
        return msg.mysql.unknown
    end
    
    local cursor = mysql.exec(connection, string.format("INSERT INTO users (name, domain_id, pubkey) VALUES('%s', %i, '%s')", mysql.escape_string(name), domain_id, mysql.escape_string(pubkey)))
    if not cursor
    then
	return string.format(msg.mysql.no_insert, string.format("%s@%s", name, domain))
    end
    
    if not mysql.exec(connection, "COMMIT")
    then
        return msg.mysql.unknown
    end
    
    return
end

local function install_db(connection, settings)

    local schema = readWholeFile(settings.schema)
    
    for statement in string.gmatch(schema, "CREATE TABLE[^;]+") do
        local cursor, err = execute_statement(statement)
        if not cursor then error(err) end
    end    
end

local function external_load(settings)
    
    connection = luasql.mysql():connect(settings.name, settings.user, settings.pass, settings.host, settings.port)
    
    if not connection then
        return nil, string.format(msg.mysql.unknown, settings.host, settings.port)
    end
    
    if settings.install then
        install_db(connection, settings)
    end

    local domains_and_users = {}
    
    users_query = execute_statement("SELECT DISTINCT name, domain, pubkey, rights FROM users")
    
    row = users_query:fetch({}, "a")
    
	while row
	do
            if not domains_and_users[row.domain] then
                domains_and_users[row.domain] = {}
            end
            domains_and_users[row.domain][row.name:lower()] = {row.pubkey,row.rights}
            row = users_query:fetch (row, "a")
    end
    
    return domains_and_users
end

local function external_add_user(name, domain, pubkey)

    local did = domain_id(domain)
    if not did
    then
	return string.format(msg.no_domain, domain)
    end
    
    if is_user(name, did)
    then
	string.format(msg.user, name, domain)
    end
    
    return add_user(name, did, pubkey, domain)
end

local function external_del_user(name, domain)

    local did = domain_id(domain)
    if not did
    then
	return string.format(msg.no_domain, domain)
    end
    
    if not is_user(name, did)
    then
	return string.format(msg.no_user, name, domain)
    end
    
    if not mysql.exec(connection, "START TRANSACTION")
    then 
        return msg.mysql.unknown
    end
    
    local cursor = mysql.exec(connection, string.format("DELETE FROM users WHERE domain_id = %i AND name = '%s'", did, mysql.escape_string(name)))
    if not cursor
    then
        return string.format(msg.mysql.no_delete, string.format("%s@%s", name, domain))
    end
    
    if not mysql.exec(connection, "COMMIT")
    then
        return msg.mysql.unknown
    end
    
    return
end

local function external_change_user_name(name, domain, new_name)

    if name == new_name
    then
	return nil, string.format(msg.same, name, new_name)
    end
    
    local did = domain_id(domain)
    if not did
    then
	return nil, string.format(msg.no_domain, domain)
    end
    
    if not is_user(name, did)
    then
	return nil, string.format(msg.no_user, name, domain)
    end
    
    if is_user(new_name, did)
    then
	return nil, string.format(msg.user, new_name, domain)
    end
    
    if not mysql.exec(connection, "START TRANSACTION")
    then 
        return nil, msg.mysql.unknown
    end
    
    local cursor = mysql.exec(connection, string.format("UPDATE users SET name = '%s' WHERE domain_id = %i AND name = '%s'", mysql.escape_string(new_name), did, mysql.escape_string(name)))
    if not cursor
    then
	return nil, string.format(msg.mysql.no_update, string.format("%s@%s", name, domain))
    end
    
    if not mysql.exec(connection, "COMMIT")
    then
        return nil, msg.mysql.unknown
    end
    
    local key = pubkey(new_name, did)
    if not key
    then
	return nil, string.format(msg.mysql.no_select, "pubkey")
    end
    
    return key
end

local function external_change_user_key(name, domain, new_pubkey)

    local did = domain_id(domain)
    if not did
    then
        return string.format(msg.no_domain, domain)
    end
    
    if not is_user(name, did)
    then
	return string.format(msg.no_user, name, domain)
    end
    
    if not mysql.exec(connection, "START TRANSACTION")
    then 
        return msg.mysql.unknown
    end
    
    local cursor = mysql.exec(connection, string.format("UPDATE users SET pubkey = '%s' WHERE domain_id = %i AND name = '%s'", mysql.escape_string(new_pubkey), did, mysql.escape_string(name)))
    if not cursor
    then
        return string.format(msg.mysql.no_update, string.format("%s@%s", name, domain))
    end
    
    if not mysql.exec(connection, "COMMIT")
    then
        return msg.mysql.unknown
    end
    
    return
end

local function external_change_user_domain(name, domain, new_domain)

    if domain == new_domain
    then
	return nil, string.format(msg.same, domain, new_domain)
    end
    
    local did = domain_id(domain)
    if not did
    then
        return nil, string.format(msg.no_domain, domain)
    end
    
    local new_did = domain_id(new_domain)
    if not new_did
    then
        return nil, string.format(msg.no_domain, new_domain)
    end
    
    if not is_user(name, did)
    then
	return nil, string.format(msg.no_user, name, domain)
    end
    
    if is_user(name, new_did)
    then
	return nil, string.format(msg.user, name, new_domain)
    end
    
    if not mysql.exec(connection, "START TRANSACTION")
    then 
        return nil, msg.mysql.unknown
    end
    
    local cursor = mysql.exec(connection, string.format("UPDATE users SET domain_id = %i WHERE domain_id = %i AND name = '%s'", new_did, did, mysql.escape_string(name)))
    if not cursor
    then
	return nil, string.format(msg.mysql.no_update, string.format("%s@%s", name, domain))
    end
    
    if not mysql.exec(connection, "COMMIT")
    then
        return nil, msg.mysql.unknown
    end
    
    local key = pubkey(name, new_did)
    if not key
    then
	return nil, string.format(msg.mysql.no_select, "pubkey")
    end
    
    return key
end

-- internal.change_domain_name(domain, new_domain)
--       nil, err or users, nil
--               users[name] = pubkey
local function external_change_domain_name(domain, new_domain)

    if domain == new_domain
    then
	return nil, string.format(msg.same, domain, new_domain)
    end
    
    local did = domain_id(domain)
    if not did
    then
	return nil, string.format(msg.no_domain, domain)
    end
    
    local users = list_users(did)
    
    local new_did = domain_id(new_domain)
    if not new_did
    then
	local domain_case = mysql.row(mysql.exec(connection, string.format("SELECT case_insensitive FROM domains WHERE id = %i", did)))
	if not domain_case
	then
	    return nil, string.format(msg.mysql.no_select, "case_insensitive")
	else
	    if domain_case.case_insensitive == "1"
	    then
		domain_case = true
	    else
		domain_case = nil
	    end
	end
	
	local add_domain_err = add_domain(new_domain, domain_case)
	if add_domain_err
	then
	    return nil, add_domain_err
	end
	
	new_did = domain_id(new_domain)
	if not new_did
	then
	    return nil, string.format(msg.mysql.no_select, "domain_id")
	end
    else
	local domain_case = mysql.row(mysql.exec(connection, string.format("SELECT case_insensitive FROM domains WHERE id = %i", did)))
	if not domain_case
	then
	    return nil, string.format(msg.mysql.no_select, "case_insensitive")
	else
	    if domain_case.case_insensitive == "1"
	    then
		domain_case = true
	    else
		domain_case = false
	    end
	end
	
	local new_domain_case = mysql.row(mysql.exec(connection, string.format("SELECT case_insensitive FROM domains WHERE id = %i", new_did)))
	if not new_domain_case
	then
	    return nil, string.format(msg.mysql.no_select, "case_insensitive")
	else
	    if new_domain_case.case_insensitive == "1"
	    then
		new_domain_case = true
	    else
		new_domain_case = false
	    end
	end
	
	if (domain_case and not new_domain_case) or (not domain_case and new_domain_case)
        then
            return nil, "New domain already exists and has not the same case sensitive setting."
        end
        
	for name, _ in pairs(users)
	do
	    if is_user(name, new_did)
	    then
		return nil, string.format(msg.user, name, new_domain)
	    end
	end
    end
    
    for name, key in pairs(users)
    do
        add_user(name, new_did, key, new_domain)
    end
    
    del_domain(did, domain)
    
    return users
end

local function external_close_connection()
    mysql.close(connection)
end


return {is_user = external_is_user,
    add_user = external_add_user,
    del_user = external_del_user,
    change_user_name = external_change_user_name,
    change_user_key = external_change_user_key,
    change_user_domain = external_change_user_domain,
    list_users = external_list_users,
    add_domain = external_add_domain,
    del_domain = external_del_domain,
    change_domain_name = external_change_domain_name,
    change_domain_sensitivity = external_change_domain_sensitivity,
    load = external_load,
    close = external_close_connection}

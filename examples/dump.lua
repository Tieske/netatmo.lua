#!/usr/bin/env lua
package.path = "./?/init.lua;"..package.path


-- Example showing how to use the Netatmo API to fetch data from the Netatmo
-- servers. Dumps the entire set of data.


local config = require "config"
local pretty = require("pl.pretty").write
local Netatmo = require "netatmo"
local logging = require "logging"
Netatmo.log:setLevel(logging.WARN)

local netatmo = Netatmo.new {
  client_id = config.auth_data.client_id,
  client_secret = config.auth_data.client_secret,
}

print()
print("Netatmo command line utility to fetch and dump data")
print()
print("Please visit and authorize: ", netatmo:get_authorization_url())
print("Enter the code you got here: ")
local code = io.read()
netatmo:authorize(netatmo.state, code)

print("Fetching device information from Netatmo servers...")

local data, err = netatmo:get_stations_data()
netatmo:logout()
if not data then
  print("Error: ",err)
  os.exit(1)
end

print(pretty(data))

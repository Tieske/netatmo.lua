package.path = "./?/init.lua;"..package.path

local config = require "config"
local pretty = require("pl.pretty").write
local Netatmo = require "netatmo"
local logging = require "logging"
Netatmo.log:setLevel(logging.WARN)

local function extend(str, size)
  return str..string.rep(" ", size - #str)
end

print()
print("Netatmo command line utility to fetch and dump data")
print()
print("Fetching device information from Netatmo servers...")
local netatmo = Netatmo.new(
                  config.auth_data.client_id,
                  config.auth_data.client_secret,
                  config.auth_data.username,
                  config.auth_data.password,
                  config.auth_data.scope
                )
local data, err = netatmo:get_stations_data()
netatmo:logout()
if not data then
  os.exit(1)
end

print(pretty(data))

while true do
  local _, data = netatmo:get_stations_data()
  print(("timeserver: %s, device.time_utc: %s, age: %s, last_status_store: %s"):format(
      data.time_server,
      data.body.devices[1].dashboard_data.time_utc,
      data.time_server-data.body.devices[1].dashboard_data.time_utc,
      data.time_server-data.body.devices[1].last_status_store))
  require"socket".sleep(30)
end

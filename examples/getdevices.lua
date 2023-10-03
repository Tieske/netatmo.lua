#!/usr/bin/env lua
package.path = "./?/init.lua;"..package.path


-- Example showing how to use the Netatmo API to fetch data from the Netatmo
-- servers. This displays device data and measured values.


local config = require "config"
local Netatmo = require "netatmo"
local logging = require "logging"
Netatmo.log:setLevel(logging.WARN)

local function extend(str, size)
  return str..string.rep(" ", size - #str)
end

local netatmo = Netatmo.new {
  client_id = config.auth_data.client_id,
  client_secret = config.auth_data.client_secret,
}

print()
print("Netatmo command line utility to display device data and values")
print()
print("Please visit and authorize: ", netatmo:get_authorization_url())
print("Enter the code you got here: ")
local code = io.read()
netatmo:authorize(netatmo.state, code)

print("Fetching device information from Netatmo servers...")

local data = netatmo:get_stations_data()
netatmo:logout()
if not data then
  os.exit(1)
end


print("======================================")
for _, device in ipairs(data) do
  print("Station name  :", device.station_name)
  print("id            :", device._id)
  print()
  for _, NAmodule in ipairs(device.modules) do
    print("    module name   :", NAmodule.module_name)
    print("    id            :", NAmodule._id)
    print("    available data:")
    for _, name in ipairs(NAmodule.data_type) do
      print("        "..extend(name, 12),tostring((NAmodule.dashboard_data or {})[name] or "<no data, check batteries?>"))
    end
    print()
  end
  print("======================================")
end


package.path = "./?/init.lua;"..package.path

local config = require "config"
local Netatmo = require "netatmo"
local logging = require "logging"
Netatmo.log:setLevel(logging.WARN)

local function extend(str, size)
  return str..string.rep(" ", size - #str)
end

print()
print("Netatmo command line utility to display device data and values")
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
  print("failed: "..tostring(err))
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
      print("        "..extend(name, 12),tostring((NAmodule.dashboard_data or {})[name] or "<no data, check battries?>"))
    end
    print()
  end
  print("======================================")
end


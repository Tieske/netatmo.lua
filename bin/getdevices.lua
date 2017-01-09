package.path = "./?/init.lua;"..package.path

local config = require "config"
local netatmo = require "netatmo"

local function extend(str, size)
  return str..string.rep(" ", size - #str)
end

print()
print("Netatmo command line utility to display device data and values")
print()
print("Fetching device information from Netatmo servers...")
local data, err = netatmo.fetch_data(config.auth_data)
if not data then
  print("Failure to get device list from Netatmo servers: ",tostring(err))
  os.exit(1)
end

print("======================================")
for _, device in ipairs(data.devices) do
  print("Station name  :", device.station_name)
  print("id            :", device._id)
  print()
  for _, NAmodule in ipairs(device.modules) do
    print("    module name   :", NAmodule.module_name)
    print("    id            :", NAmodule._id)
    print("    available data:")
    for _, name in ipairs(NAmodule.data_type) do
      print("        "..extend(name, 12),tostring(NAmodule.dashboard_data[name]))
    end
    print()
  end
  print("======================================")
end


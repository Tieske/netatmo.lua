package.path = "./?/init.lua;"..package.path

local config = require "config"
local sleep = require("socket").sleep
local https = require "ssl.https"
local log = require("logging.console")()
local Netatmo = require "netatmo"
local logging = require "logging"
Netatmo.log:setLevel(logging.WARN)

print()
print("Netatmo command line utility to push data to a url")
print()
print("Now entering an endless loop. Checking every "..tostring(config.push_interval).." seconds")

local netatmo = Netatmo.new(
                  config.auth_data.client_id,
                  config.auth_data.client_secret,
                  config.auth_data.username,
                  config.auth_data.password,
                  config.auth_data.scope
                )

-- returns module table from the data
local function get_module(id, modules)
  local mod = modules[id]
  if mod then
    return mod
  end
  return nil, "module not found with matching id; "..tostring(id)
end

-- case insensitive search for the data type from a module table
local function get_value(name, mod)
  name = name:upper()
  for key, value in pairs(mod.dashboard_data or {}) do
    if key:upper() == name then
      return value
    end
  end
  return nil, "specified name not found in module dashboarddata; "..tostring(name)
end

-- do this in an endless loop
while true do
  local success_count = 0
  local fail_count = 0
  local na_count = 0  -- unchanged values
  local modules, err = netatmo:get_modules_data()
  if not modules then
    log:warn("Failure to get device list from Netatmo servers: %s",tostring(err))
    fail_count = fail_count + 1
  else
    for _, pushurl in ipairs(config.push_urls) do
      local mod, err = get_module(pushurl.module_id, modules)
      if not mod then
        log:warn(err)
        fail_count = fail_count + 1
      else
        local value, err = get_value(pushurl.type, mod)
        if not value then
          log:warn(err)
          fail_count = fail_count + 1
        else
          if value ~= pushurl.last then  -- only update if changed
            local url = pushurl.url:format(value)
            local body, code = https.request(url)
            if tostring(code) ~= "200" then
              log:error("failed to push data to zipato-cloud; %s %s", tostring(code), tostring(body))
              fail_count = fail_count + 1
            else
              pushurl.last = value -- set last value, to track changes
              success_count = success_count + 1
            end
          else
            na_count = na_count + 1
          end
        end
      end
    end
  end
  if success_count + fail_count > 0 then
    log:info("pushed %s items succesfully, %s unchanged, %s failures", success_count, na_count, fail_count)
  end
  sleep(config.push_interval)
end

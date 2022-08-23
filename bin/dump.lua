#!/usr/bin/env lua

package.path = "./?/init.lua;"..package.path

local config = require "config"
local pretty = require("pl.pretty").write
local Netatmo = require "netatmo"
local logging = require "logging"
Netatmo.log:setLevel(logging.WARN)

print()
print("Netatmo command line utility to fetch and dump data")
print()
print("Fetching device information from Netatmo servers...")
local netatmo = Netatmo.new(
                  config.auth_data.client_id.."x",
                  config.auth_data.client_secret,
                  config.auth_data.username,
                  config.auth_data.password,
                  config.auth_data.scope
                )
local data = netatmo:get_stations_data()
netatmo:logout()
if not data then
  os.exit(1)
end

print(pretty(data))

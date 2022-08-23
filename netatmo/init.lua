--- Netatmo API library to access the REST api.
--
-- This library implements the session management and makes it easy to access
-- individual endpoints of the API.
--
-- @author Thijs Schreijer, http://www.thijsschreijer.nl
-- @license netatmo.lua is free software under the MIT/X11 license.
-- @copyright 2017-2020 Thijs Schreijer
-- @release Version x.x, Library to acces the Netatmo API

local url = require "socket.url"
local ltn12 = require "ltn12"
local json = require "cjson.safe"
local socket = require "socket"

--- The module table
-- @table netatmo
--
-- @field https
-- This is a function set on the module table, such that it can
-- be overridden by another implementation (eg. Copas). The default implementation
-- uses the LuaSec one (module `ssl.htps`).
--
-- @field log
-- Logger is set on the module table, to be able to override it.
-- Default is the LuaLogging default logger.
--
-- @field DEVICE_TYPES
-- A lookup table to convert the `type` ID to a description.
-- Eg. `"NAModule4"` -> `"Additional indoor module"`.

local netatmo = {
  _VERSION = "0.1.0",

  https = require "ssl.https",

  log = require("logging").defaultLogger(),

  DEVICE_TYPES = setmetatable({
    NAMain = "Main indoor module",
    NAModule1 = "Outdoor module",
    NAModule4 = "Additional indoor module",
    -- NAunknown? = "Rain gauge",
    -- NAunknown? = "Anemometer",
    NAPlug = "Thermostat plug",
    NATherm1 = "Thermostat",
    NRV = "Radiator valve",
    NHC = "Air quality monitor",
    NACamera = "Indoor camera",
    NOC = "Outdoor camera",
    NSD = "Smoke detector",
    NACamDoorTag = "Door/window sensor",
  }, {
    __index = function(self, key)
      return tostring(key).."(unknown device type)"
    end
  })
}
local netatmo_mt = { __index = netatmo }



-------------------------------------------------------------------------------
-- Generic functions.
-- Functions for session management and instantiation
-- @section Generic


local BASE_URL="https://api.netatmo.com"
local CLOCK_SKEW = 5 * 60 -- clock skew in seconds to allow when refreshing tokens



local function urlencode(t)
  if t == nil then
    return ""
  end
  local result = {}
  local i = 0  -- 0: first '&' will hence be dropped, by concat
  for k, v in pairs(t) do
    result[i] = "&"
    result[i+1] = url.escape(k)
    result[i+2] = "="
    result[i+3] = url.escape(v)
    i = i + 4
  end
  return table.concat(result)
end

-- Performs a HTTP request on the Netatmo API.
-- @param path (string) the relative path within the API base path
-- @param method (string) HTTP method to use
-- @param headers (table) optional header table
-- @param query (table) optional query parameters (will be escaped)
-- @param body (table/string) optional body. If set the "Content-Length" will be
-- added to the headers. If a table, it will be send as url-encoded, and the
-- "Content-Type" header will be set to "application/x-www-form-urlencoded".
-- @return ok, response_body, response_code, response_headers, response_status_line
local function na_request(path, method, headers, query, body)
  local response_body = {}
  headers = headers or {}

  query = "?" .. urlencode(query)
  if query == "?" then
    query = ""
  end

  if type(body) == "table" then
    body = urlencode(body)
    headers["Content-Type"] =  "application/x-www-form-urlencoded"
  end
  headers["Content-Length"] = #(body or "")

  local r = {
    method = assert(method, "2nd parameter 'method' missing"):upper(),
    url = BASE_URL .. assert(path, "1st parameter 'relative-path' missing") .. query,
    headers = headers,
    source = ltn12.source.string(body or ""),
    sink = ltn12.sink.table(response_body),
  }
  netatmo.log:debug("[netatmo] making api request to: %s %s", r.method, r.url)
  --netatmo.log:debug(r)  -- not logging because of credentials
--print("Request: "..require("pl.pretty").write(r))
--print("Body: "..require("pl.pretty").write(body))

  local ok, response_code, response_headers, response_status_line = netatmo.https.request(r)
  if not ok then
    netatmo.log:error("[netatmo] api request failed with: %s", response_code)
    return ok, response_code, response_headers, response_status_line
  end

  if type(response_body) == "table" then
    response_body = table.concat(response_body)
  end

  for name, value in pairs(response_headers) do
    if name:lower() == "content-type" and value:find("application/json", 1, true) then
      -- json body, decode
      response_body = assert(json.decode(response_body))
      break
    end
  end
--print("Response: "..require("pl.pretty").write({
--  body = response_body,
--  status = response_code,
--  headers = response_headers,
--}))

  netatmo.log:debug("[netatmo] api request returned: %s", response_code)

  return ok, response_body, response_code, response_headers, response_status_line
end



local function set_refresh_token(self, refresh_token)
  if refresh_token then
    self.refresh_token = refresh_token
  else
    self.refresh_token = nil
  end
  return true
end


local function set_access_token(self, access_token, expires_in)
  if access_token then
    self.access_token = "Bearer " .. access_token
    self.access_token_expires = socket.gettime() + expires_in - CLOCK_SKEW
  else
    self.access_token = nil
    self.access_token_expires = nil
  end
  return true
end


-- gets the access token, if not set or expired, it will be automatically
-- fetched/refreshed.
local function get_access_token(self)

  if self.access_token and self.access_token_expires > socket.gettime() then
    -- access token still valid
    return self.access_token
  end

  -- no access token, or expired
  netatmo.log:debug("[netatmo] access_token expired/unavailable for %s", self.username)

  if not self.refresh_token then
    -- there is no refresh token, so we must login first
    local ok, err = self:login()
    if not ok then
      return nil, err
    end
    return self.access_token
  end

  -- make a refresh call
  netatmo.log:debug("[netatmo] refreshing access_token for %s", self.username)
  local ok, response_body = self:rewrite_error(200,
    na_request("/oauth2/token", "POST", nil, nil, {
      -- docs say urlencoded body, we're trying JSON anyway
      grant_type = "refresh_token",
      refresh_token = self.refresh_token,
      client_id = self.client_id,
      client_secret = self.client_secret,
    })
  )
  if not ok then
    -- refresh failed, expired refresh token? do a force logout and retry
    -- which forces a new login
    netatmo.log:error("[netatmo] failed to refresh the access_token, retrying. Error: %s", response_body)
    self:logout()
    return get_access_token(self)
  end

  -- refresh success!
  set_access_token(self, response_body.access_token, response_body.expires_in)
  if response_body.refresh_token then
    -- only set refresh if we got it returned, just in case
    set_refresh_token(self, response_body.refresh_token)
  end

  return self.access_token
end



--- Creates a new Netatmo session instance.
-- Only OAuth2 `grant_type` supported is "password".
-- @param client_id (string) required, the client_id to use for login
-- @param client_secret (string) required, the client_secret to use for login
-- @param username (string) required, the username to use for login
-- @param password (string) required, the password to use for login
-- @param scope (string/table) optional, space separated string, or table with strings, containing the scopes requested. Default "read_station".
-- @return netatmo session object
-- @usage
-- local netatmo = require "netatmo"
-- local nasession = netatmo.new("abcdef", "xyz", "myself@nothere.com", "secret_password")
-- local ok, err = nasession:login()
-- if not ok then
--   print("failed to login: ", err)
-- end
function netatmo.new(client_id, client_secret, username, password, scope)
  local self = {
    client_id = assert(client_id, "1st parameter, 'client_id' is missing"),
    client_secret = assert(client_secret, "2nd parameter, 'client_secret' is missing"),
    username = assert(username, "3rd parameter, 'username' is missing"),
    password = assert(password, "4th parameter, 'password' is missing"),
  }

  if type(scope) == "table" then
    if next(scope) then
      scope = table.concat(scope, " ")
    else
      scope = nil -- table was empty
    end
  end
  self.scope = scope or "read_station"

  netatmo.log:debug("[netatmo] created new instance for %s with scopes: %s", self.username, self.scope or "<none>")
  return setmetatable(self, netatmo_mt)
end



--- Performs a HTTP request on the Netatmo API.
-- It will automatically inject authentication/session data. Or if not logged
-- logged in yet, it will log in. If the session has expired it will be renewed.
--
-- NOTE: if the response_body is json, then it will be decoded and returned as
-- a Lua table.
-- @tparam string path the relative path within the API base path
-- @tparam string method HTTP method to use
-- @tparam[opt] table headers header table
-- @tparam[opt] table query query parameters (will be escaped)
-- @tparam[opt] table|string body if set the "Content-Length" will be
-- added to the headers. If a table, it will be send as JSON, and the
-- "Content-Type" header will be set to "application/json".
-- @return `ok`, `response_body`, `response_code`, `response_headers`, `response_status_line`
-- @usage
-- local netatmo = require "netatmo"
-- local nasession = netatmo.new("abcdef", "xyz", "myself@nothere.com", "secret_password")
--
-- local headers = { ["My-Header"] = "myvalue" }
-- local query = { ["param1"] = "value1" }
--
-- -- the following line will automatically log in
-- local ok, response_body, status, headers, statusline = nasession:request("/api/attributes", "GET", headers, query, nil)
function netatmo:request(path, method, headers, query, body)
--  if not self.cookie then
--    -- must login first
--    local ok, err = self:login()
--    if not ok then
--      return ok, err
--    end
--  end
  local access_token, err = get_access_token(self)
  if not access_token then
    return nil, err
  end

  headers = headers or {}
  headers.Authorization = access_token

  return na_request(path, method, headers, query, body)
end


--- Rewrite errors to Lua format (nil+error).
-- Takes the output of the `request` function and validates it for errors;
--
-- - nil+err
-- - body with "error" field (json object)
-- - mismatch in expected status code (a 200 expected, but a 404 received)
--
-- This reduces the error handling to standard Lua errors, instead of having to
-- validate each of the situations above individually.
-- @tparam[opt=nil] number expected expected status code, if nil, it will be ignored
-- @param ... same parameters as the `request` method
-- @return nil+err or the input arguments
-- @usage
-- local netatmo = require "netatmo"
-- local nasession = netatmo.new("abcdef", "xyz", "myself@nothere.com", "secret_password")
--
-- -- Make a request where we expect a 200 result
-- local ok, response_body, status, headers, statusline = nasession:rewrite_error(200, nasession:request("/some/thing", "GET"))
-- if not ok then
--   return nil, response_body -- a 404 will also follow this path now, since we only want 200's
-- end
function netatmo:rewrite_error(expected, ok, body, status, headers, ...)
  if not ok then
    return ok, body
  end

  if type(body) == "table" and type(body.error) == "table" then
    return nil, tostring(status)..": "..json.encode(body.error)
  end

  if expected ~= nil and expected ~= status then
    if type(body) == "table" then
      body = json.encode({body = body, headers = headers})
    end
    return nil, "bad return code, expected " .. expected .. ", got "..status..". Response: "..body
  end

  return ok, body, status, headers, ...
end



--- Logs out of the current session.
-- There is no real logout option with this API. Hence this only deletes
-- the locally stored tokens.
-- @return `true`
-- @usage
-- local netatmo = require "netatmo"
-- local nasession = netatmo.new("abcdef", "xyz", "myself@nothere.com", "secret_password")
-- local ok, err = nasession:login()
-- if not ok then
--   print("failed to login: ", err)
-- else
--   nasession:logout()
-- end
function netatmo:logout()
  netatmo.log:debug("[netatmo] logout for %s", self.username)
  set_access_token(self, nil, nil)
  set_refresh_token(self, nil)
end



--- Logs in the current session.
-- This will automatically be called by the `request` method, if not logged in
-- already.
-- @return `true` or `nil+err`
-- @usage
-- local netatmo = require "netatmo"
-- local nasession = netatmo.new("abcdef", "xyz", "myself@nothere.com", "secret_password")
-- local ok, err = nasession:login()
-- if not ok then
--   print("failed to login: ", err)
-- end
function netatmo:login()

  local body = {
    grant_type = "password",
    client_id = self.client_id,
    client_secret = self.client_secret,
    username = self.username,
    password = self.password,
    scope = self.scope,
  }

  local ok, response_body = self:rewrite_error(200,
    na_request("/oauth2/token", "POST", nil, nil, body))
  if not ok then
    netatmo.log:error("[netatmo] failed to login: %s", response_body)
    return nil, "failed to login: "..response_body
  end

  netatmo.log:debug("[netatmo] login succes for %s", self.username)
  set_access_token(self, response_body.access_token, response_body.expires_in)
  set_refresh_token(self, response_body.refresh_token)

  return true
end



-------------------------------------------------------------------------------
-- API specific functions.
-- This section contains functions that directly interact with the Netatmo API.
-- @section API

local check_for_warnings do
  local function check_module(self, modul)
    local description = ("%s '%s' (id '%s')"):format(
                        netatmo.DEVICE_TYPES[modul.type],
                        modul.module_name or "no name",
                        modul._id or "no id")
    if modul.reachable == false then
      netatmo.log:fatal("[netatmo] %s is not reachable", description)
    end
    if (modul.rf_status or 0) > 90 then -- Current radio status per module. (90=low, 60=highest)
      netatmo.log:warn("[netatmo] %s has a weak RF signal (%d; 90=low, 60=highest)", description, modul.rf_status)
    end
    if (modul.wifi_status or 0) > 86 then -- wifi status per Base station. (86=bad, 56=good)
      netatmo.log:warn("[netatmo] %s has a weak WIFI signal (%d; 90=low, 60=highest)", description, modul.wifi_status)
    end
    if (modul.battery_percent or 999) < 10 then -- wifi status per Base station. (86=bad, 56=good)
      netatmo.log:warn("[netatmo] %s has a weak battery (%d %%)", description, modul.battery_percent)
    end
  end

  function check_for_warnings(self, devices)
    for _, device in ipairs(devices or {}) do
      check_module(self, device)
      for _, modul in ipairs(device.modules or {}) do
        check_module(self, modul)
      end
    end
  end
end

--- Gets device data.
-- @tparam[opt] string device_id the id (mac-address) of the station
-- @tparam[opt=false] bool get_favorites set to true to get the favorites
-- @tparam[opt=false] bool no_warnings set to true to skip generating warnings in the logs
-- @return device list + full response, or nil+err
-- @usage
-- local netatmo = require "netatmo"
-- local nasession = netatmo.new("abcdef", "xyz", "myself@nothere.com", "secret_password")
-- local stations, full_response = nasession:get_stations_data()
function netatmo:get_stations_data(device_id, get_favorites, no_warnings)

  local ok, response_body = self:rewrite_error(200, self:request(
      "/api/getstationsdata",
      "GET", nil, {
        device_id = device_id,
        get_favorites = (get_favorites ~= nil and tostring(get_favorites) or nil),
      }))
  if not ok then
    return nil, "failed to get data: "..response_body
  end

  if not no_warnings then
    check_for_warnings(self, response_body.body.devices)
  end

  return response_body.body.devices, response_body
end



--- Gets device data, but returns by (sub)module instead of station.
-- The returned table is both an array of all modules, as well as a hash-table
-- in which the same modules are indexed by their ID's for easy lookup.
-- @tparam[opt] string device_id the id (mac-address) of the station
-- @tparam[opt=false] bool get_favorites set to true to get the favorites
-- @tparam[opt=false] bool no_warnings set to true to skip generating warnings in the logs
-- @return module list, or nil+err
-- @usage
-- local netatmo = require "netatmo"
-- local nasession = netatmo.new("abcdef", "xyz", "myself@nothere.com", "secret_password")
-- local modules = nasession:get_modules_data()
-- local module = modules["03:00:00:04:89:50"]
function netatmo:get_modules_data(device_id, get_favorites, no_warnings)
  local data, err = self:get_stations_data(device_id, get_favorites, no_warnings)
  if not data then
    return nil, err
  end

  for i = 1, #data do
    local device = data[i]
    data[device._id] = device -- also index under its ID
    for _, submodule in ipairs(device.modules or {}) do
      data[#data + 1] = submodule
      data[submodule._id] = submodule -- also index under its ID
    end
  end
  return data
end



return netatmo

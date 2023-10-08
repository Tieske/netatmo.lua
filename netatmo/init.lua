--- Netatmo API library to access the REST api.
--
-- This library implements the session management and makes it easy to access
-- individual endpoints of the API.
--
-- To create a valid session, access and refresh tokens are required.
-- This requires the user to login to the NetAtmo site and authorize the application.
-- The  library doesn't provide a full flow, but does provide the necessary functions
-- to obtain the required tokens.
--
-- The `get_authorization_url` method will return the url to navigate to to start the
-- OAuth2 flow. Once authorized on the NetAtmo site, it will redirect the users webbrowser
-- to the `callback_url` provided when creating the session. This url should be handled
-- by a webserver, and the `authorize` method should be called with the results from the callback url.
--
-- To manually obtain the tokens, without a webserver, use a callback_url that is certain to fail
-- (the default will probably do). Then get the url using `get_authorization_url`
-- and instruct the user to visit that url and authorize the application. Once authorized,
-- the user will be redirected to the `callback_url` provided when creating the session.
-- Since it is a bad URL the redirect will fail with an error in the browser.
-- Instruct the user to collect the required informatiuon ("state" and "code" parameters) from the
-- url-bar in the browser and use them to call the `authorize` method.
--
-- If you manually retrieved a refresh token, then it can be set by calling `set_refresh_token`.
--
-- The session can be kept alive using the `keepalive` method. At the time of writing access tokens
-- have a validity of 10800 seconds (3 hours). Internally a clock-skew of 5 minutes is used, so
-- the library considers the token to be expired 5 minutes before the actual expiration time.
-- @author Thijs Schreijer, http://www.thijsschreijer.nl
-- @license netatmo.lua is free software under the MIT/X11 license.
-- @copyright 2017-2020 Thijs Schreijer
-- @release Version 0.1.0, Library to acces the Netatmo API
-- @module netatmo

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
    netatmo.log:error("[netatmo] api request failed with: %s", tostring(response_code))
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

  netatmo.log:debug("[netatmo] api request returned: %s", tostring(response_code))

  return ok, response_body, response_code, response_headers, response_status_line
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
  netatmo.log:debug("[netatmo] access_token expired/unavailable for %s", self.state)

  if not self.refresh_token then
    -- there is no refresh token, so we must login first
    self:login_callback()
    return nil, "login required"
  end

  -- make a refresh call
  netatmo.log:debug("[netatmo] refreshing access_token for %s", self.state)
  local ok, response_body, response_code, response_headers, response_status_line =
    na_request("/oauth2/token", "POST", nil, nil, {
    -- docs say urlencoded body, we're trying JSON anyway
    grant_type = "refresh_token",
    refresh_token = self.refresh_token,
    client_id = self.client_id,
    client_secret = self.client_secret,
  })

  if response_code == 401 or response_code == 403 then
    -- auth failure, refresh-token invalid, clear it
    self:logout()
    return get_access_token(self) -- retry, to return the above error "login required"
  end

  ok, response_body = self:rewrite_error(200, ok, response_body, response_code, response_headers, response_status_line)
  if not ok then
    netatmo.log:error("[netatmo] failed to refresh the access_token. Error: %s", response_body)
    return nil, response_body
  end

  -- refresh success!
  set_access_token(self, response_body.access_token, response_body.expires_in)
  if response_body.refresh_token then
    -- only set refresh if we got it returned, just in case
    self:set_refresh_token(response_body.refresh_token)
  end

  return self.access_token
end



--- Creates a new Netatmo session instance.
-- Only OAuth2 `grant_type` supported is "authorization_code", for which the refresh-token is required.
-- The `refresh_token` can be specified in the options table, or set later using the `set_refresh_token` method.
-- The token can also be retreived by getting the callback url from `get_authorization_url` and after calling
-- it, pass on the results to the `authorize` method.
-- @tparam table options options table with the following options
-- @tparam string options.client_id the client_id to use for accessing the API
-- @tparam string options.client_secret the client_secret to use for accessing the API
-- @tparam[opt] string options.refresh_token the user provided refresh-token to use for accessing the API
-- @tparam[opt] array options.scope the scope(s) to use for accessing the API. Defaults to all read permissions.
-- @tparam[opt] function options.persist callback function called as `function(session, refresh_token)` whenever
-- the refresh token is updated. This can be used to store the refresh token across restarts. NOTE: the refresh_token
-- can be nil, in case of a logout.
-- @tparam[opt] function options.login callback function called as `function(session)` whenever a login is required
-- (using the refresh-token to get a new access token returned a 401 or 403). If the refresh is tried implicitly
-- when a call is made to the API, then the login callback will be called before the API call returns an error.
-- @tparam[opt="https://localhost:54321"] string options.callback_url the OAuth2 callback url
-- @return netatmo session object
-- @usage
-- local netatmo = require "netatmo"
--
-- local must_login = false
-- local nasession = netatmo.new {
--    client_id = "abcdef",
--    client_secret = "xyz",
--    scope = { "read_station", "read_thermostat" },
--    callback_url = "https://localhost:54321/",  --> callback called with 'state' and 'code' parameters
--    login = function(session) must_login = true end,
-- }
-- user_url = nasession:get_authorization_url()   --> have user navigate to this url and authorize
-- -- now authorize using the 'state' and 'code' parameters
-- assert(nasession:authorize(state, code))
--
-- local data, err = nasession:get_modules_data()
-- if not data
--   if must_login then
--     -- tell user to login again, tokens expired for some reason
--   end
--   -- handle error
-- end
function netatmo.new(options)
  assert(type(options)=="table", "expected an options table")
  local self = {
    client_id = assert(options.client_id, "'options.client_id' is missing"),
    client_secret = assert(options.client_secret, "'options.client_secret' is missing"),
    callback_url = options.callback_url or "https://localhost:54321",
  }
  setmetatable(self, netatmo_mt)

  assert(options.scope ==nil or type(options.scope)=="table", "'options.scope' must be a table")
  self.scope = options.scope or {
    "read_station",
    "read_thermostat",
    "read_camera",
    "access_camera",
    "read_presence",
    "access_presence",
    "read_homecoach",
    "read_smokedetector",
  }
  self.state = "netatmo-session-"..tostring(math.fmod(math.floor(socket.gettime()*1000), 10000))
  if options.refresh_token then
    self:set_refresh_token(options.refresh_token)
  end

  if options.persist ~= nil then
    assert(type(options.persist) == "function", "'options.persist' must be a function")
  end
  self.persist_callback = options.persist or function() end

  if options.login ~= nil then
    assert(type(options.login) == "function", "'options.login' must be a function")
  end
  self.login_callback = options.login or function() end

  netatmo.log:debug("[netatmo] created new session %s", self.state)
  return self
end



--- Performs a HTTP request on the Netatmo API.
-- It will automatically inject authentication/session data. If the session has
-- expired it will be renewed.
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
-- local nasession = netatmo.new {
--    client_id = "abcdef",
--    client_secret = "xyz",
--    refresh_token = "123",
--    scope = { "read_station", "read_thermostat" },
--    callback_url = "https://localhost:54321/",
-- }
--
-- local headers = { ["My-Header"] = "myvalue" }
-- local query = { ["param1"] = "value1" }
--
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
--
-- If the status code is a 401 or 403, then the access token will be cleared.
-- @tparam[opt=nil] number expected expected status code, if nil, it will be ignored
-- @param ... same parameters as the `request` method
-- @return nil+err or the input arguments
-- @usage
-- local netatmo = require "netatmo"
-- local nasession = netatmo.new {
--    client_id = "abcdef",
--    client_secret = "xyz",
--    refresh_token = "123",
--    scope = { "read_station", "read_thermostat" },
--    callback_url = "https://localhost:54321/",
-- }
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

  if status == 401 or status == 403 then
    -- Auth error, clear our access token
    self.access_token = nil
    self.access_token_expires = nil
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


-------------------------------------------------------------------------------
-- Session management functions.
-- Functions for OAuth2 session management.
--
-- @section Session

--- Sets the refresh token to use for the session.
-- @tparam string refresh_token the refresh token to use
function netatmo:set_refresh_token(refresh_token)
  if refresh_token then
    self.refresh_token = refresh_token
  else
    self.refresh_token = nil
  end

  -- persist the new token to whatever storage
  self:persist_callback(self.refresh_token)

  return true
end

--- Gets the authorization url for the user to navigate to to start the OAuth2 flow.
-- The resulting "code" and "state" values from the callback url can be used
-- to call the `authorize` method.
-- @treturn string the url to navigate to
function netatmo:get_authorization_url()
  local args = {
    client_id = self.client_id,
    redirect_uri = self.callback_url,
    scope = table.concat(self.scope, " "),
    state = self.state,
  }
  local arg_array = {}
  for k,v in pairs(args) do
    arg_array[#arg_array+1] = k .. "=" .. url.escape(v)
  end
  return BASE_URL .. "/oauth2/authorize?" .. table.concat(arg_array, "&")
end


--- Authorizes the session.
-- This method is called from the callback url, and should be provided with the
-- `state` and `code` values from the callback url. It will fetch the initial tokens,
-- resulting in an access and refresh token if successful.
-- It can also be called with a single argument which is then the request(line) from
-- the callback url. It will then extract the `state` and `code` values from the url.
-- @tparam string state the state value from the callback url, or the callback request, request-url including query args, or the first request line.
-- @tparam[opt] string code the code value from the callback url (required if `state` is not request-data)
-- @return `true` or nil+err
function netatmo:authorize(state, code)
  assert(state, "state parameter is missing")
  if state ~= self.state then
    -- state doesn't match, check if 'state' is request-data
    if (not state:find("?state="..self.state, 1, true)) and
       (not state:find("&state="..self.state, 1, true)) then
      return nil, "the 'state' value doesn't match this sessions 'state' value"
    end
    -- looks like we have a request type value, extract the state and code
    local request = state
    state = request:match("[%?&]state=([^&%s\n]+)")
    if state ~= self.state then
      return nil, "the 'state' value doesn't match this sessions 'state' value"
    end

    if code then
      return nil, "the 'code' value is not expected, since request data is provided"
    end
    code = request:match("[%?&]code=([^&%s\n]+)")
    if not code then
      return nil, "no code found in request data"
    end
  end

  assert(code, "code parameter is missing")

  netatmo.log:debug("[netatmo] authorizing session %s", self.state)
  local ok, response_body = self:rewrite_error(200,
    na_request("/oauth2/token", "POST", nil, nil, {
      -- docs say urlencoded body, we're trying JSON anyway
      grant_type = "authorization_code",
      client_id = self.client_id,
      client_secret = self.client_secret,
      scope = table.concat(self.scope, " "),
      code = code,
      redirect_uri = self.callback_url,
    })
  )

  if not ok then
    -- authorization failed
    netatmo.log:error("[netatmo] failed to authorize. Error: %s", response_body)
    self:logout()
    return nil, "authorization failed"
  end

  -- authorize success!
  set_access_token(self, response_body.access_token, response_body.expires_in)
  self:set_refresh_token(response_body.refresh_token)

  return true
end

--- Logs out of the current session.
-- There is no real logout option with this API. Hence this only deletes
-- the locally stored tokens. This will make any new calls fail, until a new
-- refresh token has been set.
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
  netatmo.log:debug("[netatmo] logout session %s", self.state)
  set_access_token(self, nil, nil)
  self:set_refresh_token(nil)
end



--- Logs in the current session (deprecated).
-- Since the NetAtmo API no longer allows to log in using a password, this method
-- will no longer work. It will always return an error that a new `refresh_token`
-- must be set.
function netatmo:login()
  return nil, "login no longer supported, use a refresh_token instead"
end


--- Will refresh the access token.
-- This will force a refresh of the access token, even if it is still valid.
-- @return `true` or nil+err
-- @see expires_in
-- @see keepalive
function netatmo:refresh()
  if not self.refresh_token then
    return nil, "cannot refresh without a refresh token"
  end

  set_access_token(self, nil, nil) -- clear token to force refresh

  local ok, err = get_access_token(self)
  if not ok then
    return nil, err
  end

  return true
end


--- Gets the remaining time in seconds before the access token expires.
-- Returns an error if no refresh token is available.
-- The returned value can be negative. When the result of this function is
-- negative, then the `refresh` method should be called to refresh the token.
-- @return number of seconds remaining, or nil+err
-- @see refresh
-- @see keepalive
function netatmo:expires_in()
  if not self.refresh_token then
    return nil, "no refresh token set"
  end

  local now = socket.gettime()
  local expire_time = self.access_token_expires or (now - 0.01)

  return expire_time - now
end


--- Keeps the session alive.
-- Wraps around `expires_in` and `refresh` to keep the session alive.
-- Call this function in a loop, delaying each time by the returned number of seconds.
-- It will only refresh the token if required (other calls can also refresh the
-- token making an explicit refresh unnecessary).
-- @tparam[opt=60] number delay_on_error the number of seconds to delay when an error occurs (to prevent a busy loop).
-- @return number of seconds to delay until the next call, or `delay_on_error+err`
-- @usage
-- local keepalive_thread = create_thread(function()
--   while true do
--     local delay, err = nasession:keepalive()
--     sleep(delay)
--   end
-- end)
function netatmo:keepalive(delay_on_error)
  delay_on_error = delay_on_error or 60

  local remaining, err = self:expires_in()
  if not remaining then
    return delay_on_error, err
  end

  if remaining <= 0 then
    local ok, err = self:refresh()
    if not ok then
      return delay_on_error, err
    end
  end

  return self:expires_in()
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
      netatmo.log:warn("[netatmo] %s has a weak WIFI signal (%d; 86=bad, 56=good)", description, modul.wifi_status)
    end
    if (modul.battery_percent or 999) < 10 then
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

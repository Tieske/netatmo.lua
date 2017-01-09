local url = require "socket.url"
local ltn12 = require "ltn12"
local json = require "cjson.safe"
local deep_copy = require("pl.tablex").deepcopy
--local pretty = require("pl.pretty").write

local _M = {}

-- https method is set on the module table, such that it can be overridden
-- by another implementation (eg. Copas)
_M.https = require "ssl.https"

local base_url="https://api.netatmo.com"

local function authorize(path, fields)
  local query = {}
  local i = 0
  for k, v in pairs(fields) do
    query[i] = "&"
    query[i+1] = url.escape(k)
    query[i+2] = "="
    query[i+3] = url.escape(v)
    i = i + 4
  end
  query = table.concat(query)
  local response_body = {}
  local r = {
    method = "POST",
    url = base_url..path,
    headers = {
      ["Host"] = "api.netatmo.com",
      ["Content-type"] =  "application/x-www-form-urlencoded",
      ["Content-length"] = #query,
    },
    source = ltn12.source.string(query),
    sink = ltn12.sink.table(response_body),
  }
  return response_body, _M.https.request(r)
end

-- Fetches data from Netatmo.
-- In the result, the devices data will be inserted into the modules
-- table, as entry 1. Such that the ain device becomes just another module
-- in the data structure.
-- @param auth_data table with authorization data for Netatmo api
-- @return only the `body` element will be returned, or nil+error
_M.fetch_data = function(auth_data)
  -- first get authorization token
  local json_body, success, status, _, _ = authorize(
    "/oauth2/token", auth_data)
  if not success then
    return nil, status
  end
  json_body = table.concat(json_body)
  local auth, err = json.decode(json_body)
  if not auth then
    return nil, "failed decoding authorization with '"..tostring(err).."' for: "..tostring(json_body)
  end

  -- fetch actual data, using the token
  local json_body, success, status, _, _ = authorize(
    "/api/getstationsdata", { access_token = auth.access_token })
  if not success then
    return nil, status
  end
  local data = json.decode(table.concat(json_body))
  if not data then
    return nil, "failed decoding the device-data json; "..tostring(json_body)
  end
  if not data.status == "ok" then
    return nil, "Netatmo server returned status; "..tostring(data.status)
  end
  
  -- reduce to only the 'body' element
  if not data.body then
    return nil, "No body data; "..tostring(json_body)
  end
  data = data.body
  
  -- integrate device data into 'modules'
  for _, device in ipairs(data.devices or {}) do
    -- temporarily copy-out the modules list to prevent creating recursion
    local mod_list
    mod_list, device.modules = (device.modules or {}), nil
    table.insert(mod_list, 1, deep_copy(device)) -- insert device itself as index 1
    mod_list, device.modules = nil, mod_list
  end
  
  return data
end

return _M

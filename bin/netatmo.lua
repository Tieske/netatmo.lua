#!/usr/bin/env lua
package.path = "./?/init.lua;"..package.path


-- Example showing how to use the Netatmo API to fetch data from the Netatmo
-- servers. This example uses Copas to handle the callback from the Netatmo
-- servers, and does the full OAuth2 flow.


local copas = require "copas"
local socket = require "socket"
local pretty = require("pl.pretty").write
local Netatmo = require "netatmo"
Netatmo.https = copas.http -- Let NetAtmo use Copas for https requests

local host = "127.0.0.1"
local port = "54321"

copas(function()
  local config = require "config" -- load auth-config
  local na = Netatmo.new {
    client_id = config.auth_data.client_id,
    client_secret = config.auth_data.client_secret,
    callback_url = "http://"..host..":"..port.."/some/path",
  }
  local callback_result -- will get the result once we received it

  -- set up a server to handle the callback
  local server_sock = assert(socket.bind(host, port))
  local server_ip, server_port = assert(server_sock:getsockname())

  local socket_handler = function(sock)
    -- we assume no http body, so read lines until the line is empty
    local request = {}
    while true do
      local line = assert(sock:receive("*l"))
      --print(line)
      if line == "" then break end
      request[#request+1] = line
    end

    -- store callback result and send response
    callback_result = request
    sock:send("HTTP/1.1 200 OK\r\n\r\nOAuth2 access approved, please close this browser window.\r\n")
    sock:close()

    -- remove the server, since we have our request
    copas.removeserver(server_sock)
    server_sock = nil
  end

  copas.addserver(server_sock, copas.handler(socket_handler))

  -- instructions for authorization request by user/webbrowser
  print("if a webbrowser is not started automatically, please visit: ",na:get_authorization_url())
  os.execute("open '"..na:get_authorization_url().."'")
  print()
  print("Listening on "..server_ip..":"..server_port)


  -- wait for the callback, or a timeout
  local endtime = socket.gettime()+60 -- wait for 60 seconds max
  while socket.gettime() < endtime and callback_result == nil do
    copas.sleep(0.1)
  end

  if not callback_result then
    -- No results, so we had a timeout, cleanup the server
    copas.removeserver(server_sock)
    server_sock = nil
    print("timeout waiting for callback")
    os.exit(1)
  end

  -- callback_result contains the result of the callback, so we can authorize
  -- the client now. We use the first line of the request, the authorize method
  -- will parse the state and code from it.
  assert(na:authorize(callback_result[1]))
  print("Authorized successfully!")

  -- now we can fetch the data
  local data, err = na:get_stations_data()
  na:logout()
  if not data then
    print("Error: ", err)
    os.exit(1)
  end

  print(pretty(data))
end)

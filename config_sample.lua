-- configuration data
-- for use with utilities in ./bin
-- update this file and rename it to `config.lua`.

return {
  auth_data = {
    -- authorization data for Netatmo login
    client_id = "xxxxxxxxxxxx",
    client_secret = "xxxxxxxxxxxx",
    scope = {
      "read_station",
    },
    -- -- provide a refresh token, or...
    -- refresh_token = "xxxxxxxxxxxx",
    -- -- provide a callback url, and set up handling of the callback
    -- -- in a webserver. Using `get_authorization_url` and `authorize`.
    -- callback_url = "http://localhost:54321/",
  },
}

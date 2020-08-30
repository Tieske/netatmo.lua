-- configuration data
-- for use with utilities in ./bin
-- update this file and rename it to `config.lua`.

return {
  auth_data = {
    -- authorization data for Netatmo login
    grant_type = "password",
    client_id = "xxxxxxxxxxxx",
    client_secret = "xxxxxxxxxxxx",
    username = "xxxxxxxxxxxx",
    password = "xxxxxxxxxxxxx",
    scope = "read_station",
  },
}

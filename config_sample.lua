-- configuration data

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
  push_interval = 60,  -- how often to check and update (in seconds)
  push_urls = {
    -- one entry per value, GET request is performed, so only a query string for passing data.
    {
      -- MAC string (case insensitive)
      module_id = "xxxxxxxxxxxxxxxx", -- Indoor
      -- data type to export, eg. Temperature (case insensitive)
      type = "CO2",
      -- use a '%s' where value is to be inserted
      url = "https://my.zipato.com/zipato-web/remoting/attribute/set?serial=xxxxxxxxxxxxxxxx&apiKey=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx&value3=%s",
    },
    -- add more entries here...
    {
      module_id = "xxxxxxxxxxxxxxxx", -- Rafi
      type = "CO2",
      url = "https://my.zipato.com/zipato-web/remoting/attribute/set?serial=xxxxxxxxxxxxxxxx&apiKey=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx&value2=%s",
    },
    {
      module_id = "xxxxxxxxxxxxxxxx", -- Noa
      type = "CO2",
      url = "https://my.zipato.com/zipato-web/remoting/attribute/set?serial=xxxxxxxxxxxxxxxx&apiKey=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx&value1=%s",
    },
  },
}

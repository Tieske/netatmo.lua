local package_name = "netatmo"
local package_version = "scm"
local rockspec_revision = "3"
local github_account_name = "Tieske"
local github_repo_name = package_name..".lua"

package = package_name
version = package_version.."-"..rockspec_revision

source = {
  url = "git+https://github.com/"..github_account_name.."/"..github_repo_name.."/",
  branch = (package_version == "cvs") and "master" or nil,
  tag = (package_version ~= "cvs") and package_version or nil,
}

description = {
  summary = "Lua module to provide Netatmo API access",
  detailed = [[
    Library to access the Netatmo REST API.
  ]],
  homepage = "https://github.com/"..github_account_name.."/"..github_repo_name,
  license = "MIT"
}

dependencies = {
  "lua >= 5.1, < 5.4",
  "luasec",
  "lua-cjson",
  "lualogging",
}

build = {
  type = "builtin",

  modules = {
    ["netatmo.init"] = "netatmo/init.lua",
  },
  copy_directories = {
    "docs",
 },
}

-- This file was automatically generated for the LuaDist project.

package = "lzmq-timer"
version = "0.3.5-1"

-- LuaDist source
source = {
  tag = "0.3.5-1",
  url = "git://github.com/LuaDist-testing/lzmq-timer.git"
}
-- Original source
-- source = {
--   url = "https://github.com/moteus/lzmq/archive/v0.3.5.zip",
--   dir = "lzmq-0.3.5",
-- }

description = {
  summary = "Milliseconds timer",
  homepage = "https://github.com/moteus/lzmq",
  license = "MIT/X11",
}

dependencies = {
  "lua >= 5.1, < 5.3",
}

build = {
  copy_directories = {},

  type = "builtin",

  platforms = {
    linux   = { modules = {
      ["lzmq.timer"] = {
        libraries = {"rt"},
      }
    }},
  },

  modules = {
    ["lzmq.timer"] = {
      sources = {'src/ztimer.c','src/lzutils.c'},
    },
  },
}
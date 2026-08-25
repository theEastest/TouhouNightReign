-- LuaSTG entry point. The engine loads this file from the game directory.
package.path = "scripts/?.lua;scripts/?/init.lua;" .. package.path
require("scripts.main")

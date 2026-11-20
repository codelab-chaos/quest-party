-- luacheck: what it looks for in Quest Party. The game's API is hundreds of
-- globals (CreateFrame, C_Timer, UnitName...) and the tests fake them, so
-- global reads and writes are not checked (codes 111 to 113); everything else
-- is: unused variables and values, shadowing, unreachable code.
std = "lua51"
max_line_length = false
ignore = {
	"111", -- setting a global (the game's frames and SavedVariables)
	"112", -- mutating a global
	"113", -- reading a global (the game's API)
	"212/self", -- an unused self in a method
	"212/_.*", -- arguments named _ on purpose
	"213/_.*", -- loop variables named _ on purpose
}
exclude_files = { "dist/**", "QuestParty/libs/**" } -- libraries as their authors ship them

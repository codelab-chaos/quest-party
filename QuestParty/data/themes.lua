-- Themes: the feed's whole palette, one per entry, picked with the Theme
-- slider in Settings (data\settings.lua). ui\panel.lua reads the chosen one
-- every time it draws a row, so a change shows at once. Row colors are
-- { left, right }: a gradient across the row.
--   panel            the panel's background
--   row              an ordinary feed row
--   card             a quest's progress row
--   level            a level-up row
--   handIn           a quest handed in
--   accepted, joined a quest taken, someone joining (feed types' tint)
--   rim              the thin line around each row (alpha 0: none)
--   well, wellEdge   the square behind a row's icon and its edge (alpha 0: none)
--   divider          the line down the row after the icon (alpha 0: none)
local _, ns = ...
local L = ns.L

ns.Themes = {
	-- The concept art: charcoal lit from the left, gold rims, icon wells.
	[0] = {
		id = "concept", label = L.THEME_CONCEPT,
		panel = { 0.02, 0.02, 0.03, 0.95 },
		row = { { 0.13, 0.13, 0.16, 0.97 }, { 0.04, 0.04, 0.05, 0.97 } },
		card = { { 0.09, 0.14, 0.26, 0.97 }, { 0.03, 0.04, 0.08, 0.97 } },
		level = { { 0.42, 0.16, 0.70, 0.97 }, { 0.09, 0.04, 0.16, 0.97 } },
		handIn = { { 0.34, 0.25, 0.07, 0.97 }, { 0.06, 0.05, 0.03, 0.97 } },
		accepted = { { 0.08, 0.16, 0.38, 0.97 }, { 0.03, 0.04, 0.09, 0.97 } }, -- a quest taken: deep blue
		joined = { { 0.10, 0.22, 0.45, 0.97 }, { 0.03, 0.05, 0.10, 0.97 } }, -- someone joined: blue
		rim = { 0.78, 0.62, 0.24, 0.70 },
		well = { 0.02, 0.02, 0.03, 1 },
		wellEdge = { 0.78, 0.62, 0.24, 0.85 },
		divider = { 0.78, 0.62, 0.24, 0.35 },
	},
	-- The game's own tooltips: black glass, silver edges, nothing warm but
	-- the gold in the text.
	[1] = {
		id = "classic", label = L.THEME_CLASSIC,
		panel = { 0, 0, 0, 0.85 },
		row = { { 0.08, 0.08, 0.09, 0.90 }, { 0.03, 0.03, 0.03, 0.90 } },
		card = { { 0.06, 0.10, 0.18, 0.90 }, { 0.02, 0.03, 0.06, 0.90 } },
		level = { { 0.30, 0.12, 0.50, 0.90 }, { 0.05, 0.02, 0.08, 0.90 } },
		handIn = { { 0.10, 0.24, 0.10, 0.90 }, { 0.02, 0.05, 0.02, 0.90 } },
		accepted = { { 0.06, 0.12, 0.26, 0.90 }, { 0.02, 0.03, 0.06, 0.90 } }, -- a quest taken: deep blue
		joined = { { 0.08, 0.16, 0.32, 0.90 }, { 0.02, 0.03, 0.06, 0.90 } }, -- someone joined: blue
		rim = { 0.55, 0.55, 0.60, 0.55 },
		well = { 0, 0, 0, 0.9 },
		wellEdge = { 0.60, 0.60, 0.65, 0.70 },
		divider = { 0, 0, 0, 0 },
	},
	-- Night sky: deep blue, cool silver-blue rims, bright highlights.
	[2] = {
		id = "midnight", label = L.THEME_MIDNIGHT,
		panel = { 0.01, 0.02, 0.06, 0.95 },
		row = { { 0.07, 0.11, 0.24, 0.97 }, { 0.02, 0.03, 0.08, 0.97 } },
		card = { { 0.05, 0.18, 0.30, 0.97 }, { 0.02, 0.05, 0.09, 0.97 } },
		level = { { 0.48, 0.18, 0.78, 0.97 }, { 0.08, 0.04, 0.18, 0.97 } },
		handIn = { { 0.55, 0.40, 0.08, 0.97 }, { 0.06, 0.05, 0.10, 0.97 } },
		accepted = { { 0.08, 0.20, 0.45, 0.97 }, { 0.02, 0.04, 0.10, 0.97 } }, -- a quest taken: deep blue
		joined = { { 0.10, 0.26, 0.55, 0.97 }, { 0.02, 0.04, 0.10, 0.97 } }, -- someone joined: blue
		rim = { 0.45, 0.60, 0.90, 0.55 },
		well = { 0.01, 0.02, 0.05, 1 },
		wellEdge = { 0.50, 0.65, 0.95, 0.75 },
		divider = { 0.45, 0.60, 0.90, 0.25 },
	},
	-- Quiet: near-black, no rims or wells, only a hairline between rows, so
	-- the icons and the text carry all the color.
	[3] = {
		id = "quiet", label = L.THEME_QUIET,
		panel = { 0.03, 0.03, 0.03, 0.90 },
		row = { { 0.07, 0.07, 0.07, 0.85 }, { 0.07, 0.07, 0.07, 0.85 } },
		card = { { 0.06, 0.08, 0.12, 0.85 }, { 0.06, 0.08, 0.12, 0.85 } },
		level = { { 0.26, 0.10, 0.42, 0.90 }, { 0.07, 0.07, 0.07, 0.85 } },
		handIn = { { 0.24, 0.18, 0.04, 0.90 }, { 0.07, 0.07, 0.07, 0.85 } },
		accepted = { { 0.08, 0.14, 0.28, 0.90 }, { 0.07, 0.07, 0.07, 0.85 } }, -- a quest taken: deep blue
		joined = { { 0.10, 0.18, 0.34, 0.90 }, { 0.07, 0.07, 0.07, 0.85 } }, -- someone joined: blue
		rim = { 1, 1, 1, 0.06 },
		well = { 0, 0, 0, 0 },
		wellEdge = { 0, 0, 0, 0 },
		divider = { 0, 0, 0, 0 },
	},
}

-- Each player's own color, the same everywhere they show: their XP bar, the
-- ring around their portrait, their part of Fuel (colors.lua hands them
-- out). Bright primaries first, then deep versions of them, so a party of
-- up to 16 has a color each.
ns.PlayerPalette = {
	{ 0.90, 0.18, 0.18 }, -- red
	{ 0.20, 0.45, 0.95 }, -- blue
	{ 0.98, 0.84, 0.12 }, -- yellow
	{ 0.18, 0.78, 0.28 }, -- green
	{ 0.62, 0.30, 0.92 }, -- purple
	{ 1.00, 0.52, 0.08 }, -- orange
	{ 0.12, 0.80, 0.88 }, -- cyan
	{ 0.95, 0.28, 0.72 }, -- magenta
	{ 0.62, 0.08, 0.08 }, -- deep red
	{ 0.10, 0.22, 0.65 }, -- navy
	{ 0.78, 0.60, 0.05 }, -- gold
	{ 0.08, 0.52, 0.18 }, -- forest
	{ 0.38, 0.15, 0.68 }, -- indigo
	{ 0.75, 0.32, 0.02 }, -- burnt orange
	{ 0.05, 0.55, 0.60 }, -- teal
	{ 0.68, 0.12, 0.48 }, -- plum
}

-- The chosen theme.
function ns.Theme()
	return ns.Themes[ns.GetSlider("theme") or 0] or ns.Themes[0]
end

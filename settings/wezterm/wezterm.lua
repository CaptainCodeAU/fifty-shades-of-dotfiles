----------------------------------------------------- WezTerm Configuration -----------------------------------------------------
-- Pull in the wezterm API
local wezterm = require("wezterm")
local act = wezterm.action

-- This will hold the configuration
local config = wezterm.config_builder()

----------------------------------------------------- Color Scheme -------------------------------------------------------
-- Custom Coolnight Color Scheme
config.colors = {
	foreground = "#CBE0F0",
	background = "#011423",
	cursor_bg = "#47FF9C",
	cursor_border = "#47FF9C",
	cursor_fg = "#011423",
	selection_bg = "#033259",
	selection_fg = "#CBE0F0",
	ansi = { "#214969", "#E52E2E", "#44FFB1", "#FFE073", "#0FC5ED", "#a277ff", "#24EAF7", "#24EAF7" },
	brights = { "#214969", "#E52E2E", "#44FFB1", "#FFE073", "#A277FF", "#a277ff", "#24EAF7", "#24EAF7" },
}

-- SSH/Remote Color Scheme (warmer, amber/orange tinted)
local ssh_colors = {
	foreground = "#F0E0CB",
	background = "#1A0F05",
	cursor_bg = "#FFE073",
	cursor_border = "#FFE073",
	cursor_fg = "#1A0F05",
	selection_bg = "#4D3319",
	selection_fg = "#F0E0CB",
	ansi = { "#6B5420", "#E52E2E", "#44FFB1", "#FFE073", "#E5A850", "#a277ff", "#24EAF7", "#24EAF7" },
	brights = { "#8B7030", "#E52E2E", "#44FFB1", "#FFE073", "#FFC870", "#a277ff", "#24EAF7", "#24EAF7" },
}

----------------------------------------------------- Window Styles -------------------------------------------------------
config.window_padding = {
	left = 5,
	right = 5,
	top = 5,
	bottom = 0.5,
}

config.macos_window_background_blur = 5

-- Subtle gradient background
config.window_background_gradient = {
	colors = { "#011423", "#01304a" }, -- More pronounced gradient from your Coolnight background
	orientation = "Vertical",
}
config.initial_cols = 120
config.initial_rows = 28

config.window_decorations = "RESIZE"
config.window_background_opacity = 0.8

-- Enable native window management (for better macOS integration and window snapping)
config.native_macos_fullscreen_mode = false
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = false

-- Inactive pane dimming - makes the active pane stand out
config.inactive_pane_hsb = {
	saturation = 0.6,
	brightness = 0.6,
}

----------------------------------------------------- Font Styles -------------------------------------------------------
config.font = wezterm.font("MesloLGS Nerd Font Mono")
config.font_size = 13
config.line_height = 0.9

-- Font Rendering Enhancements
config.harfbuzz_features = { "liga=1" } -- Enable ligatures
config.freetype_load_flags = "NO_HINTING" -- Crisper text rendering
config.hide_mouse_cursor_when_typing = true

----------------------------------------------------- Cursor Style -------------------------------------------------------
config.default_cursor_style = "BlinkingBlock"
config.animation_fps = 60
config.cursor_blink_rate = 500
config.cursor_blink_ease_in = "EaseIn"
config.cursor_blink_ease_out = "EaseOut"
config.force_reverse_video_cursor = false

----------------------------------------------------- Default Terminal -------------------------------------------------------
config.default_prog = { "zsh" }
config.default_cwd = wezterm.home_dir .. "/CODE/Ideas"

----------------------------------------------------- Quality-of-Life Settings -------------------------------------------------------
config.scrollback_lines = 100000
config.use_dead_keys = true
config.audible_bell = "Disabled"
config.window_close_confirmation = "NeverPrompt"
config.adjust_window_size_when_changing_font_size = false

-- Enhanced UX Settings
config.pane_focus_follows_mouse = true -- Hover to focus panes
config.switch_to_last_active_tab_when_closing_tab = true -- Jump to recently used tab
config.unzoom_on_switch_pane = true -- Auto-unzoom when switching panes
config.status_update_interval = 1000 -- Status bar refresh rate (ms)

-- Command Palette Styling
config.command_palette_font_size = 12
-- config.command_palette_rows = 7

----------------------------------------------------- Tab Bar Styles -------------------------------------------------------
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = true
config.tab_max_width = 50 -- Increased from 25 to 50 for wider tabs
config.show_tab_index_in_tab_bar = false
config.tab_and_split_indices_are_zero_based = true

-- PowerLine arrow symbols from Nerd Fonts
local SOLID_LEFT_ARROW = wezterm.nerdfonts.pl_right_hard_divider
local SOLID_RIGHT_ARROW = wezterm.nerdfonts.pl_left_hard_divider

-- Rounded corner symbols for modern tab look
local LEFT_ROUNDED = wezterm.nerdfonts.ple_left_half_circle_thick
local RIGHT_ROUNDED = wezterm.nerdfonts.ple_right_half_circle_thick

-- SSH/Remote indicator icon (choose one by uncommenting)
local SSH_ICON = wezterm.nerdfonts.md_lan -- LAN cable icon (default)
-- local SSH_ICON = wezterm.nerdfonts.md_server_network -- Server network icon
-- local SSH_ICON = wezterm.nerdfonts.md_web -- Network web icon
-- local SSH_ICON = wezterm.nerdfonts.fa_exchange -- Exchange/connection icon
-- local SSH_ICON = wezterm.nerdfonts.cod_remote -- Remote icon

----------------------------------------------------- Performance Optimizations -------------------------------------------------------
config.front_end = "WebGpu"
config.webgpu_preferred_adapter = wezterm.gui.enumerate_gpus()[1]

----------------------------------------------------- Keybindings -------------------------------------------------------
-- Leader Key Configuration
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 2000 }

config.keys = {
	---------------------- Window Management ----------------------
	-- FZF Integration
	{ mods = "CTRL", key = "f", action = act.SendString("fzf") }, -- Search entire system
	{ mods = "CTRL|SHIFT", key = "f", action = act.SendString("fd . --type f --hidden | fzf") }, -- Search current dir

	{ mods = "CTRL|SHIFT", key = "p", action = act.ActivateCommandPalette },
	{ mods = "LEADER", key = "n", action = act.SpawnCommandInNewWindow({ args = { "zsh" } }) },
	{ mods = "LEADER|SHIFT", key = "Q", action = act.QuitApplication },

	-- Scrolling
	{ mods = "SHIFT", key = "PageUp", action = act.ScrollByPage(-0.25) },
	{ mods = "SHIFT", key = "PageDown", action = act.ScrollByPage(0.25) },

	---------------------- Editing Text ----------------------
	{ mods = "CTRL|SHIFT", key = "c", action = act.CopyTo("Clipboard") },
	{ mods = "CTRL|SHIFT", key = "v", action = act.PasteFrom("Clipboard") },
	{ mods = "CTRL|SHIFT|ALT", key = "c", action = act.ActivateCopyMode },
	{ mods = "ALT", key = "Escape", action = act.CopyMode("Close") },

	---------------------- Tab Management ----------------------
	-- Rename Tab
	{
		mods = "LEADER",
		key = "r",
		action = act.PromptInputLine({
			description = "Rename your Tab",
			action = wezterm.action_callback(function(window, _, line)
				if line then
					window:active_tab():set_title(line)
				end
			end),
		}),
	},
	-- Create new tab
	{ mods = "LEADER", key = "t", action = act.SpawnCommandInNewTab({ args = { "zsh" } }) },
	-- Navigate through tabs
	{ mods = "ALT", key = "LeftArrow", action = act.ActivateTabRelative(-1) },
	{ mods = "ALT", key = "RightArrow", action = act.ActivateTabRelative(1) },
	-- Close current tab
	{ mods = "CTRL", key = "w", action = act.CloseCurrentTab({ confirm = true }) },

	---------------------- Font Management ----------------------
	{ mods = "CTRL", key = "=", action = act.IncreaseFontSize },
	{ mods = "CTRL", key = "-", action = act.DecreaseFontSize },
	{ mods = "LEADER|CTRL", key = "0", action = act.ResetFontSize },

	---------------------- Debug / Utility ----------------------
	-- Show debug overlay (CTRL+SHIFT+L) to see window position info

	---------------------- Pane / Multiplexer Management ----------------------
	-- Split panes
	{ mods = "LEADER|SHIFT", key = "|", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
	{ mods = "LEADER", key = "\\", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
	-- Select pane
	{ mods = "CTRL|ALT|SHIFT", key = "|", action = act.PaneSelect({ alphabet = "0123456789" }) },
	-- Close pane
	{ mods = "LEADER|SHIFT", key = "X", action = act.CloseCurrentPane({ confirm = false }) },
	-- Resize panes
	{ mods = "CTRL|SHIFT", key = "UpArrow", action = act.AdjustPaneSize({ "Up", 1 }) },
	{ mods = "CTRL|SHIFT", key = "DownArrow", action = act.AdjustPaneSize({ "Down", 1 }) },
	{ mods = "CTRL|SHIFT", key = "LeftArrow", action = act.AdjustPaneSize({ "Left", 1 }) },
	{ mods = "CTRL|SHIFT", key = "RightArrow", action = act.AdjustPaneSize({ "Right", 1 }) },
	-- Navigate by word
	{ mods = "CTRL", key = "LeftArrow", action = act.SendString("\x1bb") },
	{ mods = "CTRL", key = "RightArrow", action = act.SendString("\x1bf") },
	-- Toggle fullscreen and hide
	{ mods = "ALT", key = "Enter", action = act.ToggleFullScreen },
	{ mods = "ALT", key = "h", action = act.Hide },
}

-- Navigate to tabs by index (Leader + 0-9)
for i = 0, 9 do
	table.insert(config.keys, {
		key = tostring(i),
		mods = "LEADER",
		action = act.ActivateTab(i),
	})
end

----------------------------------------------------- Event Handlers -------------------------------------------------------

-- Set initial window position on startup
wezterm.on("gui-startup", function(cmd)
	local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
	local gui_win = window:gui_window()
	if gui_win then
		gui_win:set_position(0, 1524)
	end
end)

-- Log window position on config reload (for debugging)
-- Note: Removed as window:gui_window() is not available in this context

-- Custom tab bar styling with PowerLine arrows
wezterm.on("format-tab-title", function(tab, tabs, panes, config, hover, max_width)
	local background = "#033259"
	local foreground = "#CBE0F0"
	local edge_background = "#011423"
	local edge_foreground = background

	-- Check if this is a remote/SSH session
	local is_remote = false
	if tab.active_pane and tab.active_pane.user_vars then
		is_remote = tab.active_pane.user_vars.IS_REMOTE == "true"
	end

	-- Also check the foreground process name for SSH
	local process_name = tab.active_pane.foreground_process_name or ""
	if process_name:find("ssh") then
		is_remote = true
	end

	-- Set colors based on tab state and SSH status
	if tab.is_active then
		if is_remote then
			-- Active SSH/remote tab: orange/amber color
			background = "#f9c823"
			foreground = "#011423"
		else
			-- Active local tab: cyan color
			background = "#0965c0"
			foreground = "#CBE0F0"
		end
		edge_foreground = background
	elseif hover then
		if is_remote then
			-- Hover SSH/remote tab: darker orange
			background = "#E5A850"
			foreground = "#011423"
		else
			-- Hover local tab: medium blue
			background = "#214969"
			foreground = "#CBE0F0"
		end
		edge_foreground = background
	else
		if is_remote then
			-- Inactive SSH/remote tab: muted orange
			background = "#6B5420"
			foreground = "#CBE0F0"
		else
			-- Inactive local tab: dark blue
			background = "#033259"
			foreground = "#CBE0F0"
		end
		edge_foreground = background
	end

	local title = tab.active_pane.title
	-- Add SSH indicator to remote sessions
	if is_remote then
		title = SSH_ICON .. " " .. title
	end

	-- Ensure title fits within max_width
	if #title > max_width - 2 then
		title = wezterm.truncate_right(title, max_width - 2) .. "…"
	end

	return {
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } }, -- Subtle gray for separator
		{ Text = LEFT_ROUNDED },
		{ Background = { Color = background } },
		{ Foreground = { Color = foreground } },
		{ Text = title },
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = RIGHT_ROUNDED },
		{ Background = { Color = "#000000" } },
		{ Foreground = { Color = "#aaaaaa" } }, -- Subtle gray for separator
		{ Text = "·" }
	}
end)

-- Set window title for SSH sessions
wezterm.on("format-window-title", function(tab, pane, tabs, panes, config)
	if tab.active_pane and tab.active_pane.foreground_process_name then
		local process_name = tab.active_pane.foreground_process_name
		if process_name:find("ssh") then
			return "SSH: " .. tab.active_pane.title
		end
	end
	return tab.active_pane.title
end)

-- Apply SSH background gradient when in SSH pane
wezterm.on("update-status", function(window, pane)
	local process_name = pane:get_foreground_process_name() or ""
	local is_remote = process_name:find("ssh") ~= nil

	local overrides = window:get_config_overrides() or {}

	if is_remote then
		-- Rich earthy gradient for SSH sessions (deeper brown to warm amber)
		overrides.window_background_gradient = {
			colors = { "#140A03", "#351F10" }, -- Deeper brown to balanced warm amber
			orientation = "Vertical",
		}
	else
		-- Reset to default Coolnight gradient
		if overrides.window_background_gradient then
			overrides.window_background_gradient = nil
		end
	end

	window:set_config_overrides(overrides)
end)

-- Visual indicator when leader key is active
wezterm.on("update-right-status", function(window, _)
	local prefix = ""

	if window:leader_is_active() then
		prefix = "" .. utf8.char(0x1f47e) .. "" -- 👾 Space Invader icon
	end

	window:set_left_status(wezterm.format({
		{ Background = { Color = "black" } },
		{ Foreground = { Color = "#0FC5ED" } },
		{ Text = prefix },
	}))
end)

----------------------------------------------------- Return Configuration -------------------------------------------------------
return config

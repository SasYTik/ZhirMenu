--  Multi-inject guard

do
	local env = (type(getgenv) == "function" and getgenv()) or _G
	if env._StatsGUI_Instance then
		local inst = env._StatsGUI_Instance
		if inst.show then inst.show() end
		return
	end
	env._StatsGUI_Instance = { active = true }
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local currentPlaceId = game.PlaceId
local universeId = game.GameId


--  Connection tracker (Bug #1 fix)

local _allConns = {}
local function trackConn(conn)
	table.insert(_allConns, conn)
	return conn
end


--  Original game values (captured before GUI loads)


local _origValues = (function()
	local ch = player.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local cam = Workspace.CurrentCamera
	return {
		walkSpeed    = (hum and hum.WalkSpeed)               or 16,
		jumpPower    = (hum and hum.JumpPower)               or 50,
		gravity      = Workspace.Gravity                     or 196,
		fov          = (cam and cam.FieldOfView)             or 70,
		camMinZoom   = pcall(function() return player.CameraMinZoomDistance end) and player.CameraMinZoomDistance or 0.5,
		camMaxZoom   = pcall(function() return player.CameraMaxZoomDistance end) and player.CameraMaxZoomDistance or 400,
	}
end)()


--  Global state


local State = {
	walkSpeed = 16,
	jumpPower = 50,
	gravity = 196,
	fov = 70,
	cameraUnlock = false,
	camDistance = 20,
	removeLighting = false,
	freezePlayer = false,
	infJump = false,
	noclip = false,
	fly = false,
	esp = false,
	invisible = false,
	freecam = false,
	flySpeed = 50,
	sliderStep = 1,
	separateFlySpeed = false,
	antiAfk = false,
	hitboxExpander = false,
	hitboxSize = 10,
	guiScale = 100,
	guiOpacity = 0,
	invisYOffset = 200000,
	autoexecPath = "",
}

local Keybinds = {
	toggleGUI   = Enum.KeyCode.RightControl,
	unlockCam   = Enum.KeyCode.RightBracket,
	freecam     = Enum.KeyCode.F,
	invisible   = Enum.KeyCode.I,
	fly         = Enum.KeyCode.G,
}

-- Bug #4 fix: flag set while waiting for a new keybind input
local isRebinding = false


--  Settings save / load


local _settingsPending = false
local _settingsSuppressed = false -- Bug #3 fix

local function saveSettings()
	if _settingsPending or _settingsSuppressed then return end
	_settingsPending = true
	task.delay(0.5, function()
		_settingsPending = false
		if _settingsSuppressed then return end
		pcall(function()
			if not isfolder("RSS") then makefolder("RSS") end
			local numKeys = {"walkSpeed","jumpPower","gravity","fov","camDistance","flySpeed","sliderStep","hitboxSize","guiScale","guiOpacity","invisYOffset"}
			local strKeys = {"autoexecPath"}
			local parts = {}
			for _, k in ipairs(numKeys) do
				table.insert(parts, string.format('    "%s": %s', k, tostring(State[k])))
			end
			for _, k in ipairs(strKeys) do
				local v = State[k] or ""
				table.insert(parts, string.format('    "%s": "%s"', k, v:gsub('"', '\\"')))
			end
			writefile("RSS/settings.json", "{\n" .. table.concat(parts, ",\n") .. "\n}")
		end)
	end)
end

pcall(function()
	if not isfolder("RSS") then makefolder("RSS") end
	local path = "RSS/settings.json"
	if isfile(path) then
		local data = HttpService:JSONDecode(readfile(path))
		if type(data) == "table" then
			for k, v in pairs(data) do
				if State[k] ~= nil and type(v) == "number" then State[k] = v end
				if State[k] ~= nil and type(v) == "string" and type(State[k]) == "string" then State[k] = v end
			end
		end
	end
end)

task.spawn(function()
	task.wait(0.2)
	local ch = player.Character
	if ch then
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = State.walkSpeed
			hum.UseJumpPower = true
			hum.JumpPower = State.jumpPower
		end
	end
	Workspace.Gravity = State.gravity
	if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = State.fov end
end)


--  Win10 Colours


local C = {
	titleBar       = Color3.fromRGB(18, 18, 28),
	window         = Color3.fromRGB(24, 24, 36),
	surface        = Color3.fromRGB(32, 32, 48),
	surfaceHover   = Color3.fromRGB(42, 42, 62),
	border         = Color3.fromRGB(50, 48, 72),
	accent         = Color3.fromRGB(99, 102, 241),
	accentHover    = Color3.fromRGB(129, 132, 255),
	accentDark     = Color3.fromRGB(67, 56, 202),
	textPrimary    = Color3.fromRGB(240, 240, 255),
	textSecondary  = Color3.fromRGB(170, 170, 200),
	textDim        = Color3.fromRGB(110, 110, 145),
	closeHover     = Color3.fromRGB(220, 38, 38),
	captionHover   = Color3.fromRGB(38, 38, 56),
	toggleOff      = Color3.fromRGB(90, 90, 120),
	sliderTrack    = Color3.fromRGB(44, 44, 64),
	disabled       = Color3.fromRGB(44, 44, 64),
	disabledText   = Color3.fromRGB(75, 75, 100),
	selected       = Color3.fromRGB(67, 56, 202),
	currentPlace   = Color3.fromRGB(34, 50, 40),
	errorText      = Color3.fromRGB(248, 113, 113),
	panelStroke    = Color3.fromRGB(55, 52, 80),
	surfaceAlt     = Color3.fromRGB(28, 28, 42),
}


--  Utilities


local function create(class, props)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then inst[k] = v end
	end
	if props.Parent then inst.Parent = props.Parent end
	return inst
end

local function addCorner(parent, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius or 0), Parent = parent })
end

local function addStroke(parent, color, thickness, transparency)
	return create("UIStroke", {
		Color = color or C.panelStroke,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		Parent = parent,
	})
end

local function setClipboard(text)
	local ok1 = pcall(function() if setclipboard then setclipboard(tostring(text)) return end error("no fn") end)
	if ok1 then return true end
	local ok2 = pcall(function() if toclipboard then toclipboard(tostring(text)) return end error("no fn") end)
	return ok2
end


--  ScreenGui


local screenGui = create("ScreenGui", {
	Name = "StatsGUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
	Parent = playerGui,
})
pcall(function()
	local cg = game:GetService("CoreGui")
	if syn and syn.protect_gui then syn.protect_gui(screenGui) end
	screenGui.Parent = cg
end)


--  Toast notifications


local toastContainer = create("Frame", {
	Name = "ToastContainer",
	Size = UDim2.new(0, 260, 1, 0),
	Position = UDim2.new(1, -270, 0, 0),
	BackgroundTransparency = 1,
	ClipsDescendants = false,
	ZIndex = 100,
	Parent = screenGui,
})
create("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 6),
	Parent = toastContainer,
})
create("UIPadding", {
	PaddingBottom = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 8),
	Parent = toastContainer,
})

local _toastOrder = 0
local function showToast(text, duration, color)
	_toastOrder = _toastOrder + 1
	duration = duration or 2.5
	color = color or C.accent
	local toast = create("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = C.titleBar,
		BorderSizePixel = 0,
		LayoutOrder = _toastOrder,
		ZIndex = 100,
		Parent = toastContainer,
	})
	addCorner(toast, 6)
	addStroke(toast, color, 1, 0.3)
	-- Accent bar left
	local bar = create("Frame", {
		Size = UDim2.new(0, 3, 1, -8),
		Position = UDim2.new(0, 6, 0, 4),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = 101,
		Parent = toast,
	})
	addCorner(bar, 2)
	create("TextLabel", {
		Text = text,
		Size = UDim2.new(1, -20, 1, 0),
		Position = UDim2.new(0, 16, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = C.textPrimary,
		Font = Enum.Font.SourceSans,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 101,
		Parent = toast,
	})
	-- Slide in from right
	toast.Position = UDim2.new(1, 0, 0, 0)
	toast:TweenPosition(UDim2.new(0, 0, 0, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.2, true)
	task.delay(duration, function()
		if toast.Parent then
			toast:TweenPosition(UDim2.new(1, 0, 0, 0), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.2, true)
			task.delay(0.25, function()
				if toast.Parent then toast:Destroy() end
			end)
		end
	end)
end


--  Window


local WIN_W = 360
local WIN_H = 650

local window = create("Frame", {
	Name = "Window",
	Size = UDim2.fromOffset(WIN_W, WIN_H),
	Position = UDim2.new(0.5, -math.floor(WIN_W/2), 0.5, -math.floor(WIN_H/2)),
	BackgroundColor3 = C.window,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = screenGui,
})

local WINDOW_MARGIN = 14

local function getViewportSize()
	local cam = Workspace.CurrentCamera
	if cam and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
		return cam.ViewportSize
	end
	local abs = screenGui.AbsoluteSize
	if abs.X > 0 and abs.Y > 0 then
		return abs
	end
	return Vector2.new(1280, 720)
end

local function clampWindowOffsets(x, y)
	local viewport = getViewportSize()
	local size = window.AbsoluteSize
	local maxX = math.max(WINDOW_MARGIN, viewport.X - size.X - WINDOW_MARGIN)
	local maxY = math.max(WINDOW_MARGIN, viewport.Y - size.Y - WINDOW_MARGIN)
	return math.clamp(x, WINDOW_MARGIN, maxX), math.clamp(y, WINDOW_MARGIN, maxY)
end

local function setWindowOffsets(x, y)
	x, y = clampWindowOffsets(x, y)
	window.Position = UDim2.fromOffset(x, y)
end

-- Opacity helper: stores original BG transparency for each frame, blends with opacity
local _origBGTrans = {}
local function applyWindowOpacity(opacity)
	local function recurse(inst)
		for _, child in ipairs(inst:GetChildren()) do
			if child:IsA("Frame") or child:IsA("ScrollingFrame") or child:IsA("TextButton") or child:IsA("TextLabel") or child:IsA("TextBox") then
				if _origBGTrans[child] == nil then
					_origBGTrans[child] = child.BackgroundTransparency
				end
				local base = _origBGTrans[child]
				if base < 1 then
					child.BackgroundTransparency = math.min(1, base + opacity * (1 - base))
				end
				recurse(child)
			elseif child:IsA("UIStroke") then
				child.Transparency = math.min(1, opacity)
			end
		end
	end
	recurse(window)
end

task.defer(function()
	local viewport = getViewportSize()
	setWindowOffsets(math.floor((viewport.X - WIN_W) / 2), math.floor((viewport.Y - WIN_H) / 2))
	-- Apply saved GUI Scale & Opacity
	if State.guiScale ~= 100 then
		local s = State.guiScale / 100
		window.Size = UDim2.fromOffset(math.floor(WIN_W * s), math.floor(WIN_H * s))
	end
	if State.guiOpacity > 0 then
		applyWindowOpacity(State.guiOpacity / 100)
	end
end)

trackConn(screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	setWindowOffsets(window.Position.X.Offset, window.Position.Y.Offset)
end))


--  Title Bar


local TITLE_H_PX = 30

local titleBar = create("Frame", {
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, TITLE_H_PX),
	Position = UDim2.fromOffset(0, 0),
	BackgroundColor3 = C.titleBar,
	BorderSizePixel = 0,
	Parent = window,
})

create("TextLabel", {
	Text = "ZhirMenu",
	Size = UDim2.new(0.5, 0, 1, 0),
	Position = UDim2.new(0.03, 0, 0, 0),
	BackgroundTransparency = 1,
	TextColor3 = C.textSecondary,
	Font = Enum.Font.GothamSemibold,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = titleBar,
})

local pingLabel = create("TextLabel", {
	Text = "",
	Size = UDim2.new(0.18, 0, 1, 0),
	Position = UDim2.new(0.49, 0, 0, 0),
	BackgroundTransparency = 1,
	TextColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = titleBar,
})

task.spawn(function()
	while screenGui and screenGui.Parent do
		local ok, ping = pcall(function() return math.floor(player:GetNetworkPing() * 1000) end)
		pingLabel.Text = ok and (ping .. " ms") or "? ms"
		task.wait(1)
	end
end)

local CAP_W = 0.1  -- each caption button width as fraction

local function captionButton(text, orderFromRight, hoverColor)
	local btn = create("TextButton", {
		Text = text,
		Size = UDim2.new(CAP_W, 0, 1, 0),
		Position = UDim2.new(1 - CAP_W * orderFromRight, 0, 0, 0),
		BackgroundColor3 = C.titleBar,
		TextColor3 = C.textSecondary,
		Font = Enum.Font.SourceSans,
		TextSize = text == "X" and 20 or 18,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Parent = titleBar,
	})
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = hoverColor
		if hoverColor == C.closeHover then btn.TextColor3 = Color3.new(1,1,1) end
	end)
	btn.MouseLeave:Connect(function()
		btn.BackgroundColor3 = C.titleBar; btn.TextColor3 = C.textSecondary
	end)
	return btn
end

local minimizeBtn = captionButton("-", 3, C.captionHover)
local maximizeBtn = captionButton("□", 2, C.captionHover)
local closeBtn    = captionButton("X", 1, C.closeHover)
maximizeBtn.Active = false

-- Accent line under title (gradient glow)
local accentLine = create("Frame", {
	Size = UDim2.new(1, 0, 0, 2),
	Position = UDim2.new(0, 0, 1, 0),
	BackgroundColor3 = C.accent,
	BorderSizePixel = 0,
	Parent = titleBar,
})
create("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(99, 102, 241)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(168, 85, 247)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(99, 102, 241)),
	}),
	Parent = accentLine,
})


--  Tab Bar


local TAB_H_PX = 28
local TAB_TOP_PX = TITLE_H_PX  -- right below title

local tabBar = create("Frame", {
	Name = "TabBar",
	Size = UDim2.new(1, 0, 0, TAB_H_PX),
	Position = UDim2.new(0, 0, 0, TAB_TOP_PX),
	BackgroundColor3 = C.titleBar,
	BorderSizePixel = 0,
	Parent = window,
})

local tabNames = { "Player", "SubPlaces", "Teleport", "Players", "Settings" }
local tabButtons = {}
local tabPages = {}
local activeTab = 1

local function switchTab(index)
	activeTab = index
	for i, btn in ipairs(tabButtons) do
		if i == index then
			btn.BackgroundColor3 = C.window; btn.TextColor3 = C.textPrimary
		else
			btn.BackgroundColor3 = C.titleBar; btn.TextColor3 = C.textDim
		end
	end
	for i, page in ipairs(tabPages) do page.Visible = (i == index) end
end

local TAB_W = 1 / #tabNames
for i, name in ipairs(tabNames) do
	local tabBtn = create("TextButton", {
		Text = name,
		Size = UDim2.new(TAB_W, 0, 1, 0),
		Position = UDim2.new(TAB_W * (i - 1), 0, 0, 0),
		BackgroundColor3 = i == 1 and C.window or C.titleBar,
		TextColor3 = i == 1 and C.textPrimary or C.textDim,
		Font = Enum.Font.SourceSans,
		TextSize = 13,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Parent = tabBar,
	})
	tabBtn.MouseButton1Click:Connect(function() switchTab(i) end)
	tabBtn.MouseEnter:Connect(function()
		if activeTab ~= i then tabBtn.BackgroundColor3 = C.captionHover end
	end)
	tabBtn.MouseLeave:Connect(function()
		if activeTab ~= i then tabBtn.BackgroundColor3 = C.titleBar end
	end)
	table.insert(tabButtons, tabBtn)
end

create("Frame", {
	Size = UDim2.new(1, 0, 0, 1),
	Position = UDim2.new(0, 0, 1, -1),
	BackgroundColor3 = C.border,
	BorderSizePixel = 0,
	Parent = tabBar,
})


--  Pages — content area below tab bar


local PAGE_TOP_PX = TAB_TOP_PX + TAB_H_PX  -- 58 px from top
local PAGE_PAD = 0.024             -- horizontal padding as Scale
local SCROLL_PAD_X = 8
local SCROLL_PAD_Y = 6

local function makePage(name, isScroll, vis)
	local props = {
		Name = name,
		Size = UDim2.new(1 - PAGE_PAD * 2, 0, 1, -PAGE_TOP_PX),
		Position = UDim2.new(PAGE_PAD, 0, 0, PAGE_TOP_PX),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = vis,
		Parent = window,
	}
	if isScroll then
		props.BorderSizePixel = 0
		props.ScrollBarThickness = 5
		props.ScrollBarImageColor3 = C.accent
		props.ScrollingDirection = Enum.ScrollingDirection.Y
		props.CanvasSize = UDim2.new(0, 0, 0, 0)
		props.AutomaticCanvasSize = Enum.AutomaticSize.Y
	end
	local pg = create(isScroll and "ScrollingFrame" or "Frame", props)
	if isScroll then
		create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6), Parent = pg })
		create("UIPadding", {
			PaddingLeft = UDim.new(0, SCROLL_PAD_X),
			PaddingRight = UDim.new(0, SCROLL_PAD_X + 4),
			PaddingTop = UDim.new(0, SCROLL_PAD_Y),
			PaddingBottom = UDim.new(0, SCROLL_PAD_Y),
			Parent = pg,
		})
	end
	table.insert(tabPages, pg)
	return pg
end

local page1 = makePage("PagePlayer",    true,  true)
local page2 = makePage("PageSubPlaces", false, false)
local page3 = makePage("PageTeleport",  false, false)
local page4 = makePage("PagePlayers",   true,  false)
local page5 = makePage("PageSettings",  true,  false)


--  Builders


local function createSectionHeader(parent, text, order)
	local hdr = create("TextLabel", {
		Text = "  " .. text,
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		TextColor3 = C.accent,
		Font = Enum.Font.GothamSemibold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	})
end

-- Slider tracker for Bug #2: reset syncs UI
local _sliders = {} -- { key = { update = fn(value) } }

local function createSlider(parent, label, min, max, default, order, callback, stateKey)
	local container = create("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.surface,
		BorderSizePixel = 0,
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = parent,
	})
	addCorner(container, 6)
	addStroke(container, C.panelStroke, 1, 0.5)

	create("TextLabel", {
		Text = label,
		Size = UDim2.new(0.62, 0, 0, 44),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = C.textPrimary,
		Font = Enum.Font.SourceSans,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = container,
	})

	-- Value display label
	local valueLabel = create("TextLabel", {
		Text = tostring(default),
		Size = UDim2.new(0, 64, 0, 44),
		Position = UDim2.new(1, -72, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = C.accent,
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 2,
		Parent = container,
	})

	-- TextBox shown when clicking the value label (keyboard input)
	local valueBox = create("TextBox", {
		Text = tostring(default),
		Size = UDim2.new(0, 64, 0, 36),
		Position = UDim2.new(1, -72, 0, 4),
		BackgroundColor3 = C.sliderTrack,
		TextColor3 = C.textPrimary,
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Center,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Visible = false,
		ZIndex = 6,
		Parent = container,
	})
	addCorner(valueBox, 3)
	addStroke(valueBox, C.accent, 1)

	-- Transparent button on top of value label to capture click
	local valueBtn = create("TextButton", {
		Size = UDim2.new(0, 72, 0, 44),
		Position = UDim2.new(1, -72, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		ZIndex = 4,
		Parent = container,
	})

	-- Bottom-edge track: full width, 6px tall, flush to bottom
	local track = create("Frame", {
		Size = UDim2.new(1, 0, 0, 6),
		Position = UDim2.new(0, 0, 1, -6),
		BackgroundColor3 = C.sliderTrack,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = container,
	})

	local fill = create("Frame", {
		Size = UDim2.new((default - min) / (max - min), 0, 1, 0),
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = track,
	})

	-- Thin separator line above track
	create("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		Position = UDim2.new(0, 0, 1, -7),
		BackgroundColor3 = C.border,
		BorderSizePixel = 0,
		Parent = container,
	})

	local dragging = false

	local function setVisual(value)
		local rel = math.clamp((value - min) / (max - min), 0, 1)
		fill.Size = UDim2.new(rel, 0, 1, 0)
		valueLabel.Text = tostring(value)
	end

	local function update(inputPos)
		local absX = container.AbsolutePosition.X
		local absW = container.AbsoluteSize.X
		local rel = math.clamp((inputPos - absX) / absW, 0, 1)
		local step = (stateKey == "sliderStep") and 1 or math.max(1, math.floor(State.sliderStep or 1))
		local raw = min + rel * (max - min)
		local value = math.clamp(math.floor(raw / step + 0.5) * step, min, max)
		setVisual(value)
		if callback then callback(value) end
	end

	-- Click value label → show TextBox for keyboard input
	valueBtn.MouseButton1Click:Connect(function()
		valueLabel.Visible = false
		valueBox.Text = valueLabel.Text
		valueBox.Visible = true
		valueBox:CaptureFocus()
	end)
	valueBox.FocusLost:Connect(function()
		local v = tonumber(valueBox.Text)
		if v then
			v = math.clamp(math.floor(v + 0.5), min, max)
			setVisual(v)
			if callback then callback(v) end
		end
		valueBox.Visible = false
		valueLabel.Visible = true
	end)

	-- Only start drag when clicking outside the value button area
	container.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			local relX = input.Position.X - container.AbsolutePosition.X
			if relX < container.AbsoluteSize.X - 76 then
				dragging = true; update(input.Position.X)
			end
		end
	end)
	-- Bug #1: track slider drag connections for cleanup
	trackConn(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			update(input.Position.X)
		end
	end))
	trackConn(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	-- Bug #2: register for reset
	if stateKey then
		_sliders[stateKey] = { update = setVisual }
	end
end

local function createToggle(parent, label, order, callback)
	local state = false
	local container = create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = C.surface,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = parent,
	})
	addCorner(container, 6)
	addStroke(container, C.panelStroke, 1, 0.5)

	create("TextLabel", {
		Text = label,
		Size = UDim2.new(0.72, 0, 1, 0),
		Position = UDim2.new(0.04, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = C.textPrimary,
		Font = Enum.Font.SourceSans,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = container,
	})

	local tTrack = create("Frame", {
		Size = UDim2.new(0, 40, 0, 20),
		Position = UDim2.new(1, -48, 0.5, -10),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = container,
	})
	addCorner(tTrack, 10)
	local tBorder = create("UIStroke", { Color = C.toggleOff, Thickness = 2, Parent = tTrack })

	local tKnob = create("Frame", {
		Size = UDim2.new(0, 14, 0, 14),
		Position = UDim2.new(0, 3, 0.5, -7),
		BackgroundColor3 = C.toggleOff,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = tTrack,
	})
	addCorner(tKnob, 7)

	local function updateVis()
		if state then
			tTrack.BackgroundTransparency = 0
			tTrack.BackgroundColor3 = C.accent
			tBorder.Color = C.accent
			tKnob.BackgroundColor3 = Color3.new(1,1,1)
			tKnob:TweenPosition(UDim2.new(1, -17, 0.5, -7), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true)
		else
			tTrack.BackgroundTransparency = 1
			tBorder.Color = C.toggleOff
			tKnob.BackgroundColor3 = C.toggleOff
			tKnob:TweenPosition(UDim2.new(0, 3, 0.5, -7), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true)
		end
	end

	local btn = create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "", ZIndex = 3,
		Parent = container,
	})
	btn.MouseButton1Click:Connect(function()
		state = not state; updateVis()
		if callback then callback(state) end
	end)

	return {
		getState = function() return state end,
		setState = function(v) state = v; updateVis() end,
	}
end

════════════════
--                  PAGE 1: PLAYER
════════════════

createSectionHeader(page1, "Movement", 0)

createSlider(page1, "WalkSpeed", 0, 500, State.walkSpeed, 1, function(v)
	State.walkSpeed = v
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h then h.WalkSpeed = v end
	saveSettings()
end, "walkSpeed")

createSlider(page1, "JumpPower", 0, 500, State.jumpPower, 2, function(v)
	State.jumpPower = v
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h then h.UseJumpPower = true; h.JumpPower = v end
	saveSettings()
end, "jumpPower")

createSlider(page1, "Gravity", 0, 500, State.gravity, 3, function(v)
	State.gravity = v; Workspace.Gravity = v
	saveSettings()
end, "gravity")

createSectionHeader(page1, "Camera", 4)

createSlider(page1, "Field of View", 30, 120, State.fov, 5, function(v)
	State.fov = v
	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = v end
	saveSettings()
end, "fov")

local origCamMode, origMinZoom, origMaxZoom = nil, nil, nil

local function applyCamUnlock()
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMinZoomDistance = State.camDistance
	player.CameraMaxZoomDistance = State.camDistance
	task.defer(function()
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = State.camDistance
	end)
end

local function restoreCam()
	if origCamMode then player.CameraMode = origCamMode end
	if origMinZoom then player.CameraMinZoomDistance = origMinZoom end
	if origMaxZoom then player.CameraMaxZoomDistance = origMaxZoom end
	origCamMode = nil; origMinZoom = nil; origMaxZoom = nil
end

local camToggle = createToggle(page1, "Unlock Camera  ( ] )", 6, function(on)
	State.cameraUnlock = on
	if on then
		if not origCamMode then
			origCamMode = player.CameraMode
			origMinZoom = player.CameraMinZoomDistance
			origMaxZoom = player.CameraMaxZoomDistance
		end
		applyCamUnlock()
	else restoreCam() end
end)

createSlider(page1, "Zoom Distance", 2, 128, State.camDistance, 7, function(v)
	State.camDistance = v
	if State.cameraUnlock then player.CameraMaxZoomDistance = v end
	saveSettings()
end, "camDistance")

createSectionHeader(page1, "Presets", -2)

do
	local presetRow = create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = -1,
		Parent = page1,
	})
	local presets = {
		{ name = "Default", ws = 16, jp = 50, grav = 196 },
		{ name = "Fast",    ws = 80, jp = 100, grav = 196 },
		{ name = "Parkour", ws = 50, jp = 150, grav = 80 },
		{ name = "Low-G",   ws = 16, jp = 50, grav = 30 },
	}
	local count = #presets
	local gap = 6
	for idx, p in ipairs(presets) do
		local btn = create("TextButton", {
			Text = p.name,
			Size = UDim2.new(1 / count, -(gap * (count - 1) / count), 1, 0),
			Position = UDim2.new((idx - 1) / count, (idx - 1) * gap / count, 0, 0),
			BackgroundColor3 = C.surface,
			TextColor3 = C.textSecondary,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Parent = presetRow,
		})
		addCorner(btn, 4)
		addStroke(btn, C.panelStroke, 1, 0.5)
		btn.MouseEnter:Connect(function() btn.BackgroundColor3 = C.surfaceHover end)
		btn.MouseLeave:Connect(function() btn.BackgroundColor3 = C.surface end)
		btn.MouseButton1Click:Connect(function()
			State.walkSpeed = p.ws; State.jumpPower = p.jp; State.gravity = p.grav
			local ch = player.Character
			if ch then
				local hum = ch:FindFirstChildOfClass("Humanoid")
				if hum then hum.WalkSpeed = p.ws; hum.UseJumpPower = true; hum.JumpPower = p.jp end
			end
			Workspace.Gravity = p.grav
			if _sliders.walkSpeed then _sliders.walkSpeed.update(p.ws) end
			if _sliders.jumpPower then _sliders.jumpPower.update(p.jp) end
			if _sliders.gravity then _sliders.gravity.update(p.grav) end
			saveSettings()
			btn.BackgroundColor3 = C.accent
			task.delay(0.3, function() if btn.Parent then btn.BackgroundColor3 = C.surface end end)
		end)
	end
end

createSectionHeader(page1, "Toggles", 10)

-- Remove Lighting
local origLP, origEfx = nil, nil

local function stripLight()
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("PostEffect") then c.Enabled = false
		elseif c:IsA("Atmosphere") then c.Density = 0; c.Glare = 0; c.Haze = 0 end
	end
	local cam = Workspace.CurrentCamera
	if cam then for _, c in ipairs(cam:GetChildren()) do
		if c:IsA("PostEffect") then c.Enabled = false end
	end end
	Lighting.GlobalShadows = false; Lighting.FogEnd = 1e9; Lighting.Brightness = 2
end

local function saveLightOrig()
	if origLP then return end
	origLP = { GS = Lighting.GlobalShadows, FE = Lighting.FogEnd, BR = Lighting.Brightness }
	origEfx = {}
	for _, c in ipairs(Lighting:GetChildren()) do
		if c:IsA("PostEffect") then table.insert(origEfx, { i = c, e = c.Enabled })
		elseif c:IsA("Atmosphere") then table.insert(origEfx, { i = c, a = true, D = c.Density, G = c.Glare, H = c.Haze }) end
	end
	local cam = Workspace.CurrentCamera
	if cam then for _, c in ipairs(cam:GetChildren()) do
		if c:IsA("PostEffect") then table.insert(origEfx, { i = c, e = c.Enabled, cam = true }) end
	end end
end

local function restoreLight()
	if not origLP then return end
	for _, d in ipairs(origEfx) do
		if d.cam then if d.i and d.i.Parent then d.i.Enabled = d.e end
		elseif d.a then d.i.Density = d.D; d.i.Glare = d.G; d.i.Haze = d.H
		else d.i.Enabled = d.e end
	end
	Lighting.GlobalShadows = origLP.GS; Lighting.FogEnd = origLP.FE; Lighting.Brightness = origLP.BR
	origLP = nil; origEfx = nil
end

createToggle(page1, "Remove Lighting", 11, function(on)
	State.removeLighting = on
	if on then saveLightOrig(); stripLight() else restoreLight() end
end)

-- Freeze
local freezeConn = nil
local function setAnchored(a)
	local ch = player.Character; if not ch then return end
	for _, p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = a end end
end

createToggle(page1, "Freeze Player", 12, function(on)
	State.freezePlayer = on
	if on then
		setAnchored(true)
		if freezeConn then freezeConn:Disconnect() end
		freezeConn = RunService.Heartbeat:Connect(function() if State.freezePlayer then setAnchored(true) end end)
	else
		if freezeConn then freezeConn:Disconnect(); freezeConn = nil end
		setAnchored(false)
	end
end)

-- Infinite Jump
local ijConn = nil
createToggle(page1, "Infinite Jump", 13, function(on)
	State.infJump = on
	if on then
		if ijConn then ijConn:Disconnect() end
		ijConn = UserInputService.JumpRequest:Connect(function()
			if not State.infJump then return end
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
		end)
	else if ijConn then ijConn:Disconnect(); ijConn = nil end end
end)

-- Noclip
local ncConn = nil
createToggle(page1, "Noclip", 14, function(on)
	State.noclip = on
	if on then
		if ncConn then ncConn:Disconnect() end
		ncConn = RunService.Stepped:Connect(function()
			if not State.noclip then return end
			local ch = player.Character; if not ch then return end
			for _, p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end
		end)
	else
		if ncConn then ncConn:Disconnect(); ncConn = nil end
		local ch = player.Character
		if ch then for _, p in ipairs(ch:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = true end end end
	end
end)

-- Fly
local flyConn, flyBV, flyBG = nil, nil, nil
local function startFly()
	local ch = player.Character; if not ch then return end
	local hrp = ch:FindFirstChild("HumanoidRootPart")
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	if flyBV then flyBV:Destroy() end
	if flyBG then flyBG:Destroy() end
	flyBV = create("BodyVelocity", { Velocity = Vector3.zero, MaxForce = Vector3.new(1e6,1e6,1e6), Parent = hrp })
	flyBG = create("BodyGyro", { MaxTorque = Vector3.new(1e6,1e6,1e6), D = 200, P = 10000, Parent = hrp })
	hum.PlatformStand = true
	if flyConn then flyConn:Disconnect() end
	flyConn = RunService.Heartbeat:Connect(function()
		if not State.fly then return end
		local cam = Workspace.CurrentCamera; if not cam or not hrp.Parent then return end
		local d = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then d = d + cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then d = d - cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then d = d - cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then d = d + cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then d = d + Vector3.yAxis end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then d = d - Vector3.yAxis end
		local flySpeed = State.separateFlySpeed and State.flySpeed or (math.max(State.walkSpeed, 16) * 2.5)
		flyBV.Velocity = d.Magnitude > 0 and d.Unit * flySpeed or Vector3.zero
		flyBG.CFrame = cam.CFrame
	end)
end
local function stopFly()
	if flyConn then flyConn:Disconnect(); flyConn = nil end
	if flyBV then flyBV:Destroy(); flyBV = nil end
	if flyBG then flyBG:Destroy(); flyBG = nil end
	local ch = player.Character
	if ch then local h = ch:FindFirstChildOfClass("Humanoid"); if h then h.PlatformStand = false end end
end

local flyToggle = createToggle(page1, "Fly  (G)  WASD+Space/Ctrl", 15, function(on)
	State.fly = on
	if on then startFly() else stopFly() end
	showToast(on and "Fly enabled" or "Fly disabled")
end)

-- Fly Speed sub-row: visible only when "Separate Fly Speed" is enabled in Settings
local flySpeedWrapper = create("Frame", {
	Size = UDim2.new(1, 0, 0, 52),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	LayoutOrder = 16,
	Visible = false,
	Parent = page1,
})
createSlider(flySpeedWrapper, "Fly Speed", 1, 500, State.flySpeed, 0, function(v)
	State.flySpeed = v
	saveSettings()
end, "flySpeed")

-- ESP
local ESP_TAG = "StatsGUI_ESP"
local espConns = {}
local function addESP(t)
	if t == player then return end
	local ch = t.Character; if not ch or ch:FindFirstChild(ESP_TAG) then return end
	create("Highlight", { Name = ESP_TAG, FillColor = C.accent, FillTransparency = 0.7,
		OutlineColor = Color3.new(1,1,1), OutlineTransparency = 0.3, Adornee = ch, Parent = ch })
	local head = ch:FindFirstChild("Head")
	if head then
		local bb = create("BillboardGui", { Name = ESP_TAG.."_N", Adornee = head,
			Size = UDim2.new(0,120,0,24), StudsOffset = Vector3.new(0,2.5,0), AlwaysOnTop = true, Parent = ch })
		create("TextLabel", { Text = t.DisplayName or t.Name, Size = UDim2.new(1,0,1,0),
			BackgroundTransparency = 1, TextColor3 = Color3.new(1,1,1),
			TextStrokeTransparency = 0.4, TextStrokeColor3 = Color3.new(0,0,0),
			Font = Enum.Font.SourceSansBold, TextSize = 14, Parent = bb })
	end
end
local function removeESP(t)
	local ch = t.Character; if not ch then return end
	local h = ch:FindFirstChild(ESP_TAG); if h then h:Destroy() end
	local n = ch:FindFirstChild(ESP_TAG.."_N"); if n then n:Destroy() end
end
local function enableESP()
	for _, p in ipairs(Players:GetPlayers()) do
		addESP(p)
		table.insert(espConns, p.CharacterAdded:Connect(function() task.wait(0.5); if State.esp then addESP(p) end end))
	end
	table.insert(espConns, Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function() task.wait(0.5); if State.esp then addESP(p) end end)
		if p.Character then addESP(p) end
	end))
end
local function disableESP()
	for _, c in ipairs(espConns) do c:Disconnect() end; espConns = {}
	for _, p in ipairs(Players:GetPlayers()) do removeESP(p) end
end

createToggle(page1, "ESP (Highlight Players)", 17, function(on)
	State.esp = on; if on then enableESP() else disableESP() end
end)

-- FE Invisible — teleport-under-map method
-- Every Heartbeat before render: moves HumanoidRootPart to Y=-200000
-- (server and other players see you there = you are invisible), then before
-- the next RenderStepped it moves back — you see yourself normally.
-- CameraOffset is adjusted so the camera does not jump.
local invisConn = nil

-- Apply/remove semi-transparent visual effect for the local player
local function setInvisVisual(on)
	local ch = player.Character; if not ch then return end
	for _, p in ipairs(ch:GetDescendants()) do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = on and 0.75 or 0
		end
	end
end

local invisToggle = createToggle(page1, "Invisible  (I)", 18, function(on)
	State.invisible = on
	setInvisVisual(on)
	if on then
		if invisConn then invisConn:Disconnect() end
		invisConn = RunService.Heartbeat:Connect(function()
			if not State.invisible then return end
			local ch = player.Character; if not ch then return end
			local hrp = ch:FindFirstChild("HumanoidRootPart")
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if not hrp or not hum then return end

			local savedCFrame = hrp.CFrame
			local savedCamOffset = hum.CameraOffset

			local underCFrame = savedCFrame * CFrame.new(0, -State.invisYOffset, 0)
			local camOff = underCFrame:ToObjectSpace(CFrame.new(savedCFrame.Position)).Position
			hrp.CFrame = underCFrame
			hum.CameraOffset = camOff

			RunService.RenderStepped:Wait()
			if hrp and hrp.Parent then
				hrp.CFrame = savedCFrame
				hum.CameraOffset = savedCamOffset
			end
		end)
	else
		if invisConn then invisConn:Disconnect(); invisConn = nil end
	end
end)

createSlider(page1, "Invis Y Offset", 100, 500000, State.invisYOffset, 181, function(v)
	State.invisYOffset = v
	saveSettings()
end, "invisYOffset")

-- FreeCam
local freecamConn    = nil
local freecamScrollConn = nil
local freecamOldSubject = nil
local freecamOldType    = nil
local freecamSpeed   = 1.5
local freecamAngX, freecamAngY = 0, 0
local freecamRMBHeld = false
local freecamRMBDownConn = nil
local freecamRMBUpConn   = nil

local function startFreecam()
	local cam = Workspace.CurrentCamera; if not cam then return end
	freecamOldSubject = cam.CameraSubject
	freecamOldType    = cam.CameraType
	cam.CameraType    = Enum.CameraType.Scriptable

	local lv = cam.CFrame.LookVector
	freecamAngY = math.atan2(-lv.X, -lv.Z)
	freecamAngX = math.asin(math.clamp(lv.Y, -1, 1))
	freecamRMBHeld = false

	local ch = player.Character
	if ch then
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 0; hum.JumpPower = 0 end
	end

	freecamRMBDownConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			freecamRMBHeld = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	end)
	freecamRMBUpConn = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			freecamRMBHeld = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		end
	end)

	freecamScrollConn = UserInputService.InputChanged:Connect(function(input)
		if not State.freecam then return end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			freecamSpeed = math.clamp(freecamSpeed + input.Position.Z * 0.25, 0.1, 30)
		end
	end)

	freecamConn = RunService.RenderStepped:Connect(function(dt)
		if not State.freecam then return end
		local cam2 = Workspace.CurrentCamera; if not cam2 then return end

		if freecamRMBHeld then
			local delta = UserInputService:GetMouseDelta()
			freecamAngY = freecamAngY - delta.X * 0.003
			freecamAngX = math.clamp(freecamAngX - delta.Y * 0.003, -math.pi/2 + 0.01, math.pi/2 - 0.01)
		end

		local rot = CFrame.Angles(0, freecamAngY, 0) * CFrame.Angles(freecamAngX, 0, 0)
		local pos = cam2.CFrame.Position

		local move = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + rot.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - rot.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - rot.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + rot.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space)        then move = move + Vector3.yAxis end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)  then move = move - Vector3.yAxis end
		local mult = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) and 3 or 1
		if move.Magnitude > 0 then
			pos = pos + move.Unit * (freecamSpeed * 60 * mult * dt)
		end

		cam2.CFrame = CFrame.new(pos) * rot

		local ch = player.Character
		if ch then
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if hum then hum.WalkSpeed = 0; hum.JumpPower = 0 end
		end
	end)
end

local function stopFreecam()
	if freecamConn        then freecamConn:Disconnect();         freecamConn        = nil end
	if freecamScrollConn  then freecamScrollConn:Disconnect();   freecamScrollConn  = nil end
	if freecamRMBDownConn then freecamRMBDownConn:Disconnect();  freecamRMBDownConn = nil end
	if freecamRMBUpConn   then freecamRMBUpConn:Disconnect();    freecamRMBUpConn   = nil end
	freecamRMBHeld = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = freecamOldType or Enum.CameraType.Custom
		if freecamOldSubject then cam.CameraSubject = freecamOldSubject end
	end
	freecamOldSubject = nil; freecamOldType = nil
	local ch = player.Character
	if ch then
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = State.walkSpeed; hum.UseJumpPower = true; hum.JumpPower = State.jumpPower
			-- Always restore camera to own player on freecam exit.
			-- Fixes: spectate P → enable freecam → unwatch → disable freecam → cam stuck on P
			-- (spectate heartbeat loop will immediately re-apply if spectate is still active)
			if cam then cam.CameraSubject = hum end
		end
	end
end

local freecamToggle = createToggle(page1, "FreeCam  (F)", 19, function(on)
	State.freecam = on; if on then startFreecam() else stopFreecam() end
end)

createSectionHeader(page1, "Utility", 20)

-- Anti-AFK
local afkConn = nil
createToggle(page1, "Anti-AFK", 21, function(on)
	State.antiAfk = on
	if on then
		local VU = game:GetService("VirtualUser")
		if afkConn then afkConn:Disconnect() end
		afkConn = player.Idled:Connect(function()
			VU:CaptureController()
			VU:ClickButton2(Vector2.zero)
		end)
		showToast("Anti-AFK enabled")
	else
		if afkConn then afkConn:Disconnect(); afkConn = nil end
		showToast("Anti-AFK disabled")
	end
end)

-- Hitbox Expander
local hbConn = nil
local HB_TAG = "StatsGUI_HB"

local function expandHitboxes(size)
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local ch = p.Character
			if ch then
				local hrp = ch:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.Size = Vector3.new(size, size, size)
					hrp.Transparency = 0.7
					hrp.CanCollide = false
				end
			end
		end
	end
end

local function resetHitboxes()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then
			local ch = p.Character
			if ch then
				local hrp = ch:FindFirstChild("HumanoidRootPart")
				if hrp then
					hrp.Size = Vector3.new(2, 2, 1)
					hrp.Transparency = 1
				end
			end
		end
	end
end

createToggle(page1, "Hitbox Expander", 22, function(on)
	State.hitboxExpander = on
	if on then
		expandHitboxes(State.hitboxSize)
		if hbConn then hbConn:Disconnect() end
		hbConn = RunService.Heartbeat:Connect(function()
			if not State.hitboxExpander then return end
			expandHitboxes(State.hitboxSize)
		end)
		showToast("Hitbox Expander ON (" .. State.hitboxSize .. ")")
	else
		if hbConn then hbConn:Disconnect(); hbConn = nil end
		resetHitboxes()
		showToast("Hitbox Expander OFF")
	end
end)

createSlider(page1, "Hitbox Size", 2, 50, State.hitboxSize, 23, function(v)
	State.hitboxSize = v
	if State.hitboxExpander then expandHitboxes(v) end
	saveSettings()
end, "hitboxSize")

════════════════
--                 PAGE 2: SUBPLACES
════════════════

local statusLabel = create("TextLabel", {
	Text = "Loading places...",
	Size = UDim2.new(1, 0, 0, 28),
	BackgroundTransparency = 1,
	TextColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = page2,
})

local placeList = create("ScrollingFrame", {
	Name = "PlaceList",
	Size = UDim2.new(1, 0, 1, -118),
	Position = UDim2.new(0, 0, 0, 30),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = C.accent,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ClipsDescendants = true,
	Parent = page2,
})
create("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
	Parent = placeList,
})

local teleportBtn = create("TextButton", {
	Text = "Teleport",
	Size = UDim2.new(1, 0, 0, 32),
	Position = UDim2.new(0, 0, 1, -72),
	BackgroundColor3 = C.disabled,
	TextColor3 = C.disabledText,
	Font = Enum.Font.SourceSansSemibold,
	TextSize = 18,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Active = false,
	Parent = page2,
})
addCorner(teleportBtn, 6)

local selectedPlaceId = nil
local placeButtons = {}

local function updateTPBtn()
	if selectedPlaceId and selectedPlaceId ~= currentPlaceId then
		teleportBtn.BackgroundColor3 = C.accent
		teleportBtn.TextColor3 = C.textPrimary
		teleportBtn.Active = true
		teleportBtn.Text = "Teleport"
	else
		teleportBtn.BackgroundColor3 = C.disabled
		teleportBtn.TextColor3 = C.disabledText
		teleportBtn.Active = false
		teleportBtn.Text = "Teleport"
	end
end

local function selectPlace(id)
	if id == currentPlaceId then return end
	selectedPlaceId = id
	for _, d in ipairs(placeButtons) do
		if d.id == currentPlaceId then
			d.btn.BackgroundColor3 = C.currentPlace
		elseif d.id == selectedPlaceId then
			d.btn.BackgroundColor3 = C.selected
		else
			d.btn.BackgroundColor3 = C.surface
		end
	end
	updateTPBtn()
end

local function addPlaceBtn(name, placeId, order)
	local isCur = (placeId == currentPlaceId)
	local btn = create("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = isCur and C.currentPlace or C.surface,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		LayoutOrder = order,
		Parent = placeList,
	})
	addCorner(btn, 6)

	create("TextLabel", {
		Text = name,
		Size = UDim2.new(0.95, 0, 0.45, 0),
		Position = UDim2.new(0.025, 0, 0.05, 0),
		BackgroundTransparency = 1,
		TextColor3 = isCur and C.textPrimary or C.textSecondary,
		Font = Enum.Font.SourceSans,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = btn,
	})

	create("TextLabel", {
		Text = tostring(placeId) .. (isCur and "  (current)" or ""),
		Size = UDim2.new(0.95, 0, 0.35, 0),
		Position = UDim2.new(0.025, 0, 0.55, 0),
		BackgroundTransparency = 1,
		TextColor3 = isCur and C.accent or C.textDim,
		Font = Enum.Font.SourceSans,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})

	btn.MouseEnter:Connect(function()
		if placeId ~= currentPlaceId and placeId ~= selectedPlaceId then
			btn.BackgroundColor3 = C.surfaceHover
		end
	end)
	btn.MouseLeave:Connect(function()
		if placeId == currentPlaceId then btn.BackgroundColor3 = C.currentPlace
		elseif placeId == selectedPlaceId then btn.BackgroundColor3 = C.selected
		else btn.BackgroundColor3 = C.surface end
	end)
	btn.MouseButton1Click:Connect(function() selectPlace(placeId) end)

	table.insert(placeButtons, { btn = btn, id = placeId })
end

teleportBtn.MouseButton1Click:Connect(function()
	if not selectedPlaceId or selectedPlaceId == currentPlaceId then return end
	teleportBtn.Text = "Teleporting..."
	teleportBtn.BackgroundColor3 = C.accentDark
	local ok, err = pcall(function()
		TeleportService:Teleport(selectedPlaceId, player)
	end)
	if not ok then
		teleportBtn.Text = "Error! Retry"
		teleportBtn.BackgroundColor3 = C.closeHover
		task.delay(2, function() updateTPBtn() end)
	end
end)
teleportBtn.MouseEnter:Connect(function()
	if teleportBtn.Active then teleportBtn.BackgroundColor3 = C.accentHover end
end)
teleportBtn.MouseLeave:Connect(function() updateTPBtn() end)

-- Server Hop button
local serverHopBtn = create("TextButton", {
	Text = "\u{1F310} Server Hop",
	Size = UDim2.new(1, 0, 0, 32),
	Position = UDim2.new(0, 0, 1, -36),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textPrimary,
	Font = Enum.Font.SourceSansSemibold,
	TextSize = 17,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Parent = page2,
})
addCorner(serverHopBtn, 6)
addStroke(serverHopBtn, C.panelStroke, 1, 0.4)
serverHopBtn.MouseEnter:Connect(function() serverHopBtn.BackgroundColor3 = C.surfaceHover end)
serverHopBtn.MouseLeave:Connect(function() serverHopBtn.BackgroundColor3 = C.surface end)
serverHopBtn.MouseButton1Click:Connect(function()
	serverHopBtn.Text = "Finding server..."
	serverHopBtn.BackgroundColor3 = C.accentDark
	task.spawn(function()
		local jobId = game.JobId
		local url = "https://games.roblox.com/v1/games/" .. currentPlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
		local raw
		local ok = false
		for _, fn in ipairs({
			function() return game:HttpGet(url) end,
			function() return HttpService:GetAsync(url, true) end,
		}) do
			local s, r = pcall(fn)
			if s and type(r) == "string" and #r > 5 then raw = r; ok = true; break end
		end
		if not ok then
			local reqFns = {}
			local seen = {}
			local function addFn(f) if type(f) == "function" and not seen[f] then seen[f]=true; table.insert(reqFns, f) end end
			pcall(function() addFn(syn and syn.request) end)
			pcall(function() addFn(request) end)
			pcall(function() addFn(http_request) end)
			pcall(function() addFn(fluxus_request) end)
			pcall(function() if type(http) == "table" then addFn(http.request) end end)
			for _, fn in ipairs(reqFns) do
				local s, r = pcall(fn, { Url = url, Method = "GET" })
				if s and r then
					local body = r.Body or r.body or ""
					if type(body) == "string" and #body > 5 then raw = body; ok = true; break end
				end
			end
		end
		if ok and raw then
			local s, data = pcall(function() return HttpService:JSONDecode(raw) end)
			if s and data and data.data then
				for _, srv in ipairs(data.data) do
					if srv.id ~= jobId and srv.playing and srv.maxPlayers and srv.playing < srv.maxPlayers then
						showToast("Hopping to another server...")
						TeleportService:TeleportToPlaceInstance(currentPlaceId, srv.id, player)
						return
					end
				end
			end
		end
		serverHopBtn.Text = "No server found"
		serverHopBtn.BackgroundColor3 = C.closeHover
		showToast("No other server found", 2, C.closeHover)
		task.delay(2, function()
			if serverHopBtn.Parent then
				serverHopBtn.Text = "\u{1F310} Server Hop"
				serverHopBtn.BackgroundColor3 = C.surface
			end
		end)
	end)
end)

task.spawn(function()
	local places = {}

	if universeId == 0 then
		statusLabel.Text = "Error: GameId = 0"
		statusLabel.TextColor3 = Color3.fromRGB(220, 100, 50)
		addPlaceBtn("Current Place", currentPlaceId, 1)
		return
	end

	local function fetchPage(cursor)
		local url = "https://develop.roblox.com/v1/universes/" .. universeId
			.. "/places?isUniverseCreation=false&limit=100&sortOrder=Asc"
		if cursor and cursor ~= "" then
			url = url .. "&cursor=" .. cursor
		end
		local raw
		local ok = false
		for _, fn in ipairs({
			function() return game:HttpGet(url) end,
			function() return HttpService:GetAsync(url, true) end,
		}) do
			local s, r = pcall(fn)
			if s and type(r) == "string" and #r > 5 then
				raw = r; ok = true; break
			end
		end
		if not ok then
			local reqFns = {}
			local seen = {}
			local function addFn(f) if type(f) == "function" and not seen[f] then seen[f]=true; table.insert(reqFns, f) end end
			pcall(function() addFn(syn and syn.request) end)
			pcall(function() addFn(request) end)
			pcall(function() addFn(http_request) end)
			pcall(function() addFn(fluxus_request) end)
			pcall(function() if type(http) == "table" then addFn(http.request) end end)
			for _, fn in ipairs(reqFns) do
				local s, r = pcall(fn, { Url = url, Method = "GET" })
				if s and r then
					local body = r.Body or r.body or ""
					if type(body) == "string" and #body > 5 then
						raw = body; ok = true; break
					end
				end
			end
		end
		if not ok or not raw then return nil, nil end
		local s, data = pcall(function() return HttpService:JSONDecode(raw) end)
		if not s or not data then return nil, nil end
		return data.data, data.nextPageCursor
	end

	local cursor = nil
	local errored = false
	repeat
		local pageData, nextCursor = fetchPage(cursor)
		if not pageData then errored = true; break end
		for _, p in ipairs(pageData) do
			table.insert(places, { name = p.name or "Unknown", id = p.id })
		end
		cursor = (nextCursor ~= nil and nextCursor ~= "") and nextCursor or nil
	until cursor == nil

	if errored or #places == 0 then
		local pName = "Current Place"
		pcall(function()
			local info = game:GetService("MarketplaceService"):GetProductInfo(currentPlaceId)
			if info and info.Name then pName = info.Name end
		end)
		places = {{ name = pName, id = currentPlaceId }}
		statusLabel.Text = "Could not load places"
		statusLabel.TextColor3 = Color3.fromRGB(220, 120, 50)
	else
		statusLabel.Text = #places .. " place(s) found"
		statusLabel.TextColor3 = C.textDim
	end

	for i, p in ipairs(places) do
		addPlaceBtn(p.name, p.id, i)
	end
end)

════════════════
--                 PAGE 3: TELEPORT
════════════════

local RSS_FOLDER  = "RSS"
local WP_FILE     = RSS_FOLDER .. "/wp.json"
local placeKey    = tostring(currentPlaceId)

local function ensureRSSFolder()
	pcall(function()
		if not isfolder(RSS_FOLDER) then makefolder(RSS_FOLDER) end
	end)
end

local function readWPFile()
	local ok, all = pcall(function()
		if isfile(WP_FILE) then
			return HttpService:JSONDecode(readfile(WP_FILE))
		end
		return {}
	end)
	return (ok and type(all) == "table") and all or {}
end

local function loadWaypoints()
	ensureRSSFolder()
	local all = readWPFile()
	local list = all[placeKey]
	return (type(list) == "table") and list or {}
end

local function encodeWPPretty(all)
	local function esc(s)
		return HttpService:JSONEncode(tostring(s))
	end
	local placeKeys = {}
	for k in pairs(all) do table.insert(placeKeys, k) end
	table.sort(placeKeys)

	local out = {"{\n"}
	for pi, pk in ipairs(placeKeys) do
		local wps = all[pk]
		local placeComma = pi < #placeKeys and "," or ""
		table.insert(out, '    ' .. esc(pk) .. ': [\n')
		for wi, wp in ipairs(wps) do
			local wpComma = wi < #wps and "," or ""
			table.insert(out, string.format(
				'        { "Name": %s, "X": %s, "Y": %s, "Z": %s }%s\n',
				esc(wp.Name), esc(wp.X), esc(wp.Y), esc(wp.Z), wpComma
			))
		end
		table.insert(out, '    ]' .. placeComma .. '\n')
	end
	table.insert(out, "}")
	return table.concat(out)
end

local function saveWaypointsToDisk(list)
	ensureRSSFolder()
	pcall(function()
		local all = readWPFile()
		all[placeKey] = list
		writefile(WP_FILE, encodeWPPretty(all))
	end)
end

local spectateTarget = nil

-- Coordinates header
create("TextLabel", {
	Text = "Coordinates",
	Size = UDim2.new(1, 0, 0, 28),
	BackgroundTransparency = 1,
	TextColor3 = C.accent,
	Font = Enum.Font.SourceSansSemibold,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = page3,
})

-- XYZ input row
local coordRow = create("Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 0, 30),
	BackgroundTransparency = 1,
	Parent = page3,
})

local function createCoordBox(label, scaleX)
	local box = create("TextBox", {
		Text = "0",
		PlaceholderText = label,
		Size = UDim2.new(0.3, 0, 1, 0),
		Position = UDim2.new(scaleX, 0, 0, 0),
		BackgroundColor3 = C.surface,
		TextColor3 = C.textPrimary,
		PlaceholderColor3 = C.textDim,
		Font = Enum.Font.SourceSans,
		TextSize = 18,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Parent = coordRow,
	})
	addCorner(box, 4)
	create("UIStroke", { Color = C.border, Thickness = 1, Transparency = 0.4, Parent = box })
	create("TextLabel", {
		Text = label,
		Size = UDim2.new(0, 18, 0, 18),
		Position = UDim2.new(0.05, 0, 0, -9),
		BackgroundColor3 = C.window,
		TextColor3 = C.accent,
		Font = Enum.Font.SourceSansBold,
		TextSize = 13,
		Parent = box,
	})
	return box
end

local xBox = createCoordBox("X", 0)
local yBox = createCoordBox("Y", 0.34)
local zBox = createCoordBox("Z", 0.68)

-- TP History
local tpHistory = {}
local tpBackBtn

local function pushHistory()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local pos = hrp.Position
	table.insert(tpHistory, { X = pos.X, Y = pos.Y, Z = pos.Z })
	if #tpHistory > 5 then table.remove(tpHistory, 1) end
	if tpBackBtn then tpBackBtn.Text = "\u{25C4} " .. #tpHistory end
end

-- Buttons row
local coordBtnRow = create("Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 0, 76),
	BackgroundTransparency = 1,
	Parent = page3,
})

-- Status / distance row
local tpInfoRow = create("Frame", {
	Size = UDim2.new(1, 0, 0, 20),
	Position = UDim2.new(0, 0, 0, 118),
	BackgroundTransparency = 1,
	Parent = page3,
})

local tpStatusLabel = create("TextLabel", {
	Text = "",
	Size = UDim2.new(0.6, 0, 1, 0),
	BackgroundTransparency = 1,
	TextColor3 = C.errorText,
	Font = Enum.Font.SourceSans,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = tpInfoRow,
})

local tpDistLabel = create("TextLabel", {
	Text = "",
	Size = UDim2.new(0.38, 0, 1, 0),
	Position = UDim2.new(0, 0, 0, 0),
	BackgroundTransparency = 1,
	TextColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = tpInfoRow,
})

local copyXYZBtn = create("TextButton", {
	Text = "Copy XYZ",
	Size = UDim2.new(0, 64, 0, 20),
	Position = UDim2.new(1, -64, 0, 0),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textSecondary,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Parent = tpInfoRow,
})
addCorner(copyXYZBtn, 4)
addStroke(copyXYZBtn, C.border, 1, 0.4)
copyXYZBtn.MouseEnter:Connect(function() copyXYZBtn.BackgroundColor3 = C.surfaceHover end)
copyXYZBtn.MouseLeave:Connect(function() copyXYZBtn.BackgroundColor3 = C.surface end)

local getPosBtn = create("TextButton", {
	Text = "Get Position",
	Size = UDim2.new(0.35, 0, 1, 0),
	Position = UDim2.fromScale(0, 0),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textPrimary,
	Font = Enum.Font.SourceSans,
	TextSize = 17,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Parent = coordBtnRow,
})
addCorner(getPosBtn, 6)
create("UIStroke", { Color = C.border, Thickness = 1, Transparency = 0.4, Parent = getPosBtn })

tpBackBtn = create("TextButton", {
	Text = "\u{25C4} 0",
	Size = UDim2.new(0.13, 0, 1, 0),
	Position = UDim2.fromScale(0.37, 0),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 17,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Parent = coordBtnRow,
})
addCorner(tpBackBtn, 6)
create("UIStroke", { Color = C.border, Thickness = 1, Transparency = 0.4, Parent = tpBackBtn })

local tpGoBtn = create("TextButton", {
	Text = "Teleport",
	Size = UDim2.new(0.46, 0, 1, 0),
	Position = UDim2.fromScale(0.52, 0),
	BackgroundColor3 = C.accent,
	TextColor3 = C.textPrimary,
	Font = Enum.Font.SourceSansSemibold,
	TextSize = 17,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Parent = coordBtnRow,
})
addCorner(tpGoBtn, 6)

getPosBtn.MouseEnter:Connect(function() getPosBtn.BackgroundColor3 = C.surfaceHover end)
getPosBtn.MouseLeave:Connect(function() getPosBtn.BackgroundColor3 = C.surface end)
tpBackBtn.MouseEnter:Connect(function() if #tpHistory > 0 then tpBackBtn.BackgroundColor3 = C.surfaceHover end end)
tpBackBtn.MouseLeave:Connect(function() tpBackBtn.BackgroundColor3 = C.surface end)
tpGoBtn.MouseEnter:Connect(function() tpGoBtn.BackgroundColor3 = C.accentHover end)
tpGoBtn.MouseLeave:Connect(function() tpGoBtn.BackgroundColor3 = C.accent end)

tpBackBtn.MouseButton1Click:Connect(function()
	if #tpHistory == 0 then return end
	local last = table.remove(tpHistory)
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = CFrame.new(last.X, last.Y, last.Z) end
	tpBackBtn.Text = "\u{25C4} " .. #tpHistory
end)

getPosBtn.MouseButton1Click:Connect(function()
	local hrp
	if spectateTarget then
		local ch = spectateTarget.Character
		hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	else
		local ch = player.Character
		hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	end
	if hrp then
		local pos = hrp.Position
		xBox.Text = tostring(math.floor(pos.X * 100) / 100)
		yBox.Text = tostring(math.floor(pos.Y * 100) / 100)
		zBox.Text = tostring(math.floor(pos.Z * 100) / 100)
	end
end)

-- Bug #5: show error when coords are invalid instead of silently failing
tpGoBtn.MouseButton1Click:Connect(function()
	local x = tonumber(xBox.Text)
	local y = tonumber(yBox.Text)
	local z = tonumber(zBox.Text)
	if not x or not y or not z then
		tpStatusLabel.Text = "Invalid coordinates!"
		tpStatusLabel.TextColor3 = C.errorText
		task.delay(2, function()
			if tpStatusLabel.Parent then tpStatusLabel.Text = "" end
		end)
		return
	end
	tpStatusLabel.Text = ""
	pushHistory()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = CFrame.new(x, y, z) end
end)

-- Copy XYZ to clipboard
copyXYZBtn.MouseButton1Click:Connect(function()
	local txt = (xBox.Text or "0") .. ", " .. (yBox.Text or "0") .. ", " .. (zBox.Text or "0")
	local ok = setClipboard(txt)
	copyXYZBtn.Text = ok and "Copied!" or "Failed"
	task.delay(1, function() if copyXYZBtn.Parent then copyXYZBtn.Text = "Copy XYZ" end end)
end)

-- Live distance preview with directional arrow
task.spawn(function()
	local arrs = {"\u{2191}","\u{2197}","\u{2192}","\u{2198}","\u{2193}","\u{2199}","\u{2190}","\u{2196}"}
	while screenGui and screenGui.Parent do
		local x = tonumber(xBox.Text)
		local y = tonumber(yBox.Text)
		local z = tonumber(zBox.Text)
		if x and y and z then
			local cam = Workspace.CurrentCamera
			-- In freecam, measure from camera position; otherwise from HRP
			local originPos
			if State.freecam and cam then
				originPos = cam.CFrame.Position
			else
				local ch = player.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				originPos = hrp and hrp.Position
			end
			if originPos then
				local targetPos = Vector3.new(x, y, z)
				local dist = (originPos - targetPos).Magnitude
				local arrow = ""
				if cam and dist > 2 then
					local fwd = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
					local rgt = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
					if fwd.Magnitude > 0.01 then
						fwd = fwd.Unit
						if rgt.Magnitude > 0.01 then rgt = rgt.Unit end
						local dir = Vector3.new(targetPos.X - originPos.X, 0, targetPos.Z - originPos.Z)
						if dir.Magnitude > 0.1 then
							dir = dir.Unit
							local deg = math.deg(math.atan2(dir:Dot(rgt), dir:Dot(fwd)))
							local idx = math.floor((deg + 22.5) / 45) % 8
							arrow = arrs[idx + 1] .. " "
						end
					end
				end
				tpDistLabel.Text = arrow .. math.floor(dist) .. " studs away"
			else
				tpDistLabel.Text = ""
			end
		else
			tpDistLabel.Text = ""
		end
		task.wait(0.15)
	end
end)

-- Waypoints header
local WP_SECTION_Y = 140

create("TextLabel", {
	Text = "Waypoints",
	Size = UDim2.new(1, 0, 0, 28),
	Position = UDim2.new(0, 0, 0, WP_SECTION_Y),
	BackgroundTransparency = 1,
	TextColor3 = C.accent,
	Font = Enum.Font.SourceSansSemibold,
	TextSize = 17,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = page3,
})

-- Save row
local saveRow = create("Frame", {
	Size = UDim2.new(1, 0, 0, 40),
	Position = UDim2.new(0, 0, 0, WP_SECTION_Y + 30),
	BackgroundTransparency = 1,
	Parent = page3,
})

local wpNameBox = create("TextBox", {
	Text = "",
	PlaceholderText = "Waypoint name...",
	Size = UDim2.new(0.56, 0, 1, 0),
	Position = UDim2.fromScale(0, 0),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textPrimary,
	PlaceholderColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 17,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	Parent = saveRow,
})
addCorner(wpNameBox, 4)
create("UIStroke", { Color = C.border, Thickness = 1, Transparency = 0.4, Parent = wpNameBox })

local wpQuickBtn = create("TextButton", {
	Text = "Quick",
	Size = UDim2.new(0.2, 0, 1, 0),
	Position = UDim2.fromScale(0.58, 0),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textSecondary,
	Font = Enum.Font.SourceSansSemibold,
	TextSize = 16,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Parent = saveRow,
})
addCorner(wpQuickBtn, 4)
addStroke(wpQuickBtn, C.border, 1, 0.4)
wpQuickBtn.MouseEnter:Connect(function() wpQuickBtn.BackgroundColor3 = C.surfaceHover end)
wpQuickBtn.MouseLeave:Connect(function() wpQuickBtn.BackgroundColor3 = C.surface end)

local wpSaveBtn = create("TextButton", {
	Text = "Save",
	Size = UDim2.new(0.2, 0, 1, 0),
	Position = UDim2.fromScale(0.8, 0),
	BackgroundColor3 = C.accent,
	TextColor3 = C.textPrimary,
	Font = Enum.Font.SourceSansSemibold,
	TextSize = 17,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Parent = saveRow,
})
addCorner(wpSaveBtn, 4)
wpSaveBtn.MouseEnter:Connect(function() wpSaveBtn.BackgroundColor3 = C.accentHover end)
wpSaveBtn.MouseLeave:Connect(function() wpSaveBtn.BackgroundColor3 = C.accent end)

-- Waypoint scrolling list
local WP_LIST_TOP = WP_SECTION_Y + 76
local wpList = create("ScrollingFrame", {
	Name = "WaypointList",
	Size = UDim2.new(1, 0, 1, -WP_LIST_TOP),
	Position = UDim2.new(0, 0, 0, WP_LIST_TOP),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 5,
	ScrollBarImageColor3 = C.accent,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ClipsDescendants = true,
	Parent = page3,
})
create("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
	Parent = wpList,
})

local function refreshWaypoints()
	for _, c in ipairs(wpList:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local wps = loadWaypoints()
	for i, wp in ipairs(wps) do
		local row = create("Frame", {
			Size = UDim2.new(1, 0, 0, 54),
			BackgroundColor3 = C.surface,
			BorderSizePixel = 0,
			LayoutOrder = i,
			Parent = wpList,
		})
		addCorner(row, 4)

		create("TextLabel", {
			Text = wp.Name or ("Point " .. i),
			Size = UDim2.new(0.7, 0, 0.45, 0),
			Position = UDim2.new(0.02, 0, 0.04, 0),
			BackgroundTransparency = 1,
			TextColor3 = C.textPrimary,
			Font = Enum.Font.SourceSans,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = row,
		})

		create("TextLabel", {
			Text = string.format("%.1f, %.1f, %.1f", tonumber(wp.X) or 0, tonumber(wp.Y) or 0, tonumber(wp.Z) or 0),
			Size = UDim2.new(0.7, 0, 0.35, 0),
			Position = UDim2.new(0.02, 0, 0.52, 0),
			BackgroundTransparency = 1,
			TextColor3 = C.textDim,
			Font = Enum.Font.SourceSans,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = row,
		})

		local tpWpBtn = create("TextButton", {
			Text = "TP",
			Size = UDim2.new(0.14, 0, 0, 32),
			Position = UDim2.new(0.74, 0, 0.5, -16),
			BackgroundColor3 = C.accent,
			TextColor3 = C.textPrimary,
			Font = Enum.Font.SourceSansSemibold,
			TextSize = 15,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Parent = row,
		})
		addCorner(tpWpBtn, 4)
		tpWpBtn.MouseEnter:Connect(function() tpWpBtn.BackgroundColor3 = C.accentHover end)
		tpWpBtn.MouseLeave:Connect(function() tpWpBtn.BackgroundColor3 = C.accent end)
		tpWpBtn.MouseButton1Click:Connect(function()
			pushHistory()
			local ch = player.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = CFrame.new(tonumber(wp.X) or 0, tonumber(wp.Y) or 0, tonumber(wp.Z) or 0) end
		end)

		local delWpBtn = create("TextButton", {
			Text = "X",
			Size = UDim2.new(0.09, 0, 0, 32),
			Position = UDim2.new(0.89, 0, 0.5, -16),
			BackgroundColor3 = C.surface,
			TextColor3 = C.closeHover,
			Font = Enum.Font.SourceSansBold,
			TextSize = 17,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Parent = row,
		})
		addCorner(delWpBtn, 4)
		create("UIStroke", { Color = C.border, Thickness = 1, Transparency = 0.4, Parent = delWpBtn })
		delWpBtn.MouseEnter:Connect(function() delWpBtn.BackgroundColor3 = C.closeHover; delWpBtn.TextColor3 = C.textPrimary end)
		delWpBtn.MouseLeave:Connect(function() delWpBtn.BackgroundColor3 = C.surface; delWpBtn.TextColor3 = C.closeHover end)
		delWpBtn.MouseButton1Click:Connect(function()
			local wps2 = loadWaypoints()
			table.remove(wps2, i)
			saveWaypointsToDisk(wps2)
			refreshWaypoints()
		end)
	end
end

wpSaveBtn.MouseButton1Click:Connect(function()
	local name = wpNameBox.Text
	if name == "" then name = "Waypoint" end
	local x = tonumber(xBox.Text) or 0
	local y = tonumber(yBox.Text) or 0
	local z = tonumber(zBox.Text) or 0
	local wps = loadWaypoints()
	table.insert(wps, { Name = name, X = x, Y = y, Z = z })
	saveWaypointsToDisk(wps)
	wpNameBox.Text = ""
	refreshWaypoints()
end)

-- Quick Save: saves current position with auto-generated name
wpQuickBtn.MouseButton1Click:Connect(function()
	local ch = player.Character
	local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local pos = hrp.Position
	local t = os.date("*t")
	local name = string.format("Pos %02d:%02d:%02d", t.hour, t.min, t.sec)
	local wps = loadWaypoints()
	table.insert(wps, { Name = name, X = math.floor(pos.X * 10) / 10, Y = math.floor(pos.Y * 10) / 10, Z = math.floor(pos.Z * 10) / 10 })
	saveWaypointsToDisk(wps)
	refreshWaypoints()
	wpQuickBtn.Text = "Saved!"
	task.delay(1, function() if wpQuickBtn.Parent then wpQuickBtn.Text = "Quick" end end)
end)

refreshWaypoints()

════════════════
--                 PAGE 4: PLAYERS
════════════════

spectateTarget = nil
local spectateConn   = nil
local spectateLoop   = nil

local function applyCamToTarget(target)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local ch = target.Character
	if not ch then return end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	cam.CameraType = Enum.CameraType.Custom
	cam.CameraSubject = hum
end

local function stopSpectate()
	if not spectateTarget then return end
	spectateTarget = nil
	if spectateLoop then spectateLoop:Disconnect(); spectateLoop = nil end
	if spectateConn then spectateConn:Disconnect(); spectateConn = nil end
	local cam = Workspace.CurrentCamera
	if cam then
		cam.CameraType = Enum.CameraType.Custom
		local ch = player.Character
		if ch then
			local hum = ch:FindFirstChildOfClass("Humanoid")
			if hum then cam.CameraSubject = hum end
		end
	end
end

local refreshPlayerList

local function startSpectate(target)
	if target == player then return end
	if spectateTarget == target then
		stopSpectate(); refreshPlayerList(); return
	end
	stopSpectate()
	spectateTarget = target
	applyCamToTarget(target)
	spectateLoop = RunService.Heartbeat:Connect(function()
		if not spectateTarget then return end
		local cam = Workspace.CurrentCamera; if not cam then return end
		local ch = spectateTarget.Character; if not ch then return end
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if hum and cam.CameraSubject ~= hum then
			cam.CameraType = Enum.CameraType.Custom
			cam.CameraSubject = hum
		end
	end)
	spectateConn = target.CharacterAdded:Connect(function()
		task.wait(0.1)
		if spectateTarget == target then applyCamToTarget(target) end
	end)
	refreshPlayerList()
end

-- Search bar for Players tab
local playerSearchBox = create("TextBox", {
	Name = "SearchBar",
	Text = "",
	PlaceholderText = "\u{1F50D} Search players...",
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textPrimary,
	PlaceholderColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 16,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	LayoutOrder = -1,
	Parent = page4,
})
addCorner(playerSearchBox, 6)
addStroke(playerSearchBox, C.border, 1, 0.4)

-- Distance labels updated by heartbeat
local _playerDistLabels = {}

refreshPlayerList = function()
	for _, c in ipairs(page4:GetChildren()) do
		if c:IsA("Frame") and c.Name ~= "SearchBar" then c:Destroy() end
	end
	_playerDistLabels = {}

	local searchText = playerSearchBox.Text:lower()
	local allPlayers = Players:GetPlayers()
	for i, p in ipairs(allPlayers) do
		-- Filter by search
		if searchText ~= "" then
			local dn = p.DisplayName:lower()
			local un = p.Name:lower()
			local uid = tostring(p.UserId)
			if not (dn:find(searchText, 1, true) or un:find(searchText, 1, true) or uid:find(searchText, 1, true)) then
				continue
			end
		end

		local isLocal = (p == player)
		local isSpec = (spectateTarget == p)

		local card = create("Frame", {
			Size = UDim2.new(1, 0, 0, 96),
			BackgroundColor3 = isSpec and C.selected or C.surfaceAlt,
			BorderSizePixel = 0,
			LayoutOrder = isLocal and 0 or i,
			Parent = page4,
		})
		addCorner(card, 6)
		addStroke(card, isSpec and C.accent or C.panelStroke, 1, 0.4)

		-- Avatar
		local avatar = create("ImageLabel", {
			Size = UDim2.new(0, 42, 0, 42),
			Position = UDim2.new(0, 10, 0, 9),
			BackgroundColor3 = C.sliderTrack,
			BorderSizePixel = 0,
			Image = "rbxthumb://type=AvatarHeadShot&id=" .. p.UserId .. "&w=150&h=150",
			Parent = card,
		})
		addCorner(avatar, 20)

		-- Display name
		create("TextLabel", {
			Text = p.DisplayName .. (isLocal and "  (you)" or ""),
			Size = UDim2.new(1, -66, 0, 18),
			Position = UDim2.new(0, 60, 0, 7),
			BackgroundTransparency = 1,
			TextColor3 = C.textPrimary,
			Font = Enum.Font.SourceSansSemibold,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = card,
		})

		-- @username | ID
		create("TextLabel", {
			Text = "@" .. p.Name .. " | " .. p.UserId,
			Size = UDim2.new(1, -66, 0, 14),
			Position = UDim2.new(0, 60, 0, 27),
			BackgroundTransparency = 1,
			TextColor3 = C.textDim,
			Font = Enum.Font.SourceSans,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = card,
		})

		-- Distance + arrow label (for non-local players)
		if not isLocal then
			local distLabel = create("TextLabel", {
				Text = "",
				Size = UDim2.new(1, -66, 0, 13),
				Position = UDim2.new(0, 60, 0, 43),
				BackgroundTransparency = 1,
				TextColor3 = C.textDim,
				Font = Enum.Font.SourceSans,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = card,
			})
			table.insert(_playerDistLabels, { label = distLabel, target = p })
		end

		-- Separator
		create("Frame", {
			Size = UDim2.new(1, -12, 0, 1),
			Position = UDim2.new(0, 6, 0, 64),
			BackgroundColor3 = C.border,
			BorderSizePixel = 0,
			Parent = card,
		})

		-- Bottom buttons row
		local btnRow = create("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.new(0, 0, 0, 68),
			BackgroundTransparency = 1,
			Parent = card,
		})
		create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Padding = UDim.new(0, 4),
			Parent = btnRow,
		})
		create("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			Parent = btnRow,
		})

		local function makeBtn(txt, order, bg, tc, w)
			local b = create("TextButton", {
				Text = txt,
				Size = UDim2.new(0, w, 1, 0),
				BackgroundColor3 = bg,
				TextColor3 = tc,
				Font = Enum.Font.SourceSans,
				TextSize = 13,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				LayoutOrder = order,
				Parent = btnRow,
			})
			addCorner(b, 4)
			return b
		end

		-- Cp DName copies DisplayName
		local cpDNameBtn = makeBtn("Cp DName", 1, C.surface, C.textSecondary, 62)
		addStroke(cpDNameBtn, C.border, 1, 0.4)
		cpDNameBtn.MouseEnter:Connect(function() cpDNameBtn.BackgroundColor3 = C.surfaceHover end)
		cpDNameBtn.MouseLeave:Connect(function() cpDNameBtn.BackgroundColor3 = C.surface end)
		cpDNameBtn.MouseButton1Click:Connect(function()
			local ok = setClipboard(p.DisplayName)
			cpDNameBtn.Text = ok and "Copied!" or "Failed"
			task.delay(1, function() if cpDNameBtn.Parent then cpDNameBtn.Text = "Cp DName" end end)
		end)

		-- Cp Name copies @username
		local cpNameBtn = makeBtn("Cp Name", 2, C.surface, C.textSecondary, 56)
		addStroke(cpNameBtn, C.border, 1, 0.4)
		cpNameBtn.MouseEnter:Connect(function() cpNameBtn.BackgroundColor3 = C.surfaceHover end)
		cpNameBtn.MouseLeave:Connect(function() cpNameBtn.BackgroundColor3 = C.surface end)
		cpNameBtn.MouseButton1Click:Connect(function()
			local ok = setClipboard(p.Name)
			cpNameBtn.Text = ok and "Copied!" or "Failed"
			task.delay(1, function() if cpNameBtn.Parent then cpNameBtn.Text = "Cp Name" end end)
		end)

		local cpIdBtn = makeBtn("Cp ID", 3, C.surface, C.textSecondary, 44)
		addStroke(cpIdBtn, C.border, 1, 0.4)
		cpIdBtn.MouseEnter:Connect(function() cpIdBtn.BackgroundColor3 = C.surfaceHover end)
		cpIdBtn.MouseLeave:Connect(function() cpIdBtn.BackgroundColor3 = C.surface end)
		cpIdBtn.MouseButton1Click:Connect(function()
			local ok = setClipboard(p.UserId)
			cpIdBtn.Text = ok and "Copied!" or "Failed"
			task.delay(1, function() if cpIdBtn.Parent then cpIdBtn.Text = "Cp ID" end end)
		end)

		if not isLocal then
			local tpBtn = makeBtn("TP", 4, C.sliderTrack, C.textPrimary, 30)
			tpBtn.Font = Enum.Font.SourceSansSemibold
			tpBtn.MouseEnter:Connect(function() tpBtn.BackgroundColor3 = C.surfaceHover end)
			tpBtn.MouseLeave:Connect(function() tpBtn.BackgroundColor3 = C.sliderTrack end)
			tpBtn.MouseButton1Click:Connect(function()
				pushHistory()
				local myCh = player.Character
				local tgCh = p.Character
				if myCh and tgCh then
					local myRoot = myCh:FindFirstChild("HumanoidRootPart")
					local tgRoot = tgCh:FindFirstChild("HumanoidRootPart")
					if myRoot and tgRoot then
						myRoot.CFrame = tgRoot.CFrame + tgRoot.CFrame.LookVector * 3
					end
				end
			end)

			local specBtnW = isSpec and 62 or 66
			local specBtn = makeBtn(isSpec and "Unwatch" or "Spectate", 5,
				isSpec and C.closeHover or C.accent, C.textPrimary, specBtnW)
			specBtn.Font = Enum.Font.SourceSansSemibold
			specBtn.MouseEnter:Connect(function()
				specBtn.BackgroundColor3 = isSpec and Color3.fromRGB(200, 30, 40) or C.accentHover
			end)
			specBtn.MouseLeave:Connect(function()
				specBtn.BackgroundColor3 = isSpec and C.closeHover or C.accent
			end)
			specBtn.MouseButton1Click:Connect(function()
				startSpectate(p)
			end)
		end

		card.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				if not isSpec then card.BackgroundColor3 = C.surfaceHover end
			end
		end)
		card.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement then
				card.BackgroundColor3 = isSpec and C.selected or C.surfaceAlt
			end
		end)
	end
end

refreshPlayerList()

-- Connect search box to filter
playerSearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	refreshPlayerList()
end)

-- Distance + directional arrow updater for player cards
task.spawn(function()
	local arrs = {"\u{2191}","\u{2197}","\u{2192}","\u{2198}","\u{2193}","\u{2199}","\u{2190}","\u{2196}"}
	while screenGui and screenGui.Parent do
		local cam = Workspace.CurrentCamera
		-- In freecam, measure from camera position; otherwise from HRP
		local originPos
		if State.freecam and cam then
			originPos = cam.CFrame.Position
		else
			local myChar = player.Character
			local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
			originPos = myHRP and myHRP.Position
		end
		for _, d in ipairs(_playerDistLabels) do
			if d.label.Parent and d.target and d.target.Parent then
				local tChar = d.target.Character
				local tHRP = tChar and tChar:FindFirstChild("HumanoidRootPart")
				if originPos and tHRP then
					local dist = (originPos - tHRP.Position).Magnitude
					local arrow = ""
					if cam and dist > 2 then
						local fwd = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
						local rgt = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
						if fwd.Magnitude > 0.01 then
							fwd = fwd.Unit
							if rgt.Magnitude > 0.01 then rgt = rgt.Unit end
							local dp = Vector3.new(tHRP.Position.X - originPos.X, 0, tHRP.Position.Z - originPos.Z)
							if dp.Magnitude > 0.1 then
								dp = dp.Unit
								local deg = math.deg(math.atan2(dp:Dot(rgt), dp:Dot(fwd)))
								local idx = math.floor((deg + 22.5) / 45) % 8
								arrow = arrs[idx + 1] .. " "
							end
						end
					end
					d.label.Text = arrow .. math.floor(dist) .. " studs"
				else
					d.label.Text = "—"
				end
			end
		end
		task.wait(0.15)
	end
end)

local plrAddConn = Players.PlayerAdded:Connect(function() task.wait(0.5); refreshPlayerList() end)
local plrRemConn = Players.PlayerRemoving:Connect(function(p)
	if spectateTarget == p then stopSpectate() end
	task.wait(0.2); refreshPlayerList()
end)

════════════════
--                 PAGE 5: SETTINGS
════════════════

createSectionHeader(page5, "Configuration", 0)

local settingsStatusLabel = create("TextLabel", {
	Text = "",
	Size = UDim2.new(1, 0, 0, 22),
	BackgroundTransparency = 1,
	TextColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 1,
	Parent = page5,
})

pcall(function()
	if isfile("RSS/settings.json") then
		settingsStatusLabel.Text = "Settings loaded from RSS/settings.json"
		settingsStatusLabel.TextColor3 = Color3.fromRGB(80, 200, 80)
	else
		settingsStatusLabel.Text = "No saved settings found"
	end
end)

local sepFlyToggle -- forward declared; assigned in "Sliders & Fly" section below

-- Bug #2: Reset All now syncs slider UI & toggle state
local resetAllBtn = create("TextButton", {
	Text = "Reset All to Default",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textPrimary,
	Font = Enum.Font.GothamSemibold,
	TextSize = 14,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	LayoutOrder = 2,
	Parent = page5,
})
addCorner(resetAllBtn, 6)
create("UIStroke", { Color = C.border, Thickness = 1, Transparency = 0.4, Parent = resetAllBtn })
resetAllBtn.MouseEnter:Connect(function() resetAllBtn.BackgroundColor3 = C.closeHover end)
resetAllBtn.MouseLeave:Connect(function() resetAllBtn.BackgroundColor3 = C.surface end)
resetAllBtn.MouseButton1Click:Connect(function()
	-- Reset numeric state
	State.walkSpeed = 16; State.jumpPower = 50; State.gravity = 196
	State.fov = 70; State.camDistance = 20
	-- Apply to game
	local ch = player.Character
	if ch then
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16; hum.UseJumpPower = true; hum.JumpPower = 50 end
	end
	Workspace.Gravity = 196
	if Workspace.CurrentCamera then Workspace.CurrentCamera.FieldOfView = 70 end
	-- Bug #2: sync slider visuals
	if _sliders.walkSpeed then _sliders.walkSpeed.update(16) end
	if _sliders.jumpPower then _sliders.jumpPower.update(50) end
	if _sliders.gravity then _sliders.gravity.update(196) end
	if _sliders.fov then _sliders.fov.update(70) end
	if _sliders.camDistance then _sliders.camDistance.update(20) end
	-- Reset slider step and fly speed
	State.sliderStep = 1; State.flySpeed = 50
	if _sliders.sliderStep then _sliders.sliderStep.update(1) end
	if _sliders.flySpeed then _sliders.flySpeed.update(50) end
	State.separateFlySpeed = false
	if sepFlyToggle then sepFlyToggle.setState(false) end
	if flySpeedWrapper then flySpeedWrapper.Visible = false end
	-- Reset GUI appearance
	State.guiScale = 100; State.guiOpacity = 0
	window.Size = UDim2.fromOffset(WIN_W, WIN_H)
	_origBGTrans = {}
	applyWindowOpacity(0)
	if _sliders.guiScale then _sliders.guiScale.update(100) end
	if _sliders.guiOpacity then _sliders.guiOpacity.update(0) end
	-- Reset hitbox
	State.hitboxSize = 10
	if _sliders.hitboxSize then _sliders.hitboxSize.update(10) end
	-- Reset invis offset
	State.invisYOffset = 200000
	if _sliders.invisYOffset then _sliders.invisYOffset.update(200000) end
	-- Reset camera unlock toggle
	if State.cameraUnlock then
		State.cameraUnlock = false
		camToggle.setState(false)
		restoreCam()
	end
	saveSettings()
	settingsStatusLabel.Text = "All values reset to default"
	settingsStatusLabel.TextColor3 = Color3.fromRGB(220, 180, 50)
end)

-- Bug #3: Delete Settings suppresses pending saves
local delSettingsBtn = create("TextButton", {
	Text = "Delete Saved Settings",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.surface,
	TextColor3 = C.closeHover,
	Font = Enum.Font.GothamSemibold,
	TextSize = 14,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	LayoutOrder = 3,
	Parent = page5,
})
addCorner(delSettingsBtn, 6)
create("UIStroke", { Color = C.border, Thickness = 1, Transparency = 0.4, Parent = delSettingsBtn })
delSettingsBtn.MouseEnter:Connect(function() delSettingsBtn.BackgroundColor3 = C.closeHover; delSettingsBtn.TextColor3 = C.textPrimary end)
delSettingsBtn.MouseLeave:Connect(function() delSettingsBtn.BackgroundColor3 = C.surface; delSettingsBtn.TextColor3 = C.closeHover end)
delSettingsBtn.MouseButton1Click:Connect(function()
	-- Bug #3: suppress pending saves so they don't recreate the file
	_settingsSuppressed = true
	_settingsPending = false
	pcall(function()
		if isfile("RSS/settings.json") then delfile("RSS/settings.json") end
	end)
	settingsStatusLabel.Text = "Settings file deleted"
	settingsStatusLabel.TextColor3 = Color3.fromRGB(220, 100, 50)
	-- Re-enable saves after a safe window
	task.delay(1, function() _settingsSuppressed = false end)
end)

local delWpBtn2 = create("TextButton", {
	Text = "Delete All Waypoints",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.surface,
	TextColor3 = C.closeHover,
	Font = Enum.Font.GothamSemibold,
	TextSize = 14,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	LayoutOrder = 4,
	Parent = page5,
})
addCorner(delWpBtn2, 6)
create("UIStroke", { Color = C.border, Thickness = 1, Transparency = 0.4, Parent = delWpBtn2 })
delWpBtn2.MouseEnter:Connect(function() delWpBtn2.BackgroundColor3 = C.closeHover; delWpBtn2.TextColor3 = C.textPrimary end)
delWpBtn2.MouseLeave:Connect(function() delWpBtn2.BackgroundColor3 = C.surface; delWpBtn2.TextColor3 = C.closeHover end)
delWpBtn2.MouseButton1Click:Connect(function()
	pcall(function()
		if isfile(WP_FILE) then delfile(WP_FILE) end
	end)
	pcall(refreshWaypoints)
	delWpBtn2.Text = "Deleted!"
	task.delay(1.5, function() if delWpBtn2.Parent then delWpBtn2.Text = "Delete All Waypoints" end end)
end)

createSectionHeader(page5, "Sliders & Fly", 5)

createSlider(page5, "Slider Step", 1, 50, State.sliderStep, 6, function(v)
	State.sliderStep = v
	saveSettings()
end, "sliderStep")

sepFlyToggle = createToggle(page5, "Separate Fly Speed", 7, function(on)
	State.separateFlySpeed = on
	if flySpeedWrapper then flySpeedWrapper.Visible = on end
end)

createSectionHeader(page5, "Appearance", 8)

createSlider(page5, "GUI Scale (%)", 50, 150, State.guiScale, 81, function(v)
	State.guiScale = v
	local s = v / 100
	window.Size = UDim2.fromOffset(math.floor(WIN_W * s), math.floor(WIN_H * s))
	saveSettings()
end, "guiScale")

createSlider(page5, "Window Opacity (%)", 0, 80, State.guiOpacity, 82, function(v)
	State.guiOpacity = v
	_origBGTrans = {}
	applyWindowOpacity(v / 100)
	saveSettings()
end, "guiOpacity")

createSectionHeader(page5, "Keybinds", 10)

local bindButtons = {}

-- Bug #4: keybind rebind sets isRebinding flag to block hotkeys
local function createBindRow(labelText, bindName, order)
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = C.surface,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = page5,
	})
	addCorner(row, 6)
	addStroke(row, C.panelStroke, 1, 0.5)
	create("TextLabel", {
		Text = labelText,
		Size = UDim2.new(0.55, 0, 1, 0),
		Position = UDim2.new(0.03, 0, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = C.textPrimary,
		Font = Enum.Font.SourceSans,
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local btn = create("TextButton", {
		Text = Keybinds[bindName].Name,
		Size = UDim2.new(0.38, 0, 0, 30),
		Position = UDim2.new(0.6, 0, 0.5, -15),
		BackgroundColor3 = C.sliderTrack,
		TextColor3 = C.accent,
		Font = Enum.Font.SourceSansSemibold,
		TextSize = 15,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Parent = row,
	})
	addCorner(btn, 6)
	bindButtons[bindName] = btn

	local listening = false
	local listenConn = nil
	btn.MouseEnter:Connect(function() if not listening then btn.BackgroundColor3 = C.surfaceHover end end)
	btn.MouseLeave:Connect(function() if not listening then btn.BackgroundColor3 = C.sliderTrack end end)
	btn.MouseButton1Click:Connect(function()
		if listening then return end
		listening = true
		isRebinding = true  -- Bug #4: block global hotkeys
		btn.Text = "..."
		btn.BackgroundColor3 = C.accent
		btn.TextColor3 = C.textPrimary
		listenConn = UserInputService.InputBegan:Connect(function(input, gpe)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
			if input.KeyCode == Enum.KeyCode.Escape then
				-- Cancel
			else
				Keybinds[bindName] = input.KeyCode
			end
			btn.Text = Keybinds[bindName].Name
			btn.BackgroundColor3 = C.sliderTrack
			btn.TextColor3 = C.accent
			listening = false
			isRebinding = false  -- Bug #4: unblock
			if listenConn then listenConn:Disconnect(); listenConn = nil end
		end)
	end)
end

createBindRow("Toggle GUI",    "toggleGUI",  11)
createBindRow("Unlock Camera", "unlockCam",  12)
createBindRow("FreeCam",       "freecam",    13)
createBindRow("Invisible",     "invisible",  14)
createBindRow("Fly",           "fly",        15)

createSectionHeader(page5, "Info", 20)

create("TextLabel", {
	Text = "Place ID: " .. tostring(currentPlaceId),
	Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
	TextColor3 = C.textDim, Font = Enum.Font.SourceSans, TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 21, Parent = page5,
})
create("TextLabel", {
	Text = "Universe ID: " .. tostring(universeId),
	Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
	TextColor3 = C.textDim, Font = Enum.Font.SourceSans, TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 22, Parent = page5,
})
create("TextLabel", {
	Text = "Settings auto-save on slider change",
	Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1,
	TextColor3 = C.textDim, Font = Enum.Font.SourceSans, TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 23, Parent = page5,
})

createSectionHeader(page5, "Autoexec", 30)

-- Default relative paths to try (relative to executor workspace)
local AE_REL_PATHS = { "../autoexec/ZhirMenu.lua", "autoexec/ZhirMenu.lua" }
-- Possible source locations
local SRC_PATHS = {
	"../scripts/charter.lua",
	"../scripts/ZhirMenu.lua",
	"../scripts/zhirmenu.lua",
	"scripts/charter.lua",
	"scripts/ZhirMenu.lua",
	"RSS/ZhirMenu_src.lua",
}

-- Build effective list of all autoexec paths to try, including custom path
local function getAePaths()
	local paths = {}
	-- Custom path first (highest priority)
	local custom = State.autoexecPath
	if custom and custom ~= "" then
		-- Normalize: ensure trailing separator and append filename
		local sep = custom:find("/") and "/" or "\\"
		if not custom:match("[/\\]$") then custom = custom .. sep end
		table.insert(paths, custom .. "ZhirMenu.lua")
	end
	-- Then default relative paths
	for _, p in ipairs(AE_REL_PATHS) do
		table.insert(paths, p)
	end
	return paths
end

local function isAutoexecInstalled()
	for _, p in ipairs(getAePaths()) do
		local ok, r = pcall(isfile, p)
		if ok and r then return true, p end
	end
	return false
end

local installed, installedAt = isAutoexecInstalled()

local autoexecStatusLabel = create("TextLabel", {
	Text = installed and ("Autoexec: installed  (" .. (installedAt or "") .. ")") or "Autoexec: not installed",
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundTransparency = 1,
	TextColor3 = installed and Color3.fromRGB(80, 200, 80) or C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
	LayoutOrder = 31,
	Parent = page5,
})

-- Custom path input
create("TextLabel", {
	Text = "Custom autoexec folder (full path, leave empty = auto):",
	Size = UDim2.new(1, 0, 0, 18),
	BackgroundTransparency = 1,
	TextColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = 311,
	Parent = page5,
})

local customPathBox = create("TextBox", {
	Text = State.autoexecPath or "",
	PlaceholderText = "e.g. C:\\Users\\you\\AppData\\Local\\Potassium\\autoexec",
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundColor3 = C.surface,
	TextColor3 = C.textPrimary,
	PlaceholderColor3 = C.textDim,
	Font = Enum.Font.SourceSans,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	ClearTextOnFocus = false,
	BorderSizePixel = 0,
	LayoutOrder = 312,
	Parent = page5,
})
addCorner(customPathBox, 4)
addStroke(customPathBox, C.border, 1, 0.4)
-- Pad text a little
local cpPad = create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = customPathBox })

customPathBox.FocusLost:Connect(function()
	local txt = customPathBox.Text:match("^%s*(.-)%s*$") or ""
	State.autoexecPath = txt
	saveSettings()
	showToast(txt == "" and "Custom path cleared" or "Custom path saved", 2)
end)

local installAutoexecBtn = create("TextButton", {
	Text = installed and "Reinstall Autoexec" or "Install Autoexec",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.accent,
	TextColor3 = C.textPrimary,
	Font = Enum.Font.GothamSemibold,
	TextSize = 14,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	LayoutOrder = 32,
	Parent = page5,
})
addCorner(installAutoexecBtn, 6)
installAutoexecBtn.MouseEnter:Connect(function() installAutoexecBtn.BackgroundColor3 = C.accentHover end)
installAutoexecBtn.MouseLeave:Connect(function() installAutoexecBtn.BackgroundColor3 = C.accent end)
installAutoexecBtn.MouseButton1Click:Connect(function()
	installAutoexecBtn.Text = "Installing..."
	task.spawn(function()
		-- 1. Find script source
		local scriptSrc, foundPath = nil, nil
		for _, p in ipairs(SRC_PATHS) do
			local ok, content = pcall(readfile, p)
			if ok and type(content) == "string" and #content > 500 then
				scriptSrc = content
				foundPath = p
				break
			end
		end

		-- 2. Build autoexec file content
		local fileContent
		if scriptSrc then
			fileContent = scriptSrc
		else
			fileContent = "-- ZhirMenu Autoexec Loader\n"
				.. "-- Script source not found automatically.\n"
				.. "-- Copy your full script into RSS/ZhirMenu_src.lua\n"
				.. "pcall(function()\n"
				.. "\tif isfile and readfile and isfile('RSS/ZhirMenu_src.lua') then\n"
				.. "\t\tlocal s = readfile('RSS/ZhirMenu_src.lua')\n"
				.. "\t\tif s and #s > 100 then loadstring(s)() end\n"
				.. "\tend\n"
				.. "end)\n"
		end

		-- 3. Write to all paths (custom + default relative)
		local allPaths = getAePaths()
		local writtenTo = {}
		for _, p in ipairs(allPaths) do
			-- Try to create parent folder
			local folder = p:match("^(.+)[/\\][^/\\]+$")
			if folder then pcall(function()
				local ok2, ex = pcall(isfolder, folder)
				if ok2 and not ex then makefolder(folder) end
			end) end
			local wok = pcall(writefile, p, fileContent)
			if wok then table.insert(writtenTo, p) end
		end

		-- 4. Persist source to RSS
		if scriptSrc then
			pcall(function()
				if not isfolder("RSS") then makefolder("RSS") end
				writefile("RSS/ZhirMenu_src.lua", scriptSrc)
			end)
		end

		-- 5. Update UI
		if #writtenTo > 0 then
			local paths = table.concat(writtenTo, "\n")
			autoexecStatusLabel.Text = "Autoexec: installed\n" .. paths
				.. (scriptSrc and ("\nSource: " .. foundPath) or "\n(loader only — no source found)")
			autoexecStatusLabel.TextColor3 = scriptSrc and Color3.fromRGB(80, 200, 80) or Color3.fromRGB(220, 180, 50)
			installAutoexecBtn.Text = "Reinstall Autoexec"
			showToast(
				scriptSrc and ("Autoexec installed to " .. #writtenTo .. " path(s)!") or "Autoexec installed (loader only)",
				scriptSrc and 3 or 5,
				scriptSrc and C.accent or Color3.fromRGB(220, 180, 50)
			)
		else
			autoexecStatusLabel.Text = "Failed to write any autoexec file.\nSet the custom path to your executor's autoexec folder."
			autoexecStatusLabel.TextColor3 = C.closeHover
			installAutoexecBtn.Text = "Install Autoexec"
			showToast("Failed — try setting the custom path above", 4, C.closeHover)
		end
	end)
end)

local removeAutoexecBtn = create("TextButton", {
	Text = "Remove Autoexec",
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = C.surface,
	TextColor3 = C.closeHover,
	Font = Enum.Font.GothamSemibold,
	TextSize = 14,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	LayoutOrder = 33,
	Parent = page5,
})
addCorner(removeAutoexecBtn, 6)
addStroke(removeAutoexecBtn, C.border, 1, 0.4)
removeAutoexecBtn.MouseEnter:Connect(function() removeAutoexecBtn.BackgroundColor3 = C.closeHover; removeAutoexecBtn.TextColor3 = C.textPrimary end)
removeAutoexecBtn.MouseLeave:Connect(function() removeAutoexecBtn.BackgroundColor3 = C.surface; removeAutoexecBtn.TextColor3 = C.closeHover end)
removeAutoexecBtn.MouseButton1Click:Connect(function()
	for _, p in ipairs(getAePaths()) do
		pcall(function()
			local ok, r = pcall(isfile, p)
			if ok and r then delfile(p) end
		end)
	end
	autoexecStatusLabel.Text = "Autoexec: not installed"
	autoexecStatusLabel.TextColor3 = C.textDim
	installAutoexecBtn.Text = "Install Autoexec"
	showToast("Autoexec removed")
end)

create("TextLabel", {
	Text = "Potassium: C:\\Users\\<you>\\AppData\\Local\\Potassium\\autoexec",
	Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1,
	TextColor3 = C.textDim, Font = Enum.Font.SourceSans, TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
	LayoutOrder = 34, Parent = page5,
})


--  Respawn


player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	task.wait(0.3)

	hum.WalkSpeed = State.walkSpeed
	hum.UseJumpPower = true
	hum.JumpPower = State.jumpPower
	Workspace.Gravity = State.gravity

	local cam = Workspace.CurrentCamera
	if cam then cam.FieldOfView = State.fov end
	if State.cameraUnlock then applyCamUnlock() end
	if State.freezePlayer then setAnchored(true) end
	if State.removeLighting then task.wait(0.2); stripLight() end
	if State.fly then task.wait(0.2); startFly() end
	if State.esp then
		task.wait(0.3)
		for _, p in ipairs(Players:GetPlayers()) do addESP(p) end
	end
	-- On respawn, deactivate invisible (new character; connection will be re-established on next toggle)
	if State.invisible then
		State.invisible = false
		if invisConn then invisConn:Disconnect(); invisConn = nil end
	end
end)


--  Drag


do
	local da, ds, sp
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			da = true; ds = input.Position; sp = Vector2.new(window.Position.X.Offset, window.Position.Y.Offset)
		end
	end)
	titleBar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then da = false end
	end)
	-- Bug #1: track drag connection
	trackConn(UserInputService.InputChanged:Connect(function(input)
		if da and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - ds
			setWindowOffsets(sp.X + d.X, sp.Y + d.Y)
		end
	end))
end


--  Minimize / Close


local mini = false
local miniSz = UDim2.fromOffset(WIN_W, TITLE_H_PX)

local function getFullSz()
	local s = (State.guiScale or 100) / 100
	return UDim2.fromOffset(math.floor(WIN_W * s), math.floor(WIN_H * s))
end

minimizeBtn.MouseButton1Click:Connect(function()
	mini = not mini
	if mini then
		for _, pg in ipairs(tabPages) do pg.Visible = false end
		tabBar.Visible = false
		window:TweenSize(miniSz, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
		task.delay(0.16, function()
			if window.Parent then setWindowOffsets(window.Position.X.Offset, window.Position.Y.Offset) end
		end)
	else
		window:TweenSize(getFullSz(), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
		task.delay(0.15, function()
			tabBar.Visible = true
			switchTab(activeTab)
			setWindowOffsets(window.Position.X.Offset, window.Position.Y.Offset)
		end)
	end
end)

-- Bug #1: cleanupAll now disconnects ALL tracked global connections
local function cleanupAll()
	-- Restore original game values captured at script start
	local ch = player.Character
	if ch then
		local hum = ch:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = _origValues.walkSpeed
			hum.UseJumpPower = true
			hum.JumpPower = _origValues.jumpPower
		end
	end
	Workspace.Gravity = _origValues.gravity
	local cam = Workspace.CurrentCamera
	if cam then
		cam.FieldOfView = _origValues.fov
		pcall(function()
			player.CameraMinZoomDistance = _origValues.camMinZoom
			player.CameraMaxZoomDistance = _origValues.camMaxZoom
		end)
	end

	State.freezePlayer = false
	if freezeConn then freezeConn:Disconnect(); freezeConn = nil end
	setAnchored(false)
	State.infJump = false; if ijConn then ijConn:Disconnect(); ijConn = nil end
	State.noclip = false; if ncConn then ncConn:Disconnect(); ncConn = nil end
	if State.fly then State.fly = false; stopFly() end
	if State.esp then State.esp = false; disableESP() end
	if State.invisible then State.invisible = false; if invisConn then invisConn:Disconnect(); invisConn = nil end end
	if State.freecam then State.freecam = false; stopFreecam() end
	if State.removeLighting then State.removeLighting = false; restoreLight() end
	if State.cameraUnlock then State.cameraUnlock = false; restoreCam() end
	State.antiAfk = false; if afkConn then afkConn:Disconnect(); afkConn = nil end
	State.hitboxExpander = false; if hbConn then hbConn:Disconnect(); hbConn = nil end; pcall(resetHitboxes)
	stopSpectate()
	if plrAddConn then plrAddConn:Disconnect(); plrAddConn = nil end
	if plrRemConn then plrRemConn:Disconnect(); plrRemConn = nil end
	-- Bug #1: disconnect all tracked global UIS connections (sliders, drag, keybinds)
	for _, conn in ipairs(_allConns) do
		pcall(function() conn:Disconnect() end)
	end
	table.clear(_allConns)
	local env = (type(getgenv) == "function" and getgenv()) or _G
	env._StatsGUI_Instance = nil
	screenGui:Destroy()
end

closeBtn.MouseButton1Click:Connect(cleanupAll)

do
	local env = (type(getgenv) == "function" and getgenv()) or _G
	env._StatsGUI_Instance = {
		active = true,
		show = function()
			if not screenGui.Parent then return end
			window.Visible = true
			if mini then
				mini = false
				window:TweenSize(getFullSz(), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.15, true)
				task.delay(0.15, function() tabBar.Visible = true; switchTab(activeTab) end)
			end
		end,
	}
end


--  Keybinds  (Bug #1 + Bug #4)


trackConn(UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if isRebinding then return end  -- Bug #4: don't fire hotkeys while rebinding
	if input.KeyCode == Keybinds.toggleGUI then
		window.Visible = not window.Visible
	elseif input.KeyCode == Keybinds.unlockCam then
		State.cameraUnlock = not State.cameraUnlock
		camToggle.setState(State.cameraUnlock)
		if State.cameraUnlock then
			if not origCamMode then
				origCamMode = player.CameraMode
				origMinZoom = player.CameraMinZoomDistance
				origMaxZoom = player.CameraMaxZoomDistance
			end
			applyCamUnlock()
		else restoreCam() end
	elseif input.KeyCode == Keybinds.freecam then
		State.freecam = not State.freecam
		freecamToggle.setState(State.freecam)
		if State.freecam then startFreecam() else stopFreecam() end
	elseif input.KeyCode == Keybinds.invisible then
		State.invisible = not State.invisible
		invisToggle.setState(State.invisible)
		setInvisVisual(State.invisible)
		if State.invisible then
			if invisConn then invisConn:Disconnect() end
			invisConn = RunService.Heartbeat:Connect(function()
				if not State.invisible then return end
				local ch = player.Character; if not ch then return end
				local hrp = ch:FindFirstChild("HumanoidRootPart")
				local hum = ch:FindFirstChildOfClass("Humanoid")
				if not hrp or not hum then return end
				local savedCFrame = hrp.CFrame
				local savedCamOffset = hum.CameraOffset
				local underCFrame = savedCFrame * CFrame.new(0, -State.invisYOffset, 0)
				local camOff = underCFrame:ToObjectSpace(CFrame.new(savedCFrame.Position)).Position
				hrp.CFrame = underCFrame
				hum.CameraOffset = camOff
				RunService.RenderStepped:Wait()
				if hrp and hrp.Parent then
					hrp.CFrame = savedCFrame
hum.CameraOffset = savedCamOffset
					end
				end)
			else
				if invisConn then invisConn:Disconnect(); invisConn = nil end
			end
	elseif input.KeyCode == Keybinds.fly then
		State.fly = not State.fly
		flyToggle.setState(State.fly)
		if State.fly then startFly() else stopFly() end
		showToast(State.fly and "Fly enabled" or "Fly disabled")
	end
end))

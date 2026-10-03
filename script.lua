-- Ragim Panel / Terminal UI
--
-- 명령어 텍스트 클릭: 기능 ON / OFF
-- F: 비행 ON / OFF
-- WASD: 비행 이동
-- Space / E: 상승
-- Q: 하강
-- Enter: 플레이어 잠금 OFF
-- \: 패널 숨기기 / 표시
--
-- /console: 실제 Lua 실행창 펼치기
-- Lua 실행은 실행기의 loadstring 지원이 필요합니다.

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
assert(player, "클라이언트에서 실행해야 합니다.")

local playerGui = player:WaitForChild("PlayerGui")
local RENDER_NAME = "RagimPanel_TargetLock"
local CLEANUP_KEY = "__RagimPanelCleanup"

local environment = _G
if type(getgenv) == "function" then
	environment = getgenv()
end

if type(environment[CLEANUP_KEY]) == "function" then
	pcall(environment[CLEANUP_KEY])
end

local oldGui = playerGui:FindFirstChild("RagimPanel")
if oldGui then oldGui:Destroy() end

-- 설정
local settings = {
	FlySpeed = 50,
	WalkSpeed = 16,
	JumpPower = 50,
}

local closed = false
local flying = false
local noclip = false
local targetLock = false
local espEnabled = false
local consoleVisible = false
local luaRunning = false

local selectedUserId, selectedUsername
local flightHumanoid, flightRoot
local attachment, velocity, orientation
local savedAutoRotate, savedPlatformStand, savedMouseBehavior
local watchedHumanoid
local draggingSlider

local connections = {}
local movementConnections = {}
local originalCollisions = {}
local espEntries = {}

-- 터미널 색상
local C = {
	Background = Color3.fromRGB(22, 31, 39),
	Titlebar = Color3.fromRGB(17, 24, 31),
	Input = Color3.fromRGB(17, 26, 33),
	Accent = Color3.fromRGB(91, 216, 180),
	Border = Color3.fromRGB(61, 115, 112),
	Text = Color3.fromRGB(215, 228, 229),
	Muted = Color3.fromRGB(126, 153, 159),
	Dim = Color3.fromRGB(44, 67, 73),
	Error = Color3.fromRGB(238, 130, 130),
}

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function create(className, properties, parent)
	local object = Instance.new(className)

	for key, value in pairs(properties) do
		object[key] = value
	end

	object.Parent = parent
	return object
end

local function trim(text)
	return text:match("^%s*(.-)%s*$")
end

-- 메인 창
local gui = create("ScreenGui", {
	Name = "RagimPanel",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local panel = create("Frame", {
	Size = UDim2.new(0, 440, 0.9, 0),
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 24, 0.5, 0),
	BackgroundColor3 = C.Background,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, gui)

create("UISizeConstraint", {
	MaxSize = Vector2.new(440, 800),
}, panel)

create("UIStroke", {
	Color = C.Border,
	Thickness = 1,
}, panel)

local titlebar = create("Frame", {
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundColor3 = C.Titlebar,
	BorderSizePixel = 0,
}, panel)

create("TextLabel", {
	Size = UDim2.new(1, -75, 1, 0),
	Position = UDim2.fromOffset(12, 0),
	BackgroundTransparency = 1,
	Text = "ragim@client: ~",
	TextColor3 = C.Muted,
	TextSize = 13,
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
}, titlebar)

local hideButton = create("TextButton", {
	Size = UDim2.fromOffset(56, 32),
	Position = UDim2.new(1, -60, 0, 0),
	BackgroundTransparency = 1,
	Text = "[ - ]",
	TextColor3 = C.Accent,
	TextSize = 15,
	Font = Enum.Font.Code,
	AutoButtonColor = false,
}, titlebar)

connect(hideButton.Activated, function()
	panel.Visible = false
	draggingSlider = nil
end)

local content = create("ScrollingFrame", {
	Size = UDim2.new(1, -20, 1, -42),
	Position = UDim2.fromOffset(10, 36),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = C.Border,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)

create("UIPadding", {
	PaddingTop = UDim.new(0, 10),
	PaddingBottom = UDim.new(0, 16),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 10),
}, content)

create("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 7),
}, content)

local order = 0

local function widget(className, properties)
	order = order + 1
	properties.LayoutOrder = order
	return create(className, properties, content)
end

local function label(text, height, size, color)
	return widget("TextLabel", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = color or C.Text,
		TextSize = size or 14,
		Font = Enum.Font.Code,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

local function separator()
	return widget("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = C.Border,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	})
end

label("Ragim Panel", 46, 34, C.Accent)
label("[ client control terminal ]", 20, 13, C.Muted)
separator()
label("commands", 24, 16, C.Accent)

-- 클릭 가능한 명령어 목록
local function command(name, description)
	local button = widget("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = string.format("  %-11s [OFF]", name),
		TextColor3 = C.Text,
		TextSize = 15,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
		AutoButtonColor = false,
	})

	create("TextLabel", {
		Size = UDim2.new(0.46, -8, 1, 0),
		Position = UDim2.fromScale(0.54, 0),
		BackgroundTransparency = 1,
		Text = description,
		TextColor3 = C.Muted,
		TextSize = 12,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, button)

	connect(button.MouseEnter, function()
		button.BackgroundTransparency = 0.94
	end)

	connect(button.MouseLeave, function()
		button.BackgroundTransparency = 1
	end)

	return button
end

local flyButton = command("/fly", "비행")
local noclipButton = command("/wallhack", "벽 통과")
local espButton = command("/esp", "이름 / 거리 / 윤곽선")
local lockButton = command("/lock", "플레이어 잠금")
local consoleButton = command("/console", "Lua 실행창")

separator()
label("control", 24, 16, C.Accent)

local function updateButtons()
	if closed then return end

	local function paint(button, name, enabled)
		button.Text = string.format(
			"  %-11s [%s]",
			name,
			enabled and "ON" or "OFF"
		)
		button.TextColor3 = enabled and C.Accent or C.Text
	end

	paint(flyButton, "/fly", flying)
	paint(noclipButton, "/wallhack", noclip)
	paint(espButton, "/esp", espEnabled)
	paint(lockButton, "/lock", targetLock)
	paint(consoleButton, "/console", consoleVisible)
end

-- 속도 / 점프력 자동 복원
local function disconnectMovementWatchers()
	for _, connection in ipairs(movementConnections) do
		connection:Disconnect()
	end

	table.clear(movementConnections)
	watchedHumanoid = nil
end

local function applyMovementSettings()
	if closed then return end

	local character = player.Character
	local humanoid = character
		and character:FindFirstChildOfClass("Humanoid")

	if not humanoid then return end

	if watchedHumanoid ~= humanoid then
		disconnectMovementWatchers()
		watchedHumanoid = humanoid

		local function watch(property, getDesiredValue)
			local restoring = false

			local connection =
				humanoid:GetPropertyChangedSignal(property):Connect(function()
					if closed or restoring then return end
					if watchedHumanoid ~= humanoid then return end
					if not humanoid.Parent then return end

					local desired = getDesiredValue()

					if humanoid[property] ~= desired then
						restoring = true
						humanoid[property] = desired
						restoring = false
					end
				end)

			table.insert(movementConnections, connection)
		end

		watch("WalkSpeed", function()
			return settings.WalkSpeed
		end)

		watch("JumpPower", function()
			return settings.JumpPower
		end)

		watch("UseJumpPower", function()
			return true
		end)
	end

	if humanoid.WalkSpeed ~= settings.WalkSpeed then
		humanoid.WalkSpeed = settings.WalkSpeed
	end

	if not humanoid.UseJumpPower then
		humanoid.UseJumpPower = true
	end

	if humanoid.JumpPower ~= settings.JumpPower then
		humanoid.JumpPower = settings.JumpPower
	end
end

-- 슬라이더 + 숫자 입력
local function slider(name, key, minimum, maximum)
	local row = widget("Frame", {
		Size = UDim2.new(1, 0, 0, 58),
		BackgroundTransparency = 1,
	})

	create("TextLabel", {
		Size = UDim2.new(1, -85, 0, 25),
		BackgroundTransparency = 1,
		Text = name .. ":",
		TextColor3 = C.Text,
		TextSize = 15,
		Font = Enum.Font.Code,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, row)

	local box = create("TextBox", {
		Size = UDim2.fromOffset(74, 25),
		Position = UDim2.new(1, -74, 0, 0),
		BackgroundColor3 = C.Input,
		BorderColor3 = C.Border,
		BorderSizePixel = 1,
		Text = tostring(settings[key]),
		TextColor3 = C.Accent,
		TextSize = 15,
		Font = Enum.Font.Code,
		ClearTextOnFocus = false,
		MultiLine = false,
	}, row)

	local track = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 12),
		Position = UDim2.fromOffset(0, 35),
		BackgroundColor3 = C.Dim,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
	}, row)

	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
	}, track)

	local function refresh()
		local fraction = (settings[key] - minimum) / (maximum - minimum)
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		box.Text = tostring(settings[key])
	end

	local function setValue(value)
		settings[key] = math.clamp(value, minimum, maximum)
		refresh()
		applyMovementSettings()
	end

	local function setFromX(x)
		if track.AbsoluteSize.X <= 0 then return end

		local fraction = math.clamp(
			(x - track.AbsolutePosition.X) / track.AbsoluteSize.X,
			0,
			1
		)

		local value = minimum + fraction * (maximum - minimum)
		setValue(math.floor(value + 0.5))
	end

	connect(track.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then

			draggingSlider = {
				input = input,
				setFromX = setFromX,
				touch = input.UserInputType == Enum.UserInputType.Touch,
			}

			setFromX(input.Position.X)
		end
	end)

	connect(box.FocusLost, function()
		if closed then return end

		local value = tonumber(box.Text)

		if value and value == value
			and value > -math.huge
			and value < math.huge then
			setValue(value)
		else
			refresh()
		end
	end)

	refresh()
end

slider("flyspeed", "FlySpeed", 0, 500)
slider("walkspeed", "WalkSpeed", 0, 500)
slider("jumppower", "JumpPower", 0, 1000)

connect(UIS.InputChanged, function(input)
	if closed or not panel.Visible then
		draggingSlider = nil
		return
	end

	local drag = draggingSlider
	if not drag then return end

	if drag.touch then
		if input == drag.input then
			drag.setFromX(input.Position.X)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseMovement then
		drag.setFromX(input.Position.X)
	end
end)

connect(UIS.InputEnded, function(input)
	local drag = draggingSlider
	if not drag then return end

	if input == drag.input
		or (
			not drag.touch
			and input.UserInputType == Enum.UserInputType.MouseButton1
		) then
		draggingSlider = nil
	end
end)

-- 대상 선택
separator()
label("target", 24, 16, C.Accent)

local targetRow = widget("Frame", {
	Size = UDim2.new(1, 0, 0, 32),
	BackgroundTransparency = 1,
})

local targetBox = create("TextBox", {
	Size = UDim2.new(1, -82, 1, 0),
	BackgroundColor3 = C.Input,
	BorderColor3 = C.Border,
	BorderSizePixel = 1,
	Text = "",
	PlaceholderText = "Username / 빈칸 = nearest",
	PlaceholderColor3 = C.Muted,
	TextColor3 = C.Text,
	TextSize = 13,
	Font = Enum.Font.Code,
	ClearTextOnFocus = false,
	MultiLine = false,
}, targetRow)

local applyTargetButton = create("TextButton", {
	Size = UDim2.fromOffset(76, 32),
	Position = UDim2.new(1, -76, 0, 0),
	BackgroundTransparency = 1,
	Text = "/apply",
	TextColor3 = C.Accent,
	TextSize = 14,
	Font = Enum.Font.Code,
	AutoButtonColor = false,
}, targetRow)

local selectionLabel = label("selected: nearest player", 34, 12, C.Muted)
local statusLabel = label("movement values: auto restore ON", 30, 12, C.Muted)

separator()

label(
	"[ F ] fly   [ WASD ] move\n"
		.. "[ Space / E ] up   [ Q ] down\n"
		.. "[ Enter ] unlock   [ \\ ] hide / show\n"
		.. "wallhack ON: 바닥도 통과합니다.",
	78,
	12,
	C.Muted
)

-- 접었다 펼치는 Lua 콘솔
local consoleGroup = widget("Frame", {
	Size = UDim2.new(1, 0, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Visible = false,
})

create("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 7),
}, consoleGroup)

local consoleOrder = 0

local function consoleWidget(className, properties)
	consoleOrder = consoleOrder + 1
	properties.LayoutOrder = consoleOrder
	return create(className, properties, consoleGroup)
end

consoleWidget("TextLabel", {
	Size = UDim2.new(1, 0, 0, 26),
	BackgroundTransparency = 1,
	Text = "lua console",
	TextColor3 = C.Accent,
	TextSize = 16,
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
})

consoleWidget("TextLabel", {
	Size = UDim2.new(1, 0, 0, 36),
	BackgroundTransparency = 1,
	Text = "실제 Lua 실행창입니다.\nprint / warn 출력은 실행기 콘솔에 표시됩니다.",
	TextColor3 = C.Muted,
	TextSize = 12,
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextWrapped = true,
})

local codeFrame = consoleWidget("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 175),
	BackgroundColor3 = C.Input,
	BorderColor3 = C.Border,
	BorderSizePixel = 1,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = C.Border,
	ScrollingDirection = Enum.ScrollingDirection.Y,
})

local codeBox = create("TextBox", {
	Size = UDim2.new(1, -18, 0, 158),
	Position = UDim2.fromOffset(8, 8),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Text = 'print("Hello from Ragim Panel")',
	TextColor3 = C.Text,
	TextSize = 14,
	Font = Enum.Font.Code,
	ClearTextOnFocus = false,
	MultiLine = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, codeFrame)

local consoleActions = consoleWidget("Frame", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
})

local executeButton = create("TextButton", {
	Size = UDim2.new(0.5, 0, 1, 0),
	BackgroundTransparency = 1,
	Text = "/execute",
	TextColor3 = C.Accent,
	TextSize = 15,
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Left,
	AutoButtonColor = false,
}, consoleActions)

local clearOutputButton = create("TextButton", {
	Size = UDim2.new(0.5, 0, 1, 0),
	Position = UDim2.fromScale(0.5, 0),
	BackgroundTransparency = 1,
	Text = "/clear",
	TextColor3 = C.Muted,
	TextSize = 15,
	Font = Enum.Font.Code,
	TextXAlignment = Enum.TextXAlignment.Right,
	AutoButtonColor = false,
}, consoleActions)

local outputFrame = consoleWidget("ScrollingFrame", {
	Size = UDim2.new(1, 0, 0, 130),
	BackgroundColor3 = C.Input,
	BorderColor3 = C.Border,
	BorderSizePixel = 1,
	CanvasSize = UDim2.fromOffset(0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = C.Border,
	ScrollingDirection = Enum.ScrollingDirection.Y,
})

local outputLabel = create("TextLabel", {
	Size = UDim2.new(1, -18, 0, 0),
	Position = UDim2.fromOffset(8, 8),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = C.Accent,
	TextSize = 12,
	Font = Enum.Font.Code,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
}, outputFrame)

label("ragim@client:~$ click a command", 26, 12, C.Accent)

local outputEntries = {}

local function writeOutput(message)
	if closed then return end

	table.insert(outputEntries, tostring(message))

	while #outputEntries > 30 do
		table.remove(outputEntries, 1)
	end

	outputLabel.Text = table.concat(outputEntries, "\n")
end

connect(consoleButton.Activated, function()
	if closed then return end

	consoleVisible = not consoleVisible
	consoleGroup.Visible = consoleVisible
	updateButtons()
end)

connect(clearOutputButton.Activated, function()
	table.clear(outputEntries)
	outputLabel.Text = ""
end)

connect(executeButton.Activated, function()
	if closed or luaRunning then return end

	local source = codeBox.Text

	if trim(source) == "" then
		writeOutput("[info] 실행할 Lua 코드를 입력하세요.")
		return
	end

	if type(loadstring) ~= "function" then
		writeOutput("[error] loadstring을 지원하지 않는 실행 환경입니다.")
		return
	end

	local compileOK, chunk, compileError = pcall(
		loadstring,
		source,
		"RagimPanelConsole"
	)

	if not compileOK then
		writeOutput("[compile error] " .. tostring(chunk))
		return
	end

	if type(chunk) ~= "function" then
		writeOutput("[syntax error] " .. tostring(compileError))
		return
	end

	luaRunning = true
	executeButton.Text = "/running..."
	writeOutput("[run] Lua 실행 시작")

	task.spawn(function()
		local success, result = pcall(chunk)
		luaRunning = false

		if closed then return end

		executeButton.Text = "/execute"

		if success then
			writeOutput("[done] 코드 실행 종료")

			if result ~= nil then
				writeOutput("[return] " .. tostring(result))
			end
		else
			writeOutput("[runtime error] " .. tostring(result))
		end
	end)
end)

-- 플레이어 검색
local function getAliveRoot(targetPlayer)
	local character = targetPlayer.Character
	local humanoid = character
		and character:FindFirstChildOfClass("Humanoid")
	local root = character
		and character:FindFirstChild("HumanoidRootPart")

	if humanoid and humanoid.Health > 0
		and root and root:IsA("BasePart")
		and root:IsDescendantOf(workspace) then
		return root
	end

	return nil
end

local function findPlayerByName(query)
	query = string.lower(trim(query))

	if query:sub(1, 1) == "@" then
		query = query:sub(2)
	end

	if query == "" then
		return nil, "플레이어 이름을 입력하세요."
	end

	local exactDisplay = {}
	local partial = {}

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local username = string.lower(other.Name)
			local display = string.lower(other.DisplayName)

			if username == query then
				return other, nil
			end

			if display == query then
				table.insert(exactDisplay, other)
			end

			if string.find(username, query, 1, true)
				or string.find(display, query, 1, true) then
				table.insert(partial, other)
			end
		end
	end

	if #exactDisplay == 1 then
		return exactDisplay[1], nil
	elseif #exactDisplay > 1 then
		return nil, "표시 이름이 중복됩니다. Username을 입력하세요."
	end

	if #partial == 1 then
		return partial[1], nil
	elseif #partial > 1 then
		return nil, "여러 명이 일치합니다. 정확한 Username을 입력하세요."
	end

	return nil, "현재 서버에서 해당 플레이어를 찾지 못했습니다."
end

connect(applyTargetButton.Activated, function()
	if closed then return end

	local query = trim(targetBox.Text)

	if query == "" then
		selectedUserId = nil
		selectedUsername = nil
		targetBox.Text = ""
		selectionLabel.Text = "selected: nearest player"
		selectionLabel.TextColor3 = C.Muted
		return
	end

	local matched, message = findPlayerByName(query)

	if not matched then
		selectionLabel.Text = message .. "\n기존 선택 유지"
		selectionLabel.TextColor3 = C.Error
		return
	end

	selectedUserId = matched.UserId
	selectedUsername = matched.Name
	targetBox.Text = "@" .. matched.Name
	selectionLabel.Text = "selected: @" .. matched.Name
	selectionLabel.TextColor3 = C.Accent
end)

local function findLockTarget()
	if selectedUserId ~= nil then
		for _, other in ipairs(Players:GetPlayers()) do
			if other.UserId == selectedUserId then
				local root = getAliveRoot(other)

				if root then
					return other, root
				end

				return nil, nil
			end
		end

		return nil, nil
	end

	local myRoot = getAliveRoot(player)
	if not myRoot then return nil, nil end

	local nearestPlayer
	local nearestRoot
	local nearestDistance = math.huge

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local root = getAliveRoot(other)

			if root then
				local distance = (root.Position - myRoot.Position).Magnitude

				if distance < nearestDistance then
					nearestDistance = distance
					nearestPlayer = other
					nearestRoot = root
				end
			end
		end
	end

	return nearestPlayer, nearestRoot
end

-- 기존 벽 통과 기능
local function restoreCollisions()
	for part, original in pairs(originalCollisions) do
		if part.Parent then
			part.CanCollide = original
		end
	end

	table.clear(originalCollisions)
end

local function applyNoclip()
	local character = player.Character
	if not character then return end

	for part, original in pairs(originalCollisions) do
		if not part:IsDescendantOf(character) then
			if part.Parent then
				part.CanCollide = original
			end

			originalCollisions[part] = nil
		end
	end

	for _, object in ipairs(character:GetDescendants()) do
		if object:IsA("BasePart") then
			if originalCollisions[object] == nil then
				originalCollisions[object] = object.CanCollide
			end

			if object.CanCollide then
				object.CanCollide = false
			end
		end
	end
end

local function setNoclip(enabled)
	if enabled and (closed or not getAliveRoot(player)) then
		return
	end

	noclip = enabled

	if enabled then
		applyNoclip()
	else
		restoreCollisions()
	end

	updateButtons()
end

-- 비행
local function stopFlying()
	flying = false

	if velocity then velocity:Destroy() end
	if orientation then orientation:Destroy() end
	if attachment then attachment:Destroy() end

	velocity = nil
	orientation = nil
	attachment = nil

	if flightRoot and flightRoot.Parent then
		flightRoot.AssemblyLinearVelocity = Vector3.zero
		flightRoot.AssemblyAngularVelocity = Vector3.zero
	end

	if flightHumanoid and flightHumanoid.Parent then
		flightHumanoid.AutoRotate = savedAutoRotate
		flightHumanoid.PlatformStand = savedPlatformStand
	end

	flightHumanoid = nil
	flightRoot = nil
	updateButtons()
end

local function setFlying(enabled)
	if not enabled then
		stopFlying()
		return
	end

	if closed or flying then return end

	local root = getAliveRoot(player)
	local character = player.Character

	if not root or not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root.Anchored or humanoid.SeatPart then return end

	flightHumanoid = humanoid
	flightRoot = root
	savedAutoRotate = humanoid.AutoRotate
	savedPlatformStand = humanoid.PlatformStand

	attachment = create("Attachment", {
		Name = "RagimFlyAttachment",
	}, root)

	velocity = create("LinearVelocity", {
		Name = "RagimFlyVelocity",
		Attachment0 = attachment,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		ForceLimitsEnabled = false,
		VectorVelocity = Vector3.zero,
	}, root)

	orientation = create("AlignOrientation", {
		Name = "RagimFlyOrientation",
		Attachment0 = attachment,
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		MaxTorque = math.huge,
		MaxAngularVelocity = math.huge,
		Responsiveness = 25,
		CFrame = root.CFrame.Rotation,
	}, root)

	humanoid.AutoRotate = false
	humanoid.PlatformStand = true

	flying = true
	updateButtons()
end

-- 플레이어 잠금
local function setTargetLock(enabled)
	if enabled == targetLock then return end

	if enabled then
		if closed or not getAliveRoot(player) then return end

		savedMouseBehavior = UIS.MouseBehavior
		targetLock = true
		UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
		statusLabel.Text = "lock: searching..."
	else
		targetLock = false

		if savedMouseBehavior ~= nil then
			UIS.MouseBehavior = savedMouseBehavior
			savedMouseBehavior = nil
		end

		if not closed then
			statusLabel.Text = "movement values: auto restore ON"
		end
	end

	updateButtons()
end

RunService:BindToRenderStep(
	RENDER_NAME,
	Enum.RenderPriority.Camera.Value + 1,
	function()
		if closed or not targetLock then return end

		if not getAliveRoot(player) then
			setTargetLock(false)
			return
		end

		UIS.MouseBehavior = Enum.MouseBehavior.LockCenter

		local camera = workspace.CurrentCamera
		local targetPlayer, targetRoot = findLockTarget()

		if not targetPlayer or not targetRoot then
			statusLabel.Text = selectedUserId
				and ("waiting: @" .. selectedUsername)
				or "lock: no target"

			return
		end

		statusLabel.Text = "tracking: @" .. targetPlayer.Name

		if camera then
			local position = camera.CFrame.Position
			local offset = targetRoot.Position - position

			if offset.Magnitude > 0.001 then
				local up = Vector3.yAxis

				if math.abs(offset.Unit:Dot(up)) > 0.999 then
					up = Vector3.zAxis
				end

				camera.CFrame = CFrame.lookAt(
					position,
					targetRoot.Position,
					up
				)
			end
		end
	end
)

-- ESP
local ESP_COLOR = Color3.fromRGB(65, 220, 255)

local espFolder = create("Folder", {
	Name = "RagimPanelESP",
}, workspace)

local function removeESP(other)
	local entry = espEntries[other]
	if not entry then return end

	entry.highlight:Destroy()
	entry.billboard:Destroy()
	espEntries[other] = nil
end

local function clearESP()
	for other in pairs(espEntries) do
		removeESP(other)
	end
end

local function createESP(other, root)
	local highlight = create("Highlight", {
		Name = "RagimESP_" .. other.UserId,
		Adornee = other.Character,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillColor = ESP_COLOR,
		FillTransparency = 0.85,
		OutlineColor = ESP_COLOR,
		OutlineTransparency = 0,
		Enabled = true,
	}, espFolder)

	local billboard = create("BillboardGui", {
		Name = "RagimESPLabel_" .. other.UserId,
		Adornee = root,
		Size = UDim2.fromOffset(200, 60),
		StudsOffsetWorldSpace = Vector3.new(0, 3.5, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 0,
	}, playerGui)

	local text = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = ESP_COLOR,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		TextStrokeTransparency = 0.2,
		TextSize = 13,
		Font = Enum.Font.Code,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, billboard)

	local entry = {
		character = other.Character,
		highlight = highlight,
		billboard = billboard,
		text = text,
	}

	espEntries[other] = entry
	return entry
end

local function updateESP()
	if closed or not espEnabled then return end

	local myCharacter = player.Character
	local myRoot = myCharacter
		and myCharacter:FindFirstChild("HumanoidRootPart")

	local seen = {}

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local root = getAliveRoot(other)

			if root then
				seen[other] = true
				local entry = espEntries[other]

				if entry and (
					entry.character ~= other.Character
					or not entry.highlight.Parent
					or not entry.billboard.Parent
				) then
					removeESP(other)
					entry = nil
				end

				if not entry then
					entry = createESP(other, root)
				end

				entry.billboard.Adornee = root

				local distanceText = "..."

				if myRoot and myRoot:IsA("BasePart") then
					local distance =
						(root.Position - myRoot.Position).Magnitude

					distanceText =
						tostring(math.floor(distance + 0.5)) .. " studs"
				end

				entry.text.Text = other.DisplayName
					.. "\n@" .. other.Name
					.. "\n" .. distanceText
			end
		end
	end

	for other in pairs(espEntries) do
		if not seen[other] then
			removeESP(other)
		end
	end
end

local espElapsed = 0

local function setESP(enabled)
	if enabled and closed then return end

	espEnabled = enabled
	espElapsed = 0

	if enabled then
		updateESP()
	else
		clearESP()
	end

	updateButtons()
end

connect(RunService.Heartbeat, function(deltaTime)
	if closed or not espEnabled then return end

	espElapsed = espElapsed + deltaTime

	if espElapsed >= 0.15 then
		espElapsed = 0
		updateESP()
	end
end)

connect(Players.PlayerRemoving, removeESP)

-- 명령어 텍스트 클릭
connect(flyButton.Activated, function()
	if not closed then setFlying(not flying) end
end)

connect(noclipButton.Activated, function()
	if not closed then setNoclip(not noclip) end
end)

connect(espButton.Activated, function()
	if not closed then setESP(not espEnabled) end
end)

connect(lockButton.Activated, function()
	if not closed then setTargetLock(not targetLock) end
end)

-- 단축키
connect(UIS.InputBegan, function(input, processed)
	if closed then return end

	if input.KeyCode == Enum.KeyCode.Return
		or input.KeyCode == Enum.KeyCode.KeypadEnter then

		setTargetLock(false)
		return
	end

	if UIS:GetFocusedTextBox() then return end

	if input.KeyCode == Enum.KeyCode.BackSlash then
		panel.Visible = not panel.Visible
		draggingSlider = nil
		return
	end

	if processed then return end

	if input.KeyCode == Enum.KeyCode.F then
		setFlying(not flying)
	end
end)

local function keyDown(key)
	return UIS:IsKeyDown(key) and 1 or 0
end

-- 비행 / 벽 통과 갱신
connect(RunService.PreSimulation, function()
	if closed then return end

	if noclip then
		if getAliveRoot(player) then
			applyNoclip()
		else
			setNoclip(false)
		end
	end

	if not flying then return end

	if not flightHumanoid or flightHumanoid.Health <= 0
		or not flightRoot or not flightRoot.Parent
		or flightRoot.Parent ~= player.Character then

		stopFlying()
		return
	end

	local camera = workspace.CurrentCamera

	if not camera then
		velocity.VectorVelocity = Vector3.zero
		return
	end

	local move = Vector3.zero

	if not UIS:GetFocusedTextBox() then
		local forward =
			keyDown(Enum.KeyCode.W) - keyDown(Enum.KeyCode.S)

		local sideways =
			keyDown(Enum.KeyCode.D) - keyDown(Enum.KeyCode.A)

		local up = (
			UIS:IsKeyDown(Enum.KeyCode.Space)
			or UIS:IsKeyDown(Enum.KeyCode.E)
		) and 1 or 0

		local vertical = up - keyDown(Enum.KeyCode.Q)

		move = camera.CFrame.LookVector * forward
			+ camera.CFrame.RightVector * sideways
			+ Vector3.yAxis * vertical
	end

	if move.Magnitude > 1 then
		move = move.Unit
	end

	velocity.VectorVelocity = move * settings.FlySpeed

	local look = camera.CFrame.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)

	if horizontal.Magnitude > 0.001 then
		orientation.CFrame = CFrame.lookAt(
			Vector3.zero,
			horizontal.Unit
		)
	end
end)

-- 리스폰
local function onCharacterAdded(character)
	local humanoid = character:WaitForChild("Humanoid", 10)

	if closed then return end

	if humanoid and player.Character == character then
		applyMovementSettings()
	end
end

connect(player.CharacterAdded, onCharacterAdded)

connect(player.CharacterRemoving, function()
	setTargetLock(false)
	disconnectMovementWatchers()
	stopFlying()
	setNoclip(false)

	-- ESP / UI 표시 / 대상 선택 / 설정값은 유지
end)

if player.Character then
	task.spawn(onCharacterAdded, player.Character)
end

-- 정리
-- 콘솔에서 실행한 별도 Lua 코드까지 종료하지는 않음
local function cleanup()
	if closed then return end

	closed = true
	draggingSlider = nil

	RunService:UnbindFromRenderStep(RENDER_NAME)

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)

	setTargetLock(false)
	disconnectMovementWatchers()
	stopFlying()
	setNoclip(false)
	setESP(false)

	espFolder:Destroy()

	if environment[CLEANUP_KEY] == cleanup then
		environment[CLEANUP_KEY] = nil
	end

	if gui.Parent then
		gui:Destroy()
	end
end

environment[CLEANUP_KEY] = cleanup
connect(gui.Destroying, cleanup)

updateButtons()
writeOutput("[ready] Ragim Panel")
writeOutput("[ui] \\ 키로 패널 숨기기 / 표시")

if type(loadstring) == "function" then
	writeOutput("[lua] loadstring available")
else
	writeOutput("[lua] loadstring unavailable")
end

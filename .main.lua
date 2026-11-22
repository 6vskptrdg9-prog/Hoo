--!strict
-- سكربت واجهة وأدوات استكشاف ومراقبة لألعاب Roleplay بلغة Luau القياسية

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==========================================
-- 1. الإعدادات والمواقع القابلة للتعديل
-- ==========================================
local PresetLocations: { { name: string, position: Vector3 } } = {
	{ name = "المركز / الساحة", position = Vector3.new(0, 10, 0) },
	{ name = "المستشفى", position = Vector3.new(120, 10, -85) },
	{ name = "الشرطة", position = Vector3.new(-140, 10, 95) },
	{ name = "المطار", position = Vector3.new(260, 15, 210) },
}

local state = {
	flyEnabled = false,
	flySpeed = 60,
	walkSpeedBoost = false,
	walkSpeedValue = 32,
	jumpPowerBoost = false,
	jumpPowerValue = 90,
	espEnabled = false,
	invisibleEnabled = false,
	uiOpen = true,
}

local defaultWalkSpeed = 16
local defaultJumpPower = 50
local savedPartsTransparency: { [BasePart]: number } = {}
local espHighlights: { [Player]: Highlight } = {}
local connections: { RBXScriptConnection } = {}

-- ==========================================
-- 2. دوال مساعدة للحصول على الشخصية
-- ==========================================
local function getCharacter(): Model?
	return player.Character
end

local function getHumanoid(): Humanoid?
	local char = getCharacter()
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(): BasePart?
	local char = getCharacter()
	if not char then
		return nil
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function applyMovementStats()
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = if state.walkSpeedBoost then state.walkSpeedValue else defaultWalkSpeed
	if humanoid.UseJumpPower then
		humanoid.JumpPower = if state.jumpPowerBoost then state.jumpPowerValue else defaultJumpPower
	else
		humanoid.JumpHeight = if state.jumpPowerBoost then (state.jumpPowerValue * 0.25) else 7.2
	end
end

-- ==========================================
-- 3. نظام الطيران الحر (Fly - WASD + ارتفاع/نزول)
-- ==========================================
local flyVelocity: BodyVelocity? = nil
local flyGyro: BodyGyro? = nil

local function stopFly()
	if flyVelocity then
		flyVelocity:Destroy()
		flyVelocity = nil
	end
	if flyGyro then
		flyGyro:Destroy()
		flyGyro = nil
	end
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.PlatformStand = false
	end
end

local function startFly()
	local hrp = getRootPart()
	local humanoid = getHumanoid()
	if not hrp or not humanoid then
		return
	end

	stopFly()
	humanoid.PlatformStand = true

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
	bv.Velocity = Vector3.zero
	bv.Parent = hrp
	flyVelocity = bv

	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
	bg.P = 1e4
	bg.CFrame = hrp.CFrame
	bg.Parent = hrp
	flyGyro = bg
end

local function setFlyState(enabled: boolean)
	state.flyEnabled = enabled
	if enabled then
		startFly()
	else
		stopFly()
	end
end

local function updateFly(dt: number)
	if not state.flyEnabled then
		return
	end
	local hrp = getRootPart()
	local camera = workspace.CurrentCamera
	if not hrp or not camera then
		return
	end

	if not flyVelocity or not flyGyro or flyVelocity.Parent ~= hrp then
		startFly()
		if not flyVelocity or not flyGyro then
			return
		end
	end

	local moveDir = Vector3.zero
	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		moveDir += camera.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		moveDir -= camera.CFrame.LookVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		moveDir -= camera.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		moveDir += camera.CFrame.RightVector
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
		moveDir += Vector3.yAxis
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		moveDir -= Vector3.yAxis
	end

	if moveDir.Magnitude > 0 then
		moveDir = moveDir.Unit
	end

	flyVelocity.Velocity = moveDir * state.flySpeed
	flyGyro.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + camera.CFrame.LookVector)
	local _ = dt
end

-- ==========================================
-- 4. الانتقال السريع (Teleport إلى لاعب أو موقع)
-- ==========================================
local function teleportToPosition(targetPos: Vector3)
	local hrp = getRootPart()
	if not hrp then
		return
	end
	hrp.CFrame = CFrame.new(targetPos + Vector3.new(0, 3, 0))
end

local function findPlayerByPartialName(query: string): Player?
	local trimmed = string.lower(query:gsub("^%s+", ""):gsub("%s+$", ""))
	if trimmed == "" then
		return nil
	end

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local nameMatch = string.find(string.lower(other.Name), trimmed, 1, true) ~= nil
			local displayMatch = string.find(string.lower(other.DisplayName), trimmed, 1, true) ~= nil
			if nameMatch or displayMatch then
				return other
			end
		end
	end
	return nil
end

local function teleportToPlayerName(query: string): (boolean, string)
	local targetPlayer = findPlayerByPartialName(query)
	if not targetPlayer or not targetPlayer.Character then
		return false, "لم يتم العثور على اللاعب"
	end

	local targetHrp = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not targetHrp or not targetHrp:IsA("BasePart") then
		return false, "تعذر تحديد موقع اللاعب"
	end

	teleportToPosition(targetHrp.Position + Vector3.new(0, 0, -3))
	return true, "تم الانتقال إلى: " .. targetPlayer.DisplayName
end

-- ==========================================
-- 5. إظهار اللاعبين عبر الجدران (ESP / Highlight)
-- ==========================================
local function clearEspForPlayer(target: Player)
	local hl = espHighlights[target]
	if hl then
		hl:Destroy()
		espHighlights[target] = nil
	end
end

local function applyEspToCharacter(target: Player, char: Model)
	if not state.espEnabled or target == player then
		return
	end
	clearEspForPlayer(target)

	local highlight = Instance.new("Highlight")
	highlight.Name = "RP_ESP_Highlight"
	highlight.FillColor = Color3.fromRGB(59, 130, 246)
	highlight.OutlineColor = Color3.fromRGB(147, 197, 253)
	highlight.FillTransparency = 0.65
	highlight.OutlineTransparency = 0.1
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = char
	highlight.Parent = char

	espHighlights[target] = highlight
end

local function refreshEsp()
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			if state.espEnabled and other.Character then
				applyEspToCharacter(other, other.Character)
			else
				clearEspForPlayer(other)
			end
		end
	end
end

local function setEspState(enabled: boolean)
	state.espEnabled = enabled
	refreshEsp()
end

-- ==========================================
-- 6. إخفاء الشخصية والاسم محلياً (Invisible)
-- ==========================================
local function applyInvisibleState(enabled: boolean)
	state.invisibleEnabled = enabled
	local char = getCharacter()
	if not char then
		return
	end

	if enabled then
		savedPartsTransparency = {}
		for _, desc in ipairs(char:GetDescendants()) do
			if desc:IsA("BasePart") then
				if desc.Name ~= "HumanoidRootPart" then
					savedPartsTransparency[desc] = desc.LocalTransparencyModifier
					desc.LocalTransparencyModifier = 1
				end
			elseif desc:IsA("Decal") then
				desc.Transparency = 1
			elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
				desc.Enabled = false
			end
		end
	else
		for part, oldMod in pairs(savedPartsTransparency) do
			if part and part.Parent then
				part.LocalTransparencyModifier = oldMod
			end
		end
		savedPartsTransparency = {}
		for _, desc in ipairs(char:GetDescendants()) do
			if desc:IsA("Decal") then
				desc.Transparency = 0
			elseif desc:IsA("BillboardGui") or desc:IsA("SurfaceGui") then
				desc.Enabled = true
			end
		end
	end
end

-- ==========================================
-- 7. بناء واجهة المستخدم العصرية الداكنة (UI)
-- ==========================================
local existingGui = playerGui:FindFirstChild("BrookhavenRPToolkitUI")
if existingGui then
	existingGui:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BrookhavenRPToolkitUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local function addCorner(parent: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function addStroke(parent: GuiObject, color: Color3, thickness: number)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
end

-- زر تبديل الفتح/الإغلاق العائم
local toggleFloatBtn = Instance.new("TextButton")
toggleFloatBtn.Name = "ToggleFloatButton"
toggleFloatBtn.Size = UDim2.fromOffset(118, 36)
toggleFloatBtn.Position = UDim2.new(0, 18, 0, 18)
toggleFloatBtn.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
toggleFloatBtn.TextColor3 = Color3.fromRGB(241, 245, 249)
toggleFloatBtn.Font = Enum.Font.GothamBold
toggleFloatBtn.TextSize = 13
toggleFloatBtn.Text = "إخفاء / إظهار"
toggleFloatBtn.Parent = screenGui
addCorner(toggleFloatBtn, 10)
addStroke(toggleFloatBtn, Color3.fromRGB(51, 65, 85), 1)

-- النافذة الرئيسية الداكنة القابلة للسحب
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainWindow"
mainFrame.Size = UDim2.fromOffset(360, 470)
mainFrame.Position = UDim2.new(0.5, -180, 0.5, -235)
mainFrame.BackgroundColor3 = Color3.fromRGB(16, 19, 26)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Parent = screenGui
addCorner(mainFrame, 14)
addStroke(mainFrame, Color3.fromRGB(45, 55, 72), 1)

-- شريط العنوان للسحب
local topBar = Instance.new("Frame")
topBar.Name = "TopBar"
topBar.Size = UDim2.new(1, 0, 0, 44)
topBar.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
topBar.BorderSizePixel = 0
topBar.Parent = mainFrame
addCorner(topBar, 14)

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -90, 1, 0)
titleLabel.Position = UDim2.fromOffset(14, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(248, 250, 252)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "RP Toolkit | أدوات الرول بلاي"
titleLabel.Parent = topBar

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -38, 0.5, -14)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 38, 38)
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.Text = "X"
closeBtn.Parent = topBar
addCorner(closeBtn, 8)

-- سحب النافذة بسلاسة
do
	local dragging = false
	local dragStart = Vector2.zero
	local startPos = UDim2.new()

	topBar.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = Vector2.new(input.Position.X, input.Position.Y)
			startPos = mainFrame.Position
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
			mainFrame.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local function setUiVisible(visible: boolean)
	state.uiOpen = visible
	mainFrame.Visible = visible
end

toggleFloatBtn.MouseButton1Click:Connect(function()
	setUiVisible(not state.uiOpen)
end)

closeBtn.MouseButton1Click:Connect(function()
	setUiVisible(false)
end)

-- حاوية المحتوى القابلة للتمرير
local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Name = "ContentScroll"
scrollFrame.Size = UDim2.new(1, -16, 1, -56)
scrollFrame.Position = UDim2.fromOffset(8, 50)
scrollFrame.BackgroundTransparency = 1
scrollFrame.ScrollBarThickness = 5
scrollFrame.CanvasSize = UDim2.fromOffset(0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

local function createSectionTitle(text: string, order: number): TextLabel
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -6, 0, 22)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = Color3.fromRGB(148, 163, 184)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 12
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Text = text
	lbl.LayoutOrder = order
	lbl.Parent = scrollFrame
	return lbl
end

local function createToggleRow(labelText: string, order: number, initial: boolean, onToggle: (boolean) -> ()): TextButton
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -6, 0, 36)
	row.BackgroundColor3 = Color3.fromRGB(26, 31, 43)
	row.Text = ""
	row.AutoButtonColor = false
	row.LayoutOrder = order
	row.Parent = scrollFrame
	addCorner(row, 10)
	addStroke(row, Color3.fromRGB(45, 55, 72), 1)

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.65, -10, 1, 0)
	nameLbl.Position = UDim2.fromOffset(10, 0)
	nameLbl.BackgroundTransparency = 1
	nameLbl.TextColor3 = Color3.fromRGB(226, 232, 240)
	nameLbl.Font = Enum.Font.GothamMedium
	nameLbl.TextSize = 12
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.Text = labelText
	nameLbl.Parent = row

	local badge = Instance.new("Frame")
	badge.Size = UDim2.fromOffset(72, 24)
	badge.Position = UDim2.new(1, -80, 0.5, -12)
	badge.BackgroundColor3 = if initial then Color3.fromRGB(22, 163, 74) else Color3.fromRGB(71, 85, 105)
	badge.Parent = row
	addCorner(badge, 7)

	local badgeText = Instance.new("TextLabel")
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.BackgroundTransparency = 1
	badgeText.TextColor3 = Color3.fromRGB(255, 255, 255)
	badgeText.Font = Enum.Font.GothamBold
	badgeText.TextSize = 11
	badgeText.Text = if initial then "مفعل" else "مغلق"
	badgeText.Parent = badge

	local current = initial
	local function syncVisual()
		badge.BackgroundColor3 = if current then Color3.fromRGB(22, 163, 74) else Color3.fromRGB(71, 85, 105)
		badgeText.Text = if current then "مفعل" else "مغلق"
	end

	row.MouseButton1Click:Connect(function()
		current = not current
		syncVisual()
		onToggle(current)
	end)

	return row
end

local function createSliderRow(labelText: string, order: number, minVal: number, maxVal: number, defaultVal: number, onChanged: (number) -> ())
	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, -6, 0, 48)
	container.BackgroundColor3 = Color3.fromRGB(26, 31, 43)
	container.LayoutOrder = order
	container.Parent = scrollFrame
	addCorner(container, 10)
	addStroke(container, Color3.fromRGB(45, 55, 72), 1)

	local topLbl = Instance.new("TextLabel")
	topLbl.Size = UDim2.new(1, -20, 0, 20)
	topLbl.Position = UDim2.fromOffset(10, 4)
	topLbl.BackgroundTransparency = 1
	topLbl.TextColor3 = Color3.fromRGB(203, 213, 225)
	topLbl.Font = Enum.Font.GothamMedium
	topLbl.TextSize = 11
	topLbl.TextXAlignment = Enum.TextXAlignment.Left
	topLbl.Text = string.format("%s: %d", labelText, defaultVal)
	topLbl.Parent = container

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -20, 0, 8)
	track.Position = UDim2.fromOffset(10, 30)
	track.BackgroundColor3 = Color3.fromRGB(51, 65, 85)
	track.Parent = container
	addCorner(track, 4)

	local ratio = math.clamp((defaultVal - minVal) / (maxVal - minVal), 0, 1)
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(ratio, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(59, 130, 246)
	fill.Parent = track
	addCorner(fill, 4)

	local sliding = false

	local function updateFromX(xPos: number)
		local absPos = track.AbsolutePosition.X
		local absSize = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((xPos - absPos) / absSize, 0, 1)
		local val = math.floor(minVal + (maxVal - minVal) * alpha + 0.5)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		topLbl.Text = string.format("%s: %d", labelText, val)
		onChanged(val)
	end

	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sliding = true
			updateFromX(input.Position.X)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			updateFromX(input.Position.X)
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sliding = false
		end
	end)
end

-- ==========================================
-- 8. أقسام الميزات داخل الواجهة
-- ==========================================
createSectionTitle("1. الحركة والاستكشاف", 1)

createToggleRow("طيران حر (Fly - WASD / Space / Ctrl)", 2, false, function(active)
	setFlyState(active)
end)

createSliderRow("سرعة الطيران", 3, 20, 180, state.flySpeed, function(val)
	state.flySpeed = val
end)

createToggleRow("زيادة سرعة المشي", 4, false, function(active)
	state.walkSpeedBoost = active
	applyMovementStats()
end)

createToggleRow("زيادة قوة القفز", 5, false, function(active)
	state.jumpPowerBoost = active
	applyMovementStats()
end)

-- الانتقال إلى لاعب عبر الاسم أو جزء منه
local tpPlayerFrame = Instance.new("Frame")
tpPlayerFrame.Size = UDim2.new(1, -6, 0, 74)
tpPlayerFrame.BackgroundColor3 = Color3.fromRGB(26, 31, 43)
tpPlayerFrame.LayoutOrder = 6
tpPlayerFrame.Parent = scrollFrame
addCorner(tpPlayerFrame, 10)
addStroke(tpPlayerFrame, Color3.fromRGB(45, 55, 72), 1)

local tpInput = Instance.new("TextBox")
tpInput.Size = UDim2.new(0.66, -12, 0, 32)
tpInput.Position = UDim2.fromOffset(8, 8)
tpInput.BackgroundColor3 = Color3.fromRGB(15, 23, 42)
tpInput.TextColor3 = Color3.fromRGB(248, 250, 252)
tpInput.PlaceholderText = "اكتب اسم اللاعب أو جزء منه..."
tpInput.PlaceholderColor3 = Color3.fromRGB(100, 116, 139)
tpInput.Font = Enum.Font.Gotham
tpInput.TextSize = 12
tpInput.ClearTextOnFocus = false
tpInput.Text = ""
tpInput.Parent = tpPlayerFrame
addCorner(tpInput, 8)

local tpBtn = Instance.new("TextButton")
tpBtn.Size = UDim2.new(0.32, -6, 0, 32)
tpBtn.Position = UDim2.new(0.68, 0, 0, 8)
tpBtn.BackgroundColor3 = Color3.fromRGB(37, 99, 235)
tpBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
tpBtn.Font = Enum.Font.GothamBold
tpBtn.TextSize = 12
tpBtn.Text = "انتقال"
tpBtn.Parent = tpPlayerFrame
addCorner(tpBtn, 8)

local tpStatus = Instance.new("TextLabel")
tpStatus.Size = UDim2.new(1, -16, 0, 22)
tpStatus.Position = UDim2.fromOffset(8, 45)
tpStatus.BackgroundTransparency = 1
tpStatus.TextColor3 = Color3.fromRGB(148, 163, 184)
tpStatus.Font = Enum.Font.Gotham
tpStatus.TextSize = 11
tpStatus.TextXAlignment = Enum.TextXAlignment.Left
tpStatus.Text = "الحالة: جاهز"
tpStatus.Parent = tpPlayerFrame

tpBtn.MouseButton1Click:Connect(function()
	local ok, msg = teleportToPlayerName(tpInput.Text)
	tpStatus.Text = "الحالة: " .. msg
	tpStatus.TextColor3 = if ok then Color3.fromRGB(74, 222, 128) else Color3.fromRGB(248, 113, 113)
end)

-- قسم المراقبة والتفاعل
createSectionTitle("2. المراقبة والتفاعل", 7)

createToggleRow("إظهار اللاعبين عبر الجدران (ESP)", 8, false, function(active)
	setEspState(active)
end)

createToggleRow("إخفاء الشخصية/الاسم (Invisible)", 9, false, function(active)
	applyInvisibleState(active)
end)

-- قسم مواقع الرول بلاي
createSectionTitle("3. مواقع سريعة للـ Roleplay", 10)

for idx, loc in ipairs(PresetLocations) do
	local locBtn = Instance.new("TextButton")
	locBtn.Size = UDim2.new(1, -6, 0, 34)
	locBtn.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
	locBtn.TextColor3 = Color3.fromRGB(226, 232, 240)
	locBtn.Font = Enum.Font.GothamMedium
	locBtn.TextSize = 12
	locBtn.Text = "انتقال إلى: " .. loc.name
	locBtn.LayoutOrder = 10 + idx
	locBtn.Parent = scrollFrame
	addCorner(locBtn, 8)

	locBtn.MouseButton1Click:Connect(function()
		teleportToPosition(loc.position)
	end)
end

-- ==========================================
-- 9. ربط الأحداث وتنظيف الموارد
-- ==========================================
table.insert(connections, RunService.RenderStepped:Connect(function(dt: number)
	updateFly(dt)
end))

table.insert(connections, player.CharacterAdded:Connect(function(newChar: Model)
	stopFly()
	local hum = newChar:WaitForChild("Humanoid")
	if hum:IsA("Humanoid") then
		defaultWalkSpeed = hum.WalkSpeed
		defaultJumpPower = if hum.UseJumpPower then hum.JumpPower else 50
	end
	applyMovementStats()
	if state.flyEnabled then
		startFly()
	end
	if state.invisibleEnabled then
		applyInvisibleState(true)
	end
end))

table.insert(connections, Players.PlayerAdded:Connect(function(joined: Player)
	if joined ~= player then
		joined.CharacterAdded:Connect(function(char: Model)
			if state.espEnabled then
				applyEspToCharacter(joined, char)
			end
		end)
	end
end))

table.insert(connections, Players.PlayerRemoving:Connect(function(left: Player)
	clearEspForPlayer(left)
end))

refreshEsp()
applyMovementStats()
local _ = TweenService

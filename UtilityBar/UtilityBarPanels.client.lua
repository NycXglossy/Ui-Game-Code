--!strict
-- UtilityBarPanels.client.lua
-- Separate control panels for Mount, Size, Clone and Aura. Install beside UtilityBarActions.client.lua.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local actionEvent = playerGui:WaitForChild("UtilityBarAction") :: BindableEvent
local remoteFolder = ReplicatedStorage:WaitForChild("UtilityBarRemotes")
local execute = remoteFolder:WaitForChild("ExecuteUtility") :: RemoteFunction

local C = {
	bg=Color3.fromRGB(13,16,24), surface=Color3.fromRGB(24,29,41),
	hover=Color3.fromRGB(37,45,60), gold=Color3.fromRGB(226,194,132),
	teal=Color3.fromRGB(119,196,203), text=Color3.fromRGB(242,241,236),
	muted=Color3.fromRGB(157,164,177)
}
local function make(className: string, props: {[string]: any}, parent: Instance): Instance
	local obj=Instance.new(className)
	for k,v in pairs(props) do (obj :: any)[k]=v end
	obj.Parent=parent
	return obj
end
local gui=make("ScreenGui",{Name="UtilityControlPanels",ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=32},playerGui) :: ScreenGui
local panel=make("Frame",{Name="Panel",AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.new(.86,0,.62,0),BackgroundColor3=C.bg,BorderSizePixel=0,Visible=false},gui) :: Frame
make("UISizeConstraint",{MinSize=Vector2.new(270,230),MaxSize=Vector2.new(620,430)},panel)
make("UICorner",{CornerRadius=UDim.new(0,20)},panel)
make("UIStroke",{Color=C.gold,Transparency=.42,Thickness=1},panel)
make("UIGradient",{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(28,34,47),C.bg)},panel)
local title=make("TextLabel",{Name="Title",BackgroundTransparency=1,Position=UDim2.fromOffset(18,12),Size=UDim2.new(1,-76,0,30),Font=Enum.Font.GothamBlack,Text="UTILITY",TextColor3=C.text,TextSize=18,TextXAlignment=Enum.TextXAlignment.Left},panel) :: TextLabel
local close=make("TextButton",{Name="Close",AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,-12,0,12),Size=UDim2.fromOffset(36,32),BackgroundColor3=C.hover,BorderSizePixel=0,Font=Enum.Font.GothamBold,Text="×",TextColor3=C.text,TextSize=21},panel) :: TextButton
make("UICorner",{CornerRadius=UDim.new(0,10)},close)
local accent=make("Frame",{Position=UDim2.fromOffset(18,47),Size=UDim2.fromOffset(42,2),BackgroundColor3=C.gold,BorderSizePixel=0},panel)
make("UICorner",{CornerRadius=UDim.new(1,0)},accent)
local body=make("Frame",{Name="Body",Position=UDim2.fromOffset(16,62),Size=UDim2.new(1,-32,1,-76),BackgroundTransparency=1},panel) :: Frame
local status=make("TextLabel",{BackgroundTransparency=1,AnchorPoint=Vector2.new(.5,1),Position=UDim2.new(.5,0,1,-8),Size=UDim2.new(1,-30,0,20),Font=Enum.Font.GothamMedium,Text="",TextColor3=C.muted,TextSize=11},panel) :: TextLabel
local function rounded(obj: Instance, px: number) make("UICorner",{CornerRadius=UDim.new(0,px)},obj) end
local panelConnections: {RBXScriptConnection} = {}
local function connectPanel(signal: RBXScriptSignal, callback: (...any) -> ())
	table.insert(panelConnections, signal:Connect(callback))
end
local function clearBody()
	for _, connection in ipairs(panelConnections) do connection:Disconnect() end
	table.clear(panelConnections)
	for _, child in ipairs(body:GetChildren()) do child:Destroy() end
end
local function button(parent: Instance, label: string, tint: Color3, position: UDim2, size: UDim2): TextButton
	local b=make("TextButton",{Position=position,Size=size,BackgroundColor3=C.surface,BorderSizePixel=0,AutoButtonColor=false,Font=Enum.Font.GothamBold,Text=label,TextColor3=tint,TextSize=13},parent) :: TextButton
	rounded(b,12); make("UIStroke",{Color=tint,Transparency=.68,Thickness=1},b)
	b.MouseEnter:Connect(function() TweenService:Create(b,TweenInfo.new(.1),{BackgroundColor3=C.hover}):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(b,TweenInfo.new(.1),{BackgroundColor3=C.surface}):Play() end)
	return b
end
local busy=false
local function invoke(action: string, value: any?)
	if busy then status.Text="Please wait for the current request."; return end
	busy=true; status.Text="Applying…"
	task.spawn(function()
		local ok, success, message = pcall(function() return execute:InvokeServer(action,value) end)
		busy=false
		status.Text=if ok and typeof(message)=="string" then message else "Utility request failed. Try again."
	end)
end
local function open(name: string)
	panel.Visible=true
	playerGui:SetAttribute("UtilityActionPanelOpen",true)
	title.Text=string.upper(name) .. " CONTROL"
	status.Text=""
	clearBody()
	if name=="Aura" then
		local styleNames={"TEAL GLOW","ROYAL GOLD","TIKI TIDE"}
		local presets={"Teal Glow","Royal Gold","Tiki Tide"}
		local targetNames={"CHARACTER","TOOLS","ACCESSORIES"}
		local targets={"Character","Tools","Accessories"}
		local activeStyle,activeTarget=1,1
		local styleRow=make("Frame",{BackgroundTransparency=1,Size=UDim2.new(1,0,0,42)},body)
		local targetRow=make("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(0,46),Size=UDim2.new(1,0,0,42)},body)
		local content=make("Frame",{BackgroundTransparency=1,Position=UDim2.fromOffset(0,94),Size=UDim2.new(1,0,1,-94)},body)
		local function drawAura()
			for _,child in ipairs(styleRow:GetChildren()) do child:Destroy() end
			for _,child in ipairs(targetRow:GetChildren()) do child:Destroy() end
			for _,child in ipairs(content:GetChildren()) do child:Destroy() end
			for i,label in ipairs(styleNames) do
				local tab=button(styleRow,label,if i==activeStyle then C.gold else C.muted,UDim2.new((i-1)/3,2,0,1),UDim2.new(1/3,-4,0,38))
				 tab.TextSize=9
				tab.Activated:Connect(function() activeStyle=i; drawAura() end)
			end
			for i,label in ipairs(targetNames) do
				local tab=button(targetRow,label,if i==activeTarget then C.teal else C.muted,UDim2.new((i-1)/3,2,0,1),UDim2.new(1/3,-4,0,38))
				tab.TextSize=9
				tab.Activated:Connect(function() activeTarget=i; drawAura() end)
			end
			make("TextLabel",{BackgroundTransparency=1,Position=UDim2.new(0,0,0,0),Size=UDim2.new(1,0,0,28),Font=Enum.Font.GothamMedium,Text="Apply "..targets[activeTarget].." only",TextColor3=C.muted,TextSize=12},content)
			local apply=button(content,"APPLY "..string.upper(presets[activeStyle]),C.teal,UDim2.new(.08,0,0,36),UDim2.new(.84,0,0,42))
			apply.Activated:Connect(function() invoke("Aura",{preset=presets[activeStyle],target=targets[activeTarget]}) end)
		end
		drawAura()
	elseif name=="Size" then
		local value=1.0
		local valueLabel=make("TextLabel",{BackgroundTransparency=1,Position=UDim2.new(0,0,0,4),Size=UDim2.new(1,0,0,34),Font=Enum.Font.GothamBold,Text="1.00×",TextColor3=C.gold,TextSize=22},body) :: TextLabel
		make("TextLabel",{BackgroundTransparency=1,Position=UDim2.new(0,0,0,38),Size=UDim2.new(1,0,0,22),Font=Enum.Font.GothamMedium,Text="Character scale · 0.50× to 5.00×",TextColor3=C.muted,TextSize=11},body)
		local track=make("Frame",{Position=UDim2.new(.08,0,0,91),Size=UDim2.new(.84,0,0,10),BackgroundColor3=C.hover,BorderSizePixel=0},body) :: Frame
		rounded(track,8)
		local fill=make("Frame",{Size=UDim2.new((1-.5)/4.5,0,1,0),BackgroundColor3=C.teal,BorderSizePixel=0},track) :: Frame
		rounded(fill,8)
		local knob=make("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.new((1-.5)/4.5,0,.5,0),Size=UDim2.fromOffset(22,22),BackgroundColor3=C.gold,BorderSizePixel=0},track) :: Frame
		rounded(knob,11); make("UIStroke",{Color=C.bg,Thickness=2},knob)
		local dragging=false
		local function setFromX(x: number)
			local alpha=math.clamp((x-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1)
			value=math.floor((.5+alpha*4.5)*100+.5)/100
			fill.Size=UDim2.new(alpha,0,1,0); knob.Position=UDim2.new(alpha,0,.5,0)
			valueLabel.Text=string.format("%.2f×",value)
		end
		track.InputBegan:Connect(function(input) if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=true; setFromX(input.Position.X) end end)
		connectPanel(UserInputService.InputChanged, function(input) if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then setFromX(input.Position.X) end end)
		connectPanel(UserInputService.InputEnded, function(input) if dragging and (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch) then dragging=false end end)
		local apply=button(body,"APPLY SIZE",C.teal,UDim2.new(.08,0,0,136),UDim2.new(.84,0,0,46))
		apply.Activated:Connect(function() invoke("Size",value) end)
		local reset=button(body,"RESET TO 100%",C.gold,UDim2.new(.08,0,0,190),UDim2.new(.84,0,0,38))
		reset.Activated:Connect(function() value=1; valueLabel.Text="1.00×"; local resetAlpha=(1-.5)/4.5; fill.Size=UDim2.new(resetAlpha,0,1,0); knob.Position=UDim2.new(resetAlpha,0,.5,0); invoke("Size",1) end)
	elseif name=="Mount" then
		make("TextLabel",{BackgroundTransparency=1,Position=UDim2.new(.05,0,.12,0),Size=UDim2.new(.9,0,0,60),Font=Enum.Font.GothamMedium,Text="Equip or unequip your available mount. A Mount Tool must be installed in your inventory.",TextWrapped=true,TextColor3=C.muted,TextSize=12},body)
		local act=button(body,"EQUIP / UNEQUIP MOUNT",C.teal,UDim2.new(.08,0,.52,0),UDim2.new(.84,0,0,52))
		act.Activated:Connect(function() invoke("Mount") end)
	elseif name=="Clone" then
		make("TextLabel",{BackgroundTransparency=1,Position=UDim2.new(.05,0,.12,0),Size=UDim2.new(.9,0,0,60),Font=Enum.Font.GothamMedium,Text="Create a temporary, non-interactive visual copy beside your character. It disappears after 12 seconds.",TextWrapped=true,TextColor3=C.muted,TextSize=12},body)
		local act=button(body,"CREATE CLONE",C.gold,UDim2.new(.08,0,.52,0),UDim2.new(.84,0,0,52))
		act.Activated:Connect(function() invoke("Clone") end)
	end
end
local function closePanel()
	panel.Visible=false
	playerGui:SetAttribute("UtilityActionPanelOpen",false)
end
close.Activated:Connect(closePanel)
actionEvent.Event:Connect(function(actionName: string)
	if actionName=="Mount" or actionName=="Size" or actionName=="Clone" or actionName=="Aura" then open(actionName) end
end)
gui.Destroying:Connect(function() playerGui:SetAttribute("UtilityActionPanelOpen",false) end)
print("[Utility Bar] Separate Mount, Size, Clone and three-style Aura panels ready.")

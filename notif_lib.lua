--[[ Minimal self-contained notifications ]]
local NotificationLibrary = {}
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local holder = Instance.new("ScreenGui")
holder.Name = "AutoPianoNotifs"
holder.ResetOnSpawn = false
pcall(function() holder.Parent = CoreGui end)

local list = Instance.new("Frame")
list.BackgroundTransparency = 1
list.Size = UDim2.new(0, 300, 1, -40)
list.Position = UDim2.new(1, -320, 0, 20)
list.Parent = holder

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Parent = list

local colors = {
    Success = Color3.fromRGB(46, 204, 113),
    Error = Color3.fromRGB(231, 76, 60),
    Info = Color3.fromRGB(52, 152, 219),
    Warning = Color3.fromRGB(241, 196, 15),
}

function NotificationLibrary:SendNotification(title, text, duration)
    duration = duration or 3
    local card = Instance.new("Frame")
    card.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
    card.Size = UDim2.new(1, 0, 0, 0)
    card.ClipsDescendants = true
    card.Parent = list
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(0, 4, 1, 0)
    bar.BorderSizePixel = 0
    bar.BackgroundColor3 = colors[title] or colors.Info
    bar.Parent = card

    local t = Instance.new("TextLabel")
    t.BackgroundTransparency = 1
    t.Position = UDim2.new(0, 12, 0, 8)
    t.Size = UDim2.new(1, -20, 0, 18)
    t.Font = Enum.Font.GothamBold
    t.TextSize = 14
    t.TextColor3 = Color3.fromRGB(255, 255, 255)
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.Text = tostring(title or "Info")
    t.Parent = card

    local b = Instance.new("TextLabel")
    b.BackgroundTransparency = 1
    b.Position = UDim2.new(0, 12, 0, 28)
    b.Size = UDim2.new(1, -20, 0, 20)
    b.Font = Enum.Font.Gotham
    b.TextSize = 13
    b.TextColor3 = Color3.fromRGB(190, 190, 200)
    b.TextXAlignment = Enum.TextXAlignment.Left
    b.Text = tostring(text or "")
    b.Parent = card

    TweenService:Create(card, TweenInfo.new(0.2), {Size = UDim2.new(1, 0, 0, 56)}):Play()
    task.delay(duration, function()
        pcall(function()
            local tw = TweenService:Create(card, TweenInfo.new(0.15), {Size = UDim2.new(1, 0, 0, 0)})
            tw:Play()
            tw.Completed:Wait()
            card:Destroy()
        end)
    end)
end

return NotificationLibrary

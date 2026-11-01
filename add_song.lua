--[[ AutoPiano - add_song.lua (optional)
     Dán script sheet + đặt tên + chọn mục -> lưu vào AUTOPIANO_CUSTOM_SONGS/{name}.txt
     Mục mặc định: custom. Chọn một mục có sẵn, hoặc gõ mục mới (nhiều mục: cách nhau bằng dấu phẩy).
     Mục lưu trong _categories.txt (dòng "name|cat1,cat2") và header --CAT: trong file. ]]

local DIR = "AUTOPIANO_CUSTOM_SONGS"
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")

local function notify(kind, msg)
    local n = _G.AP_Notif
    if n and n.SendNotification then n:SendNotification(kind, msg, 3) else print(kind, msg) end
end

if type(writefile) ~= "function" or type(makefolder) ~= "function" or type(isfolder) ~= "function" then
    notify("Error", "Executor has no file system support")
    return
end

if _G.__AP_ADDSONG_GUI then pcall(function() _G.__AP_ADDSONG_GUI:Destroy() end) end

local C = {
    bg = Color3.fromRGB(18, 18, 24), panel = Color3.fromRGB(28, 28, 38), item = Color3.fromRGB(36, 36, 50),
    text = Color3.fromRGB(235, 235, 245), muted = Color3.fromRGB(150, 150, 172),
    accent = Color3.fromRGB(255, 182, 208), accentText = Color3.fromRGB(40, 24, 32),
}

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o) new("UICorner", { CornerRadius = UDim.new(0, 8) }, o) end
local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

-- mục có sẵn: từ auto.lua, thêm "custom" (mặc định) lên đầu
local categories = { "custom" }
if _G.AP_GetCategories then
    local ok, list = pcall(_G.AP_GetCategories)
    if ok and type(list) == "table" then categories = list end
end

local gui = Instance.new("ScreenGui")
gui.Name = "APAddSong"
gui.ResetOnSpawn = false
gui.DisplayOrder = 950
local ok = pcall(function() gui.Parent = CoreGui end)
if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
_G.__AP_ADDSONG_GUI = gui

local main = new("Frame", {
    Size = UDim2.new(0, 420, 0, 392), Position = UDim2.new(0.5, -210, 0.5, -196),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true, Draggable = true,
}, gui)
corner(main)
new("UIStroke", { Color = C.accent, Thickness = 1, Transparency = 0.55 }, main)

new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(1, -90, 0, 24),
    Text = "Add Song", Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.accent,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)
local closeBtn = new("TextButton", {
    Position = UDim2.new(1, -74, 0, 8), Size = UDim2.new(0, 62, 0, 24), BackgroundColor3 = C.panel,
    BorderSizePixel = 0, Text = "Close", Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
}, main)
corner(closeBtn)
closeBtn.Activated:Connect(function() gui:Destroy() end)

local function box(y, h, placeholder, multi)
    local b = new("TextBox", {
        Position = UDim2.new(0, 14, 0, y), Size = UDim2.new(1, -28, 0, h),
        BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "",
        PlaceholderText = placeholder, PlaceholderColor3 = C.muted,
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = C.text,
        ClearTextOnFocus = false, MultiLine = multi or false, TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = multi and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
        ClipsDescendants = true,
    }, main)
    corner(b)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6) }, b)
    return b
end

local nameBox = box(40, 30, "Song name")

-- chọn mục (mặc định custom)
new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 76), Size = UDim2.new(1, -28, 0, 16),
    Text = "Category (default: custom)", Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = C.muted,
    TextXAlignment = Enum.TextXAlignment.Left,
}, main)
local chipBar = new("ScrollingFrame", {
    Position = UDim2.new(0, 14, 0, 94), Size = UDim2.new(1, -28, 0, 28),
    BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0,
    CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
    ScrollingDirection = Enum.ScrollingDirection.X,
}, main)
new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
}, chipBar)

local chosen = "custom"
local chips = {}
local function paintChips()
    for name, chip in pairs(chips) do
        local active = (name == chosen)
        chip.BackgroundColor3 = active and C.accent or C.item
        chip.TextColor3 = active and C.accentText or C.text
    end
end
for _, name in ipairs(categories) do
    local chip = new("TextButton", {
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
        BackgroundColor3 = C.item, BorderSizePixel = 0, Text = name,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = C.text,
    }, chipBar)
    corner(chip)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, chip)
    chips[name] = chip
    chip.Activated:Connect(function()
        chosen = name
        paintChips()
    end)
end
paintChips()

local newCatBox = box(128, 30, "Or type a new category (overrides the choice above)")
local scriptBox = box(166, 168, "Paste sheet script here (keypress / rest / finishedSong)", true)

local saveBtn = new("TextButton", {
    Position = UDim2.new(0, 14, 1, -48), Size = UDim2.new(1, -28, 0, 34),
    BackgroundColor3 = C.accent, BorderSizePixel = 0, Text = "Save",
    Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.accentText,
}, main)
corner(saveBtn)

saveBtn.Activated:Connect(function()
    local name = trim((trim(nameBox.Text):gsub("[^%w%-_ ]", "")))
    local script = scriptBox.Text
    if name == "" then notify("Error", "Enter a song name") return end
    if #script <= 10 then notify("Error", "Paste the sheet script first") return end

    -- mục: ô gõ mới (nếu có) > chip đang chọn; "custom" = mặc định, không cần ghi header
    local cats = {}
    local typed = trim(newCatBox.Text)
    if typed ~= "" then
        for raw in typed:gmatch("[^,]+") do
            local c = trim(raw):lower()
            if c ~= "" then cats[#cats + 1] = c end
        end
    elseif chosen ~= "custom" then
        cats[1] = chosen
    end

    local okSave, err = pcall(function()
        if not isfolder(DIR) then makefolder(DIR) end

        local body = script
        if #cats > 0 and not body:match("^%-%-CAT:") then
            body = "--CAT:" .. table.concat(cats, ",") .. "\n" .. body
        end
        writefile(DIR .. "/" .. name .. ".txt", body)

        -- _categories.txt : "name|cat1,cat2"
        local catPath = DIR .. "/_categories.txt"
        local lines = {}
        if type(isfile) == "function" and isfile(catPath) then
            for line in tostring(readfile(catPath)):gmatch("[^\r\n]+") do
                local n = line:match("^(.-)|")
                if n ~= name then lines[#lines + 1] = line end
            end
        end
        if #cats > 0 then lines[#lines + 1] = name .. "|" .. table.concat(cats, ",") end
        writefile(catPath, table.concat(lines, "\n"))
    end)

    if okSave then
        notify("Success", "Saved: " .. name .. " (" .. (#cats > 0 and table.concat(cats, ", ") or "custom") .. ")")
        if _G.AP_RefreshSongs then pcall(_G.AP_RefreshSongs) end
        gui:Destroy()
    else
        warn("[AutoPiano] add_song: " .. tostring(err))
        notify("Error", "Could not save song")
    end
end)

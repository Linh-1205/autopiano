--[[ AutoPiano - add_song.lua (optional)
     Dán script sheet + đặt tên + category -> lưu vào AUTOPIANO_CUSTOM_SONGS/{name}.txt
     Category lưu trong _categories.txt (dòng "name|cat1,cat2") và header --CAT: trong file. ]]

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
    bg = Color3.fromRGB(18, 18, 24), panel = Color3.fromRGB(28, 28, 38),
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

local gui = Instance.new("ScreenGui")
gui.Name = "APAddSong"
gui.ResetOnSpawn = false
gui.DisplayOrder = 950
local ok = pcall(function() gui.Parent = CoreGui end)
if not ok then gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end
_G.__AP_ADDSONG_GUI = gui

local main = new("Frame", {
    Size = UDim2.new(0, 420, 0, 360), Position = UDim2.new(0.5, -210, 0.5, -180),
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

local nameBox = box(42, 30, "Song name")
local catBox = box(78, 30, "Category (comma separated, optional)")
local scriptBox = box(114, 190, "Paste sheet script here (keypress / rest / finishedSong)", true)

local saveBtn = new("TextButton", {
    Position = UDim2.new(0, 14, 1, -48), Size = UDim2.new(1, -28, 0, 34),
    BackgroundColor3 = C.accent, BorderSizePixel = 0, Text = "Save",
    Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = C.accentText,
}, main)
corner(saveBtn)

local function trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

saveBtn.Activated:Connect(function()
    local name = trim(nameBox.Text):gsub("[^%w%-_ ]", "")
    name = trim(name)
    local script = scriptBox.Text
    if name == "" then notify("Error", "Enter a song name") return end
    if #script <= 10 then notify("Error", "Paste the sheet script first") return end

    local cats = {}
    for raw in trim(catBox.Text):gmatch("[^,]+") do
        local c = trim(raw):lower()
        if c ~= "" then cats[#cats + 1] = c end
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
        notify("Success", "Saved: " .. name)
        if _G.AP_RefreshSongs then pcall(_G.AP_RefreshSongs) end
        gui:Destroy()
    else
        warn("[AutoPiano] add_song: " .. tostring(err))
        notify("Error", "Could not save song")
    end
end)

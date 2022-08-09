-- intialize var
local paletteLUT = {
    [0] = "white",
    [1] = "orange",
    [2] = "magenta",
    [3] = "lightBlue",
    [4] = "yellow",
    [5] = "lime",
    [6] = "pink",
    [7] = "gray",
    [8] = "lightGray",
    [9] = "cyan",
    [10] = "purple",
    [11] = "blue",
    [12] = "brown",
    [13] = "green",
    [14] = "red",
    [15] = "black"
}

term.setCursorPos(1, 1)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()

print("Terminal Palette Editor: ")
term.setCursorPos(1, 3)

-- get current palette colors
local currentPalette = {}
for i = 0, 15 do
    currentPalette[i] = colors.packRGB(term.getPaletteColor(2 ^ i))
end

for i = 0, 15 do
    local _, cy = term.getCursorPos()
    local color = colors[paletteLUT[i]]
    local label = paletteLUT[i] .. ": "
    label = string.upper(string.sub(label, 1, 1)) .. string.sub(label, 2)
    local hex = ("%06X"):format(currentPalette[i])

    term.setCursorPos(1, cy)
    term.write(label)
    term.setCursorPos(12, cy)
    term.write(hex)
    term.setBackgroundColor(color)
    term.setTextColor(colors.white)
    term.setCursorPos(20, cy)
    term.write(" gYw ")
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(1, cy + 1)
end

term.setCursorPos(2, select(2, term.getCursorPos())+1)
term.setBackgroundColor(colors.red)
term.write(" Save ")
term.setCursorPos(12, select(2, term.getCursorPos()))
term.write(" Exit ")
term.setBackgroundColor(colors.black)

local function savePalette()
    local palette = {}
    for i = 0, 15 do
        palette[paletteLUT[i]] = colors.packRGB(term.getPaletteColor(2 ^ i))
    end
    local file = fs.open("palette.txt", "w")
    file.write(textutils.serialize(palette))
    file.close()
end

local function eventHandler(ev)
    if ev[1] == "key" and ev[2] == keys.q then
        term.clear()
        term.setCursorPos(1, 1)
        error("", 0)
    elseif ev[1] == "mouse_click" then
        local x, y = ev[3], ev[4]
        if x >= 12 and x <= 18 and y >= 3 and y <= 18 then
            term.setCursorPos(12, y)
            term.write("      ")
            term.setCursorPos(12, y)
            local code = read()
            local newColor = tonumber(code, 16)
            if newColor then
                term.setPaletteColor(2 ^ (y - 3), newColor)
                term.setCursorPos(12, y)
                term.write(code:upper())
                currentPalette[y - 3] = colors.packRGB(term.getPaletteColor(2 ^ (y - 3)))
            else
                term.setCursorPos(12, y)
                term.write(("%06X"):format(currentPalette[(y-3)]))
            end
        elseif x >= 2 and x <= 8 and y == 20 then
            term.setCursorPos(2, 20)
            term.setBackgroundColor(colors.green)
            term.write(" Save ")
            savePalette()
            sleep(0.1)
            term.setCursorPos(2, 20)
            term.setBackgroundColor(colors.red)
            term.write(" Save ")
            term.setBackgroundColor(colors.black)
        elseif x >= 12 and x <= 18 and y == 20 then
            term.clear()
            term.setCursorPos(1,1)
            error("",0)
        end
    end
end

while true do
    local ev = { os.pullEvent() }
    eventHandler(ev)
end


local resx, resy = term.getSize()
local docWin = window.create(term.current(),1,1,resx,resy-2)
local infobar = window.create(term.current(),1,resy-1,resx,2)
-- term.redirect(infobar)

local toggleMods = true

---@diagnostic disable-next-line: undefined-global
if periphemu then
  -- this is on craftospc
  toggleMods = false
end

local api = {}
api.selectedFG = '0'
api.selectedBG = 'f'

api.defaultFG = '0'
api.defaultBG = 'f'

api.hudFG = colors.white -- lightest color
api.hudBG = colors.black -- darkest color

api.PAPER_WIDTH = 25
api.PAPER_HEIGHT = 21

local offset = {1,1} -- what position on the document the top left is in
local selPos = {1,1} -- where in the visable region the cursor has selected

local INTERNAL_FORMAT_EXTENSION = "giim"

local activeLayer = 1

local document = {}

local furthestColorLUT = {} -- input a color char, get a color char of the color furthest from it

local undoBuffer = {}
-- each element in the undoBuffer is either a set, or a multi
-- {0, x, y, blit[3]}
-- {1, amount} -- when this is undone, automatically undo amount more

-- ensures every given index in the chain exists
local function checkExists(table, ...)
  local t = table
  for _, val in ipairs({...}) do
    t = t[val]
    if not t then
      return false
    end
  end
  return true
end

local eventLookup = {}

local function callEventHandlers(name, ...)
  if eventLookup[name] then
    for i,f in pairs(eventLookup[name]) do
      f(...) -- call each event handler for this type
    end
  end
end

local function renderDocument()
  docWin.setVisible(false)
  docWin.clear()
  for y = 2, resy-2 do
    for x = 2, resx do
      docWin.setCursorPos(x,y)
      local xindex = offset[1]+x-2
      local yindex = offset[2]+y-2
      if checkExists(document, "im", activeLayer, yindex, xindex) then
        -- this co-ordinate has a character defined
        local ch, fg, bg = table.unpack(document.im[activeLayer][yindex][xindex])
        docWin.blit(ch, fg, bg or api.defaultBG)
      else
        docWin.blit(" ",api.defaultFG,api.defaultBG)
      end
    end
  end
  -- generate the horizontal ruler
  local hozruler = ""
  local sideString = string.rep(" ", math.floor((api.PAPER_WIDTH-2-3)/2))
  -- possible bug for if paper width is even
  for x = math.ceil(offset[1]/api.PAPER_WIDTH)-1,
  math.ceil((offset[1]+resx)/api.PAPER_WIDTH) do
    hozruler = hozruler..
    string.format("|"..sideString.."%3u"..sideString.."|", x)
  end
  docWin.setBackgroundColor(api.hudBG)
  docWin.setTextColor(api.hudFG)
  docWin.setCursorPos(2,1)
  docWin.write(hozruler:sub(((offset[1]-1)%api.PAPER_WIDTH)+1+api.PAPER_WIDTH))

  -- generate the vertical ruler
  local verruler = ""
  local vertString = string.rep(" ", math.floor((api.PAPER_HEIGHT-2-3)/2))
  for x = math.ceil(offset[2]/api.PAPER_HEIGHT)-1,
  math.ceil((offset[2]+resy)/api.PAPER_HEIGHT) do
    verruler = verruler..
    string.format("-"..vertString.."%3u"..vertString.."-", x)
  end
  local sindex = ((offset[2]-1)%api.PAPER_HEIGHT)+1+api.PAPER_HEIGHT
  for y = 2, resy do
    docWin.setCursorPos(1,y)
    docWin.write(verruler:sub(sindex,sindex))
    sindex = sindex + 1
  end

  callEventHandlers("render") -- call all registered event handlers

  -- now add markers to the rulers to show where the cursor currently is
  -- do it in this order so the cursor markers are always visable
  local x, y = table.unpack(selPos)
  docWin.setCursorPos(1,y+1)
  docWin.write("\16")
  docWin.setCursorPos(x+1,1)
  docWin.write("\31")


  docWin.setVisible(true)
end

local function calcDocumentPos()
  return offset[1]+selPos[1]-1,offset[2]+selPos[2]-1
end

local function renderAll()
  renderDocument()
  local x, y = calcDocumentPos()
  local fg
  if checkExists(document, "im", activeLayer, y, x, 2) then
    fg = document.im[activeLayer][y][x][2]
  else
    fg = api.defaultFG
  end
  term.setTextColor(2^tonumber(fg,16))
  term.setBackgroundColor(api.hudBG)
  term.setCursorPos(selPos[1]+1,selPos[2]+1)
  term.setCursorBlink(true)
end

local function setChar(x,y,char)
  document.im = document.im or {}
  document.im[activeLayer] = document.im[activeLayer] or {}
  document.im[activeLayer][y] = document.im[activeLayer][y] or {}
  undoBuffer[#undoBuffer+1] = {0, x, y, document.im[activeLayer][y][x]} -- this works because the original blit table is not being modified
  if char == nil then
    document.im[activeLayer][y][x] = nil
  else
    document.im[activeLayer][y][x] = {char, api.selectedFG, api.selectedBG} -- see, it's just getting replaced.
  end
end

local function offsetOffset(dx,dy)
  offset = {offset[1]+dx,offset[2]+dy}
  offset = {math.max(offset[1],1),math.max(offset[2],1)}
end

local function offsetSelect(dx,dy)
  selPos = {selPos[1]+dx,selPos[2]+dy}
  if selPos[1] < 2 then
    -- this is to the left of the document
    offsetOffset(selPos[1]-1,0) -- attempt to move the entire document by that amount
  elseif selPos[1] > resx-2 then
    offsetOffset(selPos[1]-(resx-2),0)
  end
  if selPos[2] < 2 then
    offsetOffset(0,selPos[2]-1)
  elseif selPos[2] > resy-4 then
    offsetOffset(0,selPos[2]-(resy-4))
  end
  selPos = {math.max(selPos[1],1),math.max(selPos[2],1)}
  selPos = {math.min(selPos[1],resx-2),math.min(selPos[2],resy-4)}
end

-- add a special entry to the undo buffer, that signifies the next n steps should be undone.
local function addMultiUndo(n)
  undoBuffer[#undoBuffer+1] = {1, n} -- indicate this is a group undo
end

-- set the character at the current document position
local function writeChar(char)
  local x, y = calcDocumentPos()
  setChar(x,y,char)
end

-- set the info bar to something specific
local function setFooter(t)
  infobar.setBackgroundColor(api.hudBG)
  infobar.setTextColor(api.hudFG)
  infobar.clear()
  infobar.setCursorPos(1,1)
  infobar.write(t)
end

-- set the info bar to the default
local function resetFooter()
  setFooter("GIIM v1.0.2 CTRL-H for help")
end

-- get input from the info bar, displaying string t
local function getFooter(t)
  setFooter(t)
  return io.read()
end

-- get a boolean from the info bar, displaying string t
local function getFooterConfirm(t)
  return getFooter(t):lower():sub(1,1) == "y"
end

-- get input from the info bar (enter is pushed without inputting anything returns default)
-- t should be  string.format string that takes a single string (def)
local function getFooterDefault(t,def)
  local input = getFooter(string.format(t,def))
  if input == "" then
    return def
  end
  return input
end

local function getDocumentSize()
  local maxx = 0
  local maxy = 0
  local maxlayer = 0
  document.im = document.im or {}
  for l, layer in pairs(document.im) do
    maxlayer = math.max(maxlayer, l)
    for y,row in pairs(layer) do
      for x, column in pairs(row) do
        maxx = math.max(maxx, x)
      end
      maxy = math.max(maxy,y)
    end
  end
  return {maxx, maxy, maxlayer}
end

local function cropDocument(maxx,maxy,maxlayer)
  document.im = document.im or {}
  for l, layer in pairs(document.im) do
    if l > maxlayer then
      document.im[l] = nil
      layer = {}
    end
    for y,row in pairs(layer) do
      if y > maxy then
        document.im[l][y] = nil
        row = {} -- to satisfy the other for loop
      end
      for x, column in pairs(row) do
        if x > maxx then
          row[x] = nil
        end
      end
    end
  end
  document.pal = document.pal or {}
  for l, layer in pairs(document.pal) do
    if type(l) == "number" and l > maxlayer then
      document.pal[l] = nil
    end
  end
end

-- applies a palette based on the current layer
-- sets hudFG, hudBG, and furthestColorLUT
local function applyPalette()
  local brightest = 0
  local darkest = 255
  local function _ca(c)
    local r,g,b = colors.unpackRGB(c)
    return 255 * ((r+g+b)/3)
  end
  document.pal = document.pal or {}
  local colorsUsed = {}
  for i = 0, 15 do
    local colorUsed
    if document.pal[activeLayer] and document.pal[activeLayer][i] then
      -- set the palette based off the active layer palette
      colorUsed = document.pal[activeLayer][i]
    elseif document.pal.def and document.pal.def[i] then
      -- fall back to the default document palette
      colorUsed = document.pal.def[i]
    else
      -- fall back to the 16 default colors
      colorUsed = colors.packRGB(term.nativePaletteColor(2^i))
    end
    docWin.setPaletteColor(2^i, colorUsed)
    local colorAverage = _ca(colorUsed)
    if colorAverage < darkest then
      darkest = colorAverage
      api.hudBG = 2^i
    end
    if colorAverage > brightest then
      brightest = colorAverage
      api.hudFG = 2^i
    end
    colorsUsed[i] = colorUsed
  end
  local function _cl(c) -- luminance
    local r,g,b = colors.unpackRGB(c)
    return (0.2126*r + 0.7152*g + 0.0722*b)
  end
  for a = 0, 15 do -- this could absolutely be optimized
    local ac = ("%x"):format(a)
    local largestDiff = 0
    furthestColorLUT[ac] = furthestColorLUT[ac] or "0"
    local aAve = _cl(colorsUsed[a])
    for b = 0, 15 do -- really, nested loops??
      -- calculate which b color is furthest from a
      local bc = ("%x"):format(b)
      local diff = math.abs(_cl(colorsUsed[b]) - aAve) -- redundant calculations
      if diff > largestDiff then
        -- these colors are further apart
        furthestColorLUT[ac] = bc
        largestDiff = diff
      end
    end
  end
  term.setBackgroundColor(api.hudBG)
  term.clear()
  resetFooter()
end

-- move the {1,1} position of the document by dx,dy
-- this will CLIP anything that goes off the left and top sides (< 1)
local function moveDocument(dx,dy)
  local newDocument = {im={}}
  for k,v in pairs(document) do
    if k ~= "im" then
      -- copy over all data that's not the image
      newDocument[k] = v
    end
  end
  document.im = document.im or {}
  for l, layer in pairs(document.im) do
    newDocument.im[l] = {}
    for y,row in pairs(layer) do
      if y+dy >= 1 then
        newDocument.im[l][y+dy] = {}
        for x, column in pairs(row) do
          if x+dx >= 1 then
            newDocument.im[l][y+dy][x+dx] = column
          end
        end
      end
    end
  end
  document = newDocument

end

local function undo()
  local undoinfo = undoBuffer[#undoBuffer]
  if undoinfo == nil then return end
  undoBuffer[#undoBuffer] = nil
  if undoinfo[1] == 0 then
    -- set
    local x = undoinfo[2]
    local y = undoinfo[3]
    document.im = document.im or {}
    document.im[activeLayer] = document.im[activeLayer] or {}
    document.im[activeLayer][y] = document.im[activeLayer][y] or {}
    document.im[activeLayer][y][x] = undoinfo[4]

  elseif undoinfo[1] == 1 then
    -- series
    for i = 1, undoinfo[2] do
      undo()
    end
  else
    error("Invalid entry in undo table")
  end
end

local function loadbimg(t)
  local function _convBimgPalette(p)
    if p == nil then return end
    local np = {}
    for k,v in pairs(p) do
      np[k] = v[1]
    end
    return np
  end
  -- t is loaded bimg table
  if type(t) == "table" then
    document = {im={},pal={}}
    document.pal.def = _convBimgPalette(t.palette)
    for fn, frame in ipairs(t) do
      document.im[fn] = {}
      document.pal[fn] = _convBimgPalette(frame.palette)
      for y, line in pairs(frame) do
        document.im[fn][y] = {}
        for x = 1, string.len(line[1]) do
          document.im[fn][y][x] = {line[1]:sub(x,x), line[2]:sub(x,x), line[3]:sub(x,x)}
        end
      end
    end
    applyPalette()
  else
    setFooter("Invalid BIMG file")
  end
end
-- returns a bimg compatible blit table
local function savebimg()
  local function _convBimgPalette(p)
    if p == nil then return end
    local np = {}
    for k,v in pairs(p) do
      np[k] = {v}
    end
    return np
  end
  local maxx, maxy, maxlayer = table.unpack(getDocumentSize())
  local bimg = {}
  document.pal = document.pal or {}
  bimg.palette = _convBimgPalette(document.pal.def)
  for layer = 1, maxlayer do
    bimg[layer] = {}
    bimg[layer].palette = _convBimgPalette(document.pal[layer])
    for y = 1, maxy do
      bimg[layer][y] = {{},{},{}}
      for x = 1, maxx do
        bimg[layer][y][1][x] = document.im[layer][y][x][1]
        bimg[layer][y][2][x] = document.im[layer][y][x][2]
        bimg[layer][y][3][x] = document.im[layer][y][x][3]
      end
      bimg[layer][y][1] = table.concat(bimg[layer][y][1])
      bimg[layer][y][2] = table.concat(bimg[layer][y][2])
      bimg[layer][y][3] = table.concat(bimg[layer][y][3])
    end
  end
  return bimg
end

-- takes a file handle
local function loadbbf(f)
  local function _convBbfPalette(p)
    if p == nil then return end
    local np = {}
    for k,v in pairs(p) do
      np[tonumber(k)] = v
    end
    return np
  end
  local magic = f.readLine()
  if magic == "BLBFOR1" then
    local width = tonumber(f.readLine())
    local height = tonumber(f.readLine())
    local frames = tonumber(f.readLine())
    local creationDate = tonumber(f.readLine())
    local metadata = textutils.unserialiseJSON(f.readLine())
    document = {im={},pal={}}
    if metadata.palette and #metadata.palette == 1 then
      -- there's only a single palette
      document.pal.def = _convBbfPalette(metadata.palette[1])
    end
    for frame = 1, frames do
      document.im[frame] = {}
      if metadata.palette and metadata.palette[frame] then
        document.pal[frame] = _convBbfPalette(metadata.palette[frame])
      end
      for y = 1, height do
        document.im[frame][y] = {}
        for x = 1, width do
          local char = f.read(1)
          local byte = string.byte(f.read(1))
          local fg = string.format("%x", bit32.rshift(byte, 4))
          local bg = string.format("%x", bit32.band(byte, 0xF))
          document.im[frame][y][x] = {char,fg,bg}
        end
      end
    end
    applyPalette()
  else
    setFooter("Invalid bbf file")
  end
end

-- returns a string
local function savebbf()
  local file = {"BLBFOR1\n"}
  local function add(...)
    for k,v in pairs({...}) do
      file[#file+1] = v
    end
  end
  local width, height, frames = table.unpack(getDocumentSize())
  add(width, "\n", height, "\n", frames, "\n")
  add(os.epoch("utc"), "\n")
  local palette = {}
  for k,v in ipairs(document.pal) do
    palette[k] = {}
    for k2,v2 in pairs(v) do
      palette[k][tostring(k2)] = v2
    end
  end
  palette[1] = document.pal.def or palette[1] -- make sure default palette is first
  add(textutils.serializeJSON({palette=palette}),"\n")
  for frame = 1, frames do
    for y = 1, height do
      for x = 1, width do
        local blitTable
        if checkExists(document, "im", frame, y, x) then
          blitTable = document.im[frame][y][x]
        else
          blitTable = {" ", api.defaultFG, api.defaultBG}
        end
        add(blitTable[1])
        local byte = bit32.lshift(tonumber(blitTable[2],16),4) + tonumber(blitTable[3],16)
        add(string.char(byte))
      end
    end
  end
  return table.concat(file)
end

local function openFile(fn)
  local f = fs.open(fn, "rb")
  if f then
    if fn:sub(-4):lower() == "bimg" then
      local bt = textutils.unserialise(f.readAll())
      if bt then
        loadbimg(bt)
        resetFooter()
        undoBuffer = {}
      else
        setFooter("Invalid bimg file")
      end
    elseif fn:sub(-INTERNAL_FORMAT_EXTENSION:len()) == INTERNAL_FORMAT_EXTENSION then
      local bt = textutils.unserialise(f.readAll())
      if bt then
        document = bt
        resetFooter()
        undoBuffer = {}
      else
        setFooter("Invalid file")
      end
    elseif fn:sub(-3):lower() == "bbf" then
      loadbbf(f)
      undoBuffer = {}
    else
      setFooter("Unsupported format")
    end
    f.close()
  else
    setFooter("Unable to open file")
  end

end

local function saveFile(fn)
  local f = fs.open(fn, "wb")
  if f then
    if fn:sub(-4):lower() == "bimg" then
      -- TODO implement bimg saving
      f.write(textutils.serialize(savebimg(),{compact=true}))
      setFooter("Saved file")
    elseif fn:sub(-INTERNAL_FORMAT_EXTENSION:len()) == INTERNAL_FORMAT_EXTENSION then
      f.write(textutils.serialise(document,{compact=true}))
      setFooter("Saved file")
    elseif fn:sub(-3):lower() == "bbf" then
      f.write(savebbf())
      setFooter("Saved file")
    else
      setFooter("Unsupported format")
    end
    f.close()
  else
    setFooter("Unable to open file")
  end
end

local controlHeld = false
local shiftHeld = false
local altHeld = false
local keyLookup = {}

local CONTROL_HELD = 0x10000
local ALT_HELD = 0x20000
local SHIFT_HELD = 0x40000

local running = true
local mouseAnchor = {}
local paintMode = false
local paintChar = " "
local paintLength = 0

local function addKey(keycode, func, info, modifiers)
  local modstring = ""
  local key = keys.getName(keycode)
  modifiers = modifiers or {}
  if modifiers.control then
    keycode = keycode + CONTROL_HELD
    modstring = "ctrl+"
  end
  if modifiers.alt then
    keycode = keycode + ALT_HELD
    modstring = modstring.."alt+"
  end
  if modifiers.shift then
    keycode = keycode + SHIFT_HELD
    modstring = modstring.."shift+"
  end
  local help = string.format("%s%s: %s",modstring,key,info)
  if keyLookup[keycode] then
    -- there is already a key registered here
    error(string.format("%s%s combo is already taken.",modstring,key,2))
  end
  if info == nil then
    ---@diagnostic disable-next-line: cast-local-type
    help = nil
  end
  keyLookup[keycode] = {func=func, help=help}
  return keycode
end

local _PLUGIN_ENV
local function addEventHandler(name,func)
  setfenv(func, _PLUGIN_ENV)
  eventLookup[name] = eventLookup[name] or {}
  eventLookup[name][#eventLookup[name]+1] = func
end

local function updatePluginENV()
  _PLUGIN_ENV = setmetatable({
    term = docWin,
    controlHeld = controlHeld,
    shiftHeld = shiftHeld,
    altHeld = altHeld,
    paintMode = paintMode,
    paintChar = paintChar,
    document = document,
    setChar = setChar,
    writeChar = writeChar,
    getDocumentSize = getDocumentSize,
    setFooter = setFooter,
    resetFooter = resetFooter,
    getFooter = getFooter,
    getFooterConfirm = getFooterConfirm,
    getFooterDefault = getFooterDefault,
    addKey = addKey,
    addEventHandler = addEventHandler
  }, {__index=_ENV})
end

updatePluginENV()

-- takes an initialization function for a plugin
-- sets the env properly, and calls it
local function registerPlugin(func)
  setfenv(func, _PLUGIN_ENV)
  func() -- this should initialize all listeners, keys, etc
end

local function marginPlugin()
  -- initialization function for the margin plugin, a default plugin
  local leftMargin = 1
  addEventHandler("render",function()
    -- add a marker for the current X anchor position
    local x = leftMargin - offset[1] + 2
    if x > 0 and x < resx then
      docWin.setCursorPos(x,1)
      docWin.write("\25")
    end
  end)
  addKey(keys.enter,function()
    local xpos, _ = calcDocumentPos()
    offsetSelect(leftMargin-xpos,1)
  end)
  addKey(keys.a,function()
    leftMargin, _ = calcDocumentPos()
    setFooter(("Set lMargin to %u"):format(leftMargin))
    term.clear()
    sleep(1)
  end,"Set left margin",{control=true})
end

local function colorPickerPlugin()
  local colorBarActive = false
  addEventHandler("render", function()
    -- add a palette indicator along the side of the screen
    term.setCursorPos(resx, 1)
    term.write("\7")
    if colorBarActive then
      for i = 0, 15 do
        term.setCursorPos(resx, 2+i)
        local char = ("%x"):format(i)
        local fg = furthestColorLUT[char]
        if char == api.selectedBG and char == api.selectedFG then
          term.blit("\127",fg,char)
        elseif char == api.selectedFG then
          term.blit("f",fg,char)
        elseif char == api.selectedBG then
          term.blit("b",fg,char)
        else
          term.blit(" ",fg,char)
        end
      end
    end
  end)
  addEventHandler("mouse_click", function(button, x, y)
    if x == resx and y == 1 then
      colorBarActive = not colorBarActive
    elseif x == resx and y > 1 and y < 16 + 2 and colorBarActive then
      local char = ("%x"):format(y-2)
      if button == 1 then
        -- left click, set FG
        api.selectedFG = char
      elseif button == 2 then
        -- right click set BG
        api.selectedBG = char
      end
    end
  end)
end

local function registerDefault()
  addKey(keys.q, function()
    if getFooterConfirm("Really quit? ") then
      running = false
    end
    resetFooter()
  end, "Quit", {control=true})
  addKey(keys.k,function()
    local currentWidth, currentHeight, currentLayers = table.unpack(getDocumentSize())
    local targetWidth = tonumber(getFooterDefault("Width ("..api.PAPER_WIDTH.."pp) [%u]: ", currentWidth))
    local targetHeight = tonumber(getFooterDefault("Height ("..api.PAPER_HEIGHT.."pp) [%u]: ",currentHeight))
    local targetLayers = tonumber(getFooterDefault("Layers [%u]: ",currentLayers))
    if targetWidth and targetHeight and targetLayers then
      cropDocument(targetWidth, targetHeight,targetLayers)
      resetFooter()
    else
      setFooter("Invalid input.")
    end
  end, "Crop", {control=true})
  addKey(keys.h,function() -- TODO, redo this
    term.setBackgroundColor(api.hudBG)
    term.setTextColor(api.hudFG)
    term.clear()
    term.setCursorPos(1,1)
    for k,v in pairs(keyLookup) do
      if v.help then
        print(v.help)
      end
    end
    term.write("Push enter")
    ---@diagnostic disable-next-line: discard-returns
    io.read() -- nooo you can't just ignore the return value!!!!!
    resetFooter()
  end, "Help", {control=true})
  addKey(keys.o,function()
    local fn = getFooter("Open file? ")
    if fn ~= "" then
      openFile(fn)
    else
      resetFooter()
    end
  end,"Open",{control=true})
  addKey(keys.s,function()
    local fn = getFooter("Save file? ")
    if fn ~= "" then
      saveFile(fn)
    else
      resetFooter()
    end
  end,"Save",{control=true})
  addKey(keys.f,function()
    local char = tonumber(getFooter("Character code? "))
    if char and char >= 0 and char <= 255 then
      local width = tonumber(getFooterDefault("Width [%u]? ",1))
      local height = tonumber(getFooterDefault("Height [%u]? ",1))
      if width and height and width > 0 and height > 0 then
        local x, y = calcDocumentPos()
        for dx = 1, width do
          for dy = 1, height do
            setChar(x+dx-1, y+dy-1, string.char(char))
          end
        end
        offsetSelect(width,height-1)
        resetFooter()
        addMultiUndo(width*height) -- indicate this is a group undo
      else
        setFooter("Invalid size")
      end
    else
      setFooter("Invalid color code")
    end
  end,"Fill",{control=true})
  addKey(keys.i,function()
    local maxx, maxy, maxlayer = table.unpack(getDocumentSize())
    local pagen = math.ceil(maxx/api.PAPER_WIDTH) * math.ceil(maxy/api.PAPER_HEIGHT)
    local pagetotal = pagen * maxlayer
    local cursorPos = {calcDocumentPos()}
    setFooter(string.format("%ux%u[%uPT @ %uP/L](%uL) Curs@(%u,%u)", maxx, maxy, pagetotal, pagen, maxlayer,cursorPos[1],cursorPos[2]))
    -- x by y [pages total@pages per layer](layers)@(xpos,ypos)
  end,"Info",{control=true})
  addKey(keys.c,function()
    local targetFG = tonumber(getFooterDefault("FG [%s]? ", api.selectedFG),16)
    local targetBG = tonumber(getFooterDefault("BG [%s]? ", api.selectedBG),16)
    if targetBG and targetBG <= 15 and targetBG >= 0 and targetFG and targetFG <= 15 and targetFG >= 0 then
      -- valid
      api.selectedFG = string.format("%x", targetFG)
      api.selectedBG = string.format("%x", targetBG)
      setFooter("Changed colors")
    else
      setFooter("Invalid colors")
    end
  end,"Change color",{control=true})
  addKey(keys.d,function()
    local targetFG = tonumber(getFooterDefault("Default FG [%s]? ", api.defaultFG),16)
    local targetBG = tonumber(getFooterDefault("Default BG [%s]? ", api.defaultBG),16)
    if targetBG and targetBG <= 15 and targetBG >= 0 and targetFG and targetFG <= 15 and targetFG >= 0 then
      -- valid
      api.defaultBG = string.format("%x", targetBG)
      api.defaultFG = string.format("%x", targetFG)
      setFooter("Changed colors")
    else
      setFooter("Invalid colors")
    end
  end,"Change default background",{control=true})
  addKey(keys.l,function()
    local targetLayer = tonumber(getFooterDefault("Layer [%u]? ", activeLayer))
    if targetLayer and targetLayer > 0 then
      activeLayer = targetLayer
      resetFooter()
      applyPalette()
      undoBuffer = {} -- empty the undo buffer
    else
      setFooter("Invalid layer")
    end
  end,"Change layer",{control=true})
  addKey(keys.p,function()
    if not paintMode then
      -- ask what character to paint with
      local char = tonumber(getFooter("Character code? "))
      if char then
        paintChar = string.char(char)
        paintMode = true
        setFooter("Paint mode enabled")
      else
        setFooter("Invalid character code")
      end
    else
      paintMode = false
      setFooter("Paint mode disabled")
    end
  end,"Toggle paint mode", {control=true})
  addKey(keys.g, function()
    local currentx, currenty = calcDocumentPos()
    local targetx = tonumber(getFooterDefault("X [%u]? ", currentx))
    local targety = tonumber(getFooterDefault("Y [%u]? ", currenty))
    if targetx and targety then
      offsetSelect(targetx-currentx,targety-currenty)
    end
    resetFooter()
  end, "Goto", {control=true})
  addKey(keys.m,function()
    local offsetx = tonumber(getFooterDefault("X offset [%u]? ", 0))
    local offsety = tonumber(getFooterDefault("Y offset [%u]? ", 0))
    if offsetx and offsety then
      moveDocument(offsetx,offsety)
      undoBuffer = {} -- empty the undo buffer
    end
    resetFooter()
  end, "Move document", {control=true})
  addKey(keys.z,function()
    undo()
  end, "Undo", {control=true})
  addKey(keys.b,function()
    local changeDef = getFooterConfirm("Change default (y/*)? ")
    local blitChar = tonumber(getFooter("Blit Char? "),16)
    if blitChar and blitChar >= 0 and blitChar <= 15 then
      document.pal = document.pal or {}
      document.pal.def = document.pal.def or {}
      local currentCol
      if changeDef then
        currentCol = (checkExists(document, "pal", "def") and document.pal.def[blitChar]) or term.nativePaletteColor(2^blitChar)
      else
        currentCol = (checkExists(document, "pal", activeLayer) and document.pal[activeLayer][blitChar]) or term.nativePaletteColor(2^blitChar)
      end
      local newCol = tonumber(getFooterDefault("Color [%6x]? ", currentCol))
      local layer = (changeDef and document.pal.def) or document.pal[activeLayer]
      if newCol >= 0 and newCol <= 0xFFFFFF then
        layer[blitChar] = newCol
        applyPalette()
        setFooter("Color applied")
      else
        setFooter("Invalid color")
      end
    else
      setFooter("Invalid blit char")
    end
  
  end, "Change palette color", {control=true})
  addKey(keys.backspace,function()
    offsetSelect(-1,0)
    writeChar()
  end)
  addKey(keys.delete,function()
    writeChar()
  end)
  addKey(keys.home,function()
    local x, y = calcDocumentPos()
    offsetSelect(-x,0)
  end)
  addKey(keys.left,function()
    offsetSelect(-1,0)
  end)
  addKey(keys.right,function()
    offsetSelect(1,0)
  end)
  addKey(keys.up,function()
    offsetSelect(0,-1)
  end)
  addKey(keys.down,function()
    offsetSelect(0,1)
  end)

  addEventHandler("mouse_click",function(button,x,y)
    if x > 1 and y > 1 and y < resy - 2 and x < resx then
      -- click on document area
      selPos = {x-1,y-1}
      if paintMode and button == 1 then
        -- left click and paint mode
        writeChar(paintChar)
        paintLength = 1
      end
    end
    mouseAnchor = {x,y}
  end)
  addEventHandler("char",function(char)
    writeChar(char)
    offsetSelect(1,0)
  end)
  addEventHandler("mouse_drag", function(button,x,y)
    if x > 1 and y > 1 and y < resy-2 and x < resx then
      selPos = {x-1,y-1}
      if (not paintMode) or button > 1 then
        local dx, dy = mouseAnchor[1] - x, mouseAnchor[2] - y
        offsetOffset(dx,dy)
      elseif paintMode then
        writeChar(paintChar)
        paintLength = paintLength + 1
      end
      mouseAnchor = {x,y}
    end
  end)
  addEventHandler("mouse_up", function()
    if paintLength > 0 then
      undoBuffer[#undoBuffer+1] = {1, paintLength} -- indicate this is a group undo
      paintLength = 0
    end
  end)
  addEventHandler("key", function(code)
    if code == keys.leftCtrl then
      if toggleMods then
        controlHeld = not controlHeld
      else
        controlHeld = true
      end
    elseif code == keys.leftAlt then
      if toggleMods then
        altHeld = not altHeld
      else
        altHeld = true
      end
    elseif code == keys.leftShift then
      if toggleMods then
        shiftHeld = not shiftHeld
      else
        shiftHeld = true
      end
    else
      -- perform lookup into shortcut table
      code = code + ((controlHeld and CONTROL_HELD) or 0)
      code = code + ((altHeld and ALT_HELD) or 0)
      code = code + ((shiftHeld and SHIFT_HELD) or 0)
      if keyLookup[code] then
        keyLookup[code].func()
        controlHeld = false
        altHeld = false
        shiftHeld = false
      end
    end
  end)
  addEventHandler("key_up",function(code)
    if code == keys.leftCtrl and not toggleMods then
      controlHeld = false
    elseif code == keys.leftAlt and not toggleMods then
      altHeld = false
    elseif code == keys.leftShift and not toggleMods then
      shiftHeld = false
    end
  end)
  addEventHandler("mouse_scroll",function(dir)
    if controlHeld then
      offsetOffset(dir*3,0)
    else
      offsetOffset(0, dir*3)
    end
  end)
  addEventHandler("term_resize", function()
    resx, resy = term.getSize()
    docWin.reposition(1,1,resx,resy-2)
    infobar.reposition(1,resy-1,resx,2)
  end)

  registerPlugin(marginPlugin)
  registerPlugin(colorPickerPlugin)
end



local function main()
  resetFooter()
  registerDefault()
  while running do
    renderAll()
    updatePluginENV()
    callEventHandlers("main")
    local event = {os.pullEventRaw()}
    if event[1] == "terminate" then
      running = false

    else
      callEventHandlers(event[1], table.unpack(event, 2))
    end
  end
  for i = 0, 15 do
    term.setPaletteColor(2^i, term.nativePaletteColor(2^i))
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
end

local arg = {...}
-- if a filename is passed in, attempt to load that image
if arg[1] then
  openFile(arg[1])
end
applyPalette()
main()
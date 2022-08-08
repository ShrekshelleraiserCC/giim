
local resx, resy = term.getSize()
local docWin = window.create(term.current(),1,1,resx,resy-2)
local infobar = window.create(term.current(),1,resy-1,resx,2)
-- term.redirect(infobar)

local toggleControl = true

---@diagnostic disable-next-line: undefined-global
if periphemu then
  -- this is on craftospc
  toggleControl = false
end

local selectedFG = '0'
local selectedBG = 'f'

local defaultFG = '0'
local defaultBG = 'f'

local hudFG = colors.white -- lightest color
local hudBG = colors.black -- darkest color

local PAPER_WIDTH = 25
local PAPER_HEIGHT = 21

local xAnchor = 1 -- the x anchor to use when creating newlines

local offset = {1,1} -- what position on the document the top left is in
local selPos = {1,1} -- where in the visable region the cursor has selected

local INTERNAL_FORMAT_EXTENSION = "giim"

local activeLayer = 1

local document = {}

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
        docWin.blit(ch, fg, bg or defaultBG)
      else
        docWin.blit(" ",defaultFG,defaultBG)
      end
    end
  end
  -- generate the horizontal ruler
  local hozruler = ""
  local sideString = string.rep(" ", math.floor((PAPER_WIDTH-2-3)/2))
  -- possible bug for if paper width is even
  for x = math.ceil(offset[1]/PAPER_WIDTH)-1,
  math.ceil((offset[1]+resx)/PAPER_WIDTH) do
    hozruler = hozruler..
    string.format("|"..sideString.."%3u"..sideString.."|", x)
  end
  docWin.setBackgroundColor(hudBG)
  docWin.setTextColor(hudFG)
  docWin.setCursorPos(2,1)
  docWin.write(hozruler:sub(((offset[1]-1)%PAPER_WIDTH)+1+PAPER_WIDTH))

  -- generate the vertical ruler
  local verruler = ""
  local vertString = string.rep(" ", math.floor((PAPER_HEIGHT-2-3)/2))
  for x = math.ceil(offset[2]/PAPER_HEIGHT)-1,
  math.ceil((offset[2]+resy)/PAPER_HEIGHT) do
    verruler = verruler..
    string.format("-"..vertString.."%3u"..vertString.."-", x)
  end
  local sindex = ((offset[2]-1)%PAPER_HEIGHT)+1+PAPER_HEIGHT
  for y = 2, resy do
    docWin.setCursorPos(1,y)
    docWin.write(verruler:sub(sindex,sindex))
    sindex = sindex + 1
  end

  -- add a marker for the current X anchor position
  local x = xAnchor - offset[1] + 2
  if x > 0 and x < resx then
    docWin.setCursorPos(x,1)
    docWin.write("\25")
  end

  -- now add markers to the rulers to show where the cursor currently is
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
    fg = defaultFG
  end
  term.setTextColor(2^tonumber(fg,16))
  term.setBackgroundColor(hudBG)
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
    document.im[activeLayer][y][x] = {char, selectedFG, selectedBG} -- see, it's just getting replaced.
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



-- set the character at the current document position
local function setCharAtPos(char)
  local x, y = calcDocumentPos()
  setChar(x,y,char)
end

-- set the info bar to something specific
local function setInfo(t)
  infobar.setBackgroundColor(hudBG)
  infobar.setTextColor(hudFG)
  infobar.clear()
  infobar.setCursorPos(1,1)
  infobar.write(t)
end

-- set the info bar to the default
local function setInfoDefault()
  setInfo("GIIM v1.0.2 CTRL-H for help")
end

-- get input from the info bar, displaying string t
local function getInfo(t)
  setInfo(t)
  return io.read()
end

-- get a boolean from the info bar, displaying string t
local function getInfoConfirm(t)
  return getInfo(t):lower():sub(1,1) == "y"
end

-- get input from the info bar (enter is pushed without inputting anything returns default)
-- t should be  string.format string that takes a single string (def)
local function getInfoDefault(t,def)
  local input = getInfo(string.format(t,def))
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
local function applyPalette()
  local brightest = 0
  local darkest = 255
  local function _ca(c)
    local r,g,b = colors.unpackRGB(c)
    return 255 * ((r+g+b)/3)
  end
  document.pal = document.pal or {}
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
      hudBG = 2^i
    end
    if colorAverage > brightest then
      brightest = colorAverage
      hudFG = 2^i
    end
  end
  term.setBackgroundColor(hudBG)
  term.clear()
  setInfoDefault()
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

local function openbimg(t)
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
local function openbbf(f)
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
    setInfoDefault()
  else
    setInfo("Invalid bbf file")
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
          blitTable = {" ", defaultFG, defaultBG}
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
        openbimg(bt)
        setInfoDefault()
        undoBuffer = {}
      else
        setInfo("Invalid bimg file")
      end
    elseif fn:sub(-INTERNAL_FORMAT_EXTENSION:len()) == INTERNAL_FORMAT_EXTENSION then
      local bt = textutils.unserialise(f.readAll())
      if bt then
        document = bt
        setInfoDefault()
        undoBuffer = {}
      else
        setInfo("Invalid file")
      end
    elseif fn:sub(-3):lower() == "bbf" then
      openbbf(f)
      undoBuffer = {}
    else
      setInfo("Unsupported format")
    end
    f.close()
  else
    setInfo("Unable to open file")
  end
  applyPalette()

end

local function saveFile(fn)
  local f = fs.open(fn, "wb")
  if f then
    if fn:sub(-4):lower() == "bimg" then
      -- TODO implement bimg saving
      f.write(textutils.serialize(savebimg(),{compact=true}))
      setInfo("Saved file")
    elseif fn:sub(-INTERNAL_FORMAT_EXTENSION:len()) == INTERNAL_FORMAT_EXTENSION then
      f.write(textutils.serialise(document,{compact=true}))
      setInfo("Saved file")
    elseif fn:sub(-3):lower() == "bbf" then
      f.write(savebbf())
      setInfo("Saved file")
    else
      setInfo("Unsupported format")
    end
    f.close()
  else
    setInfo("Unable to open file")
  end
end

local function main()
  local mouseAnchor = {}
  local controlHeld = false
  local controlHeldFunctions -- get this into scope of its own definition
  local running = true
  local paintMode = false
  local paintChar = " "
  local paintLength = 0
  controlHeldFunctions = {
    [keys.q] = {func=function()
      controlHeld = false
      if getInfoConfirm("Really quit? ") then
        running = false
      end
      setInfoDefault()
    end,help="Q=quit"},

    [keys.k] = {func=function()
      controlHeld = false
      local currentWidth, currentHeight, currentLayers = table.unpack(getDocumentSize())
      local targetWidth = tonumber(getInfoDefault("Width ("..PAPER_WIDTH.."pp) [%u]: ", currentWidth))
      local targetHeight = tonumber(getInfoDefault("Height ("..PAPER_HEIGHT.."pp) [%u]: ",currentHeight))
      local targetLayers = tonumber(getInfoDefault("Layers [%u]: ",currentLayers))
      if targetWidth and targetHeight and targetLayers then
        cropDocument(targetWidth, targetHeight,targetLayers)
        setInfoDefault()
      else
        setInfo("Invalid input.")
      end
    end,help="K=crop"},

    [keys.h] = {func=function()
      term.setBackgroundColor(hudBG)
      term.setTextColor(hudFG)
      controlHeld=false
      term.clear()
      term.setCursorPos(1,1)
      print("Arrows move by page when control is held")
      for k,v in pairs(controlHeldFunctions) do
        if v.help then
          print(v.help)
        end
      end
      term.write("Push enter")
      ---@diagnostic disable-next-line: discard-returns
      io.read() -- nooo you can't just ignore the return value!!!!!
      setInfoDefault()
    end,help="H=help"},

    [keys.o] = {func=function()
      local fn = getInfo("Open file? ")
      controlHeld = false
      if fn ~= "" then
        openFile(fn)
      else
        setInfoDefault()
      end
    end,help="O=open"},

    [keys.s] = {func=function()
      local fn = getInfo("Save file? ")
      controlHeld = false
      if fn ~= "" then
        saveFile(fn)
      else
        setInfoDefault()
      end
    end,help="S=save"},

    [keys.f] = {func=function()
      controlHeld = false
      local char = tonumber(getInfo("Character code? "))
      if char and char >= 0 and char <= 255 then
        local width = tonumber(getInfoDefault("Width [%u]? ",1))
        local height = tonumber(getInfoDefault("Height [%u]? ",1))
        if width and height and width > 0 and height > 0 then
          local x, y = calcDocumentPos()
          for dx = 1, width do
            for dy = 1, height do
              setChar(x+dx-1, y+dy-1, string.char(char))
            end
          end
          offsetSelect(width,height-1)
          setInfoDefault()
          undoBuffer[#undoBuffer+1] = {1, width*height} -- indicate this is a group undo
        else
          setInfo("Invalid size")
        end
      else
        setInfo("Invalid color code")
      end
    end,help="F=fill"},

    [keys.i] = {func=function()
      local maxx, maxy, maxlayer = table.unpack(getDocumentSize())
      local pagen = math.ceil(maxx/PAPER_WIDTH) * math.ceil(maxy/PAPER_HEIGHT)
      local pagetotal = pagen * maxlayer
      local cursorPos = {calcDocumentPos()}
      setInfo(string.format("%ux%u[%uPT @ %uP/L](%uL) Curs@(%u,%u)", maxx, maxy, pagetotal, pagen, maxlayer,cursorPos[1],cursorPos[2]))
      -- x by y [pages total@pages per layer](layers)@(xpos,ypos)
    end,help="I=info"},

    [keys.c] = {func=function()
      controlHeld=false
      local targetFG = tonumber(getInfoDefault("FG [%s]? ", selectedFG),16)
      local targetBG = tonumber(getInfoDefault("BG [%s]? ", selectedBG),16)
      if targetBG and targetBG <= 15 and targetBG >= 0 and targetFG and targetFG <= 15 and targetFG >= 0 then
        -- valid
        selectedFG = string.format("%x", targetFG)
        selectedBG = string.format("%x", targetBG)
        setInfo("Changed colors")
      else
        setInfo("Invalid colors")
      end
    end,help="C=change color"},

    [keys.d] = {func=function()
      controlHeld=false
      local targetFG = tonumber(getInfoDefault("Default FG [%s]? ", defaultFG),16)
      local targetBG = tonumber(getInfoDefault("Default BG [%s]? ", defaultBG),16)
      if targetBG and targetBG <= 15 and targetBG >= 0 and targetFG and targetFG <= 15 and targetFG >= 0 then
        -- valid
        defaultBG = string.format("%x", targetBG)
        defaultFG = string.format("%x", targetFG)
        setInfo("Changed colors")
      else
        setInfo("Invalid colors")
      end
    end,help="D=change default background"},

    [keys.l] = {func=function ()
      controlHeld=false
      local targetLayer = tonumber(getInfoDefault("Layer [%u]? ", activeLayer))
      if targetLayer and targetLayer > 0 then
        activeLayer = targetLayer
        setInfoDefault()
        applyPalette()
        undoBuffer = {} -- empty the undo buffer
      else
        setInfo("Invalid layer")
      end
    end,help="L=change layer"},

    [keys.p] = {func=function()
      controlHeld=false
      if not paintMode then
        -- ask what character to paint with
        local char = tonumber(getInfo("Character code? "))
        if char then
          paintChar = string.char(char)
          paintMode = true
          setInfo("Paint mode enabled")
        else
          setInfo("Invalid character code")
        end
      else
        paintMode = false
        setInfo("Paint mode disabled")
      end
    end,help="P=toggle paint mode"},

    [keys.a] = {func=function()
      xAnchor, _ = calcDocumentPos()
      setInfo(("Set anchor to %u"):format(xAnchor))
    end,help="A=set newline anchor"},

    [keys.g] = {func=function()
      controlHeld=false
      local currentx, currenty = calcDocumentPos()
      local targetx = tonumber(getInfoDefault("X [%u]? ", currentx))
      local targety = tonumber(getInfoDefault("Y [%u]? ", currenty))
      if targetx and targety then
        offsetSelect(targetx-currentx,targety-currenty)
      end
      setInfoDefault()
    end,help="G=goto"},

    [keys.m] = {func=function()
      controlHeld=false
      local offsetx = tonumber(getInfoDefault("X offset [%u]? ", 0))
      local offsety = tonumber(getInfoDefault("Y offset [%u]? ", 0))
      if offsetx and offsety then
        moveDocument(offsetx,offsety)
        undoBuffer = {} -- empty the undo buffer
      end
      setInfoDefault()
    
    end,help="M=move document"},

    [keys.z] = {func=function()
      undo()
    end,help="Z=undo"},

    [keys.b] = {func=function()
      controlHeld=false
      local changeDef = getInfoConfirm("Change default (y/*)? ")
      local blitChar = tonumber(getInfo("Blit Char? "),16)
      if blitChar and blitChar >= 0 and blitChar <= 15 then
        document.pal = document.pal or {}
        document.pal.def = document.pal.def or {}
        local currentCol
        if changeDef then
          currentCol = (checkExists(document, "pal", "def") and document.pal.def[blitChar]) or term.nativePaletteColor(2^blitChar)
        else
          currentCol = (checkExists(document, "pal", activeLayer) and document.pal[activeLayer][blitChar]) or term.nativePaletteColor(2^blitChar)
        end
        local newCol = tonumber(getInfoDefault("Color [%6x]? ", currentCol))
        local layer = (changeDef and document.pal.def) or document.pal[activeLayer]
        if newCol >= 0 and newCol <= 0xFFFFFF then
          layer[blitChar] = newCol
          applyPalette()
          setInfo("Color applied")
        else
          setInfo("Invalid color")
        end
      else
        setInfo("Invalid blit char")
      end
    
    end,help="B=change palette color"}
  }
  setInfoDefault()
  while running do
    renderAll()
    local event = {os.pullEventRaw()}
    if event[1] == "terminate" then
      running = false

    elseif event[1] == "mouse_click" then
      local button, x, y = event[2], event[3], event[4]
      if x > 1 and y > 1 and y < resy - 1 then
        -- click on document area
        selPos = {x-1,y-1}
        if paintMode and button == 1 then
          -- left click and paint mode
          setCharAtPos(paintChar)
          paintLength = 1
        end
      end
      mouseAnchor = {x,y}

    elseif event[1] == "char" then
      local char = event[2]
      -- for now just process all characters
      -- when control is held "char" events don't fire
      setCharAtPos(char)
      offsetSelect(1,0)

    elseif event[1] == "mouse_drag" then
      local button, x, y = event[2], event[3], event[4]
      if x > 1 and y > 1 and y < resy-1 then
        selPos = {x-1,y-1}
        if (not paintMode) or button > 1 then
          local dx, dy = mouseAnchor[1] - x, mouseAnchor[2] - y
          offsetOffset(dx,dy)
        elseif paintMode then
          setCharAtPos(paintChar)
          paintLength = paintLength + 1
        end
        mouseAnchor = {x,y}
      end
    elseif event[1] == "mouse_up" then
      if paintLength > 0 then
        undoBuffer[#undoBuffer+1] = {1, paintLength} -- indicate this is a group undo
        paintLength = 0
      end

    elseif event[1] == "key" then
      local code = event[2]
      if code == keys.backspace then
        offsetSelect(-1,0)
        setCharAtPos()

      elseif code == keys.delete then
        setCharAtPos()

      elseif code == keys.enter then
        local xpos, _ = calcDocumentPos()
        offsetSelect(xAnchor-xpos,1)

      elseif code == keys.leftCtrl then
        if toggleControl then
          controlHeld = not controlHeld
          if controlHeld then
            setInfo("Control active")
          else
            setInfoDefault()
          end
        else
          controlHeld = true
        end

      elseif code == keys.home then
        local x, y = calcDocumentPos()
        offsetSelect(-x,0)

      elseif controlHeld then
        if controlHeldFunctions[code] then
          controlHeldFunctions[code].func()

        elseif code == keys.left then
          offsetSelect(-PAPER_WIDTH,0)
        elseif code == keys.right then
          offsetSelect(PAPER_WIDTH,0)
        elseif code == keys.down then
          offsetSelect(0,PAPER_HEIGHT)
        elseif code == keys.up then
          offsetSelect(0,-PAPER_HEIGHT)
        end
      -- check for arrows without control
      elseif code == keys.left then
        offsetSelect(-1,0)
      elseif code == keys.right then
        offsetSelect(1,0)
      elseif code == keys.down then
        offsetSelect(0,1)
      elseif code == keys.up then
        offsetSelect(0,-1)
      end

    elseif event[1] == "key_up" then
      local code = event[2]
      if code == keys.leftCtrl and not toggleControl then
        controlHeld = false

      end

    elseif event[1] == "mouse_scroll" then
      local dir = event[2]
      if controlHeld then
        offsetOffset(dir*3,0)
      else
        offsetOffset(0, dir*3)
      end

    elseif event[1] == "term_resize" then
      resx, resy = term.getSize()
      docWin.reposition(1,1,resx,resy-2)
      infobar.reposition(1,resy-1,resx,2)
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


-- if a filename is passed in, attempt to load that image
if arg[1] then
  openFile(arg[1])
end
main()
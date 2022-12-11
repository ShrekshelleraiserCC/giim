local resx, resy = term.getSize()
local viewport = window.create(term.current(),1,1,resx,resy-2)
local documentRender = window.create(viewport,1,1,1,1)
local infobar = window.create(term.current(),1,resy-1,resx,2)
local api = {}
local expect = require("cc.expect").expect

-- You will have access to all items in the api table when running a plugin
-- You will have access to docWin through term in your plugin
-- You will also have a few registration functions

api.GIIM_VERSION = "1.1.4" -- do not modify, but you can enforce GIIM version compatibility by comparing with this string

api.toggleMods = true

---@diagnostic disable-next-line: undefined-global
if periphemu then
  -- this is on craftospc
  api.toggleMods = false
end

api.selectedFG = '0' -- selected blit character of FG
api.selectedBG = 'f' -- selected blit character of BG

api.hudFG = colors.white -- lightest color (calculated automatically when palettes change)
api.hudBG = colors.black -- darkest color (calculated automatically when palettes change)

api.PAPER_WIDTH = 25 -- Constant paper width
api.PAPER_HEIGHT = 21 -- Constant paper height

local offset = {1,1} -- what position on the document the top left is in
local selPos = {1,1} -- where in the visable region the cursor has selected

api.controlHeld = false
api.shiftHeld = false
api.altHeld = false

api.fullRender = true -- do a full render next pass

local INTERNAL_FORMAT_EXTENSION = "giim"

api.activeLayer = 1 -- the layer we're on

api.document = {} -- the document we're editing, indexed ["im"][layer][y][x] = {char,fg,bg} for the document itself
-- and ["pal"]["def"] / ["pal"][layer] = {0-15 indexed colors} for the palettes

api.furthestColorLUT = {} -- input a color char, get a color char of the color furthest from it

local undoBuffer = {}
-- each element in the undoBuffer is either a set, or a multi
-- {0, x, y, blit[3]}
-- {1, amount} -- when this is undone, automatically undo amount more

--- Checks that every element in the given chain exists, ie. table[arg[1]][arg[2]]...
-- @treturn boolean
function api.checkExists(tab, ...)
  expect(1,tab,"table")
  local t = tab
  for _, val in ipairs({...}) do
    t = t[val]
    if not t then
      return false
    end
  end
  return true
end

--- Get the current cursor position on the document
-- @treturn int
-- @treturn int
function api.getCursorPos()
  return offset[1]+selPos[1]-1,offset[2]+selPos[2]-1
end

local updateDocumentPosition

--- Set the character at the given x,y position in the document (adds to undo buffer)
-- @tparam x int
-- @tparam y int
-- @tparam char character
function api.setChar(x,y,char)
  expect(1,x,"number")
  expect(2,y,"number")
  expect(3,char,"string","nil")
  api.document.im = api.document.im or {}
  api.document.im[api.activeLayer] = api.document.im[api.activeLayer] or {}
  api.document.im[api.activeLayer][y] = api.document.im[api.activeLayer][y] or {}
  undoBuffer[#undoBuffer+1] = {0, x, y, api.document.im[api.activeLayer][y][x]} -- this works because the original blit table is not being modified
  if char == nil then
    api.document.im[api.activeLayer][y][x] = nil -- TODO, the document size might expand and not get shrunk back down
    documentRender.setCursorPos(x,y)
    documentRender.setTextColor(api.hudFG)
    documentRender.setBackgroundColor(api.hudBG)
    documentRender.write(" ")
  else
    api.document.im[api.activeLayer][y][x] = {char, api.selectedFG, api.selectedBG} -- see, it's just getting replaced.
    api.cachedDocumentSize[1] = math.max(x, api.cachedDocumentSize[1])
    api.cachedDocumentSize[2] = math.max(y, api.cachedDocumentSize[2])
    api.cachedDocumentSize[3] = math.max(api.activeLayer, api.cachedDocumentSize[3])
    if (x > api.cachedDocumentSize[1] or y > api.cachedDocumentSize[2]) then
      updateDocumentPosition()
      api.fullRender = true
    end
    documentRender.setCursorPos(x,y)
    documentRender.blit(table.unpack(api.document.im[api.activeLayer][y][x]))
  end
  -- api.fullRender = true
end

--- set the character at the current document position (adds to undo buffer)
-- @tparam char character
function api.writeChar(char)
  expect(1,char,"string","nil")
  local x, y = api.getCursorPos()
  api.setChar(x,y,char)
end

--- Offset the document viewport (range checks)
-- @tparam dx int
-- @tparam dy int
function api.offsetViewport(dx,dy)
  expect(1,dx,"number")
  expect(2,dy,"number")
  offset = {offset[1]+dx,offset[2]+dy}
  offset = {math.max(offset[1],1),math.max(offset[2],1)}
end
--- Offset the document cursor (range checks & moves viewport to match)
-- @tparam dx int
-- @tparam dy int
function api.offsetCursor(dx,dy)
  expect(1,dx,"number")
  expect(2,dy,"number")
  selPos = {selPos[1]+dx,selPos[2]+dy}
  if selPos[1] < 2 then
    -- this is to the left of the document
    api.offsetViewport(selPos[1]-1,0) -- attempt to move the entire document by that amount
  elseif selPos[1] > resx-2 then
    api.offsetViewport(selPos[1]-(resx-2),0)
  end
  if selPos[2] < 2 then
    api.offsetViewport(0,selPos[2]-1)
  elseif selPos[2] > resy-4 then
    api.offsetViewport(0,selPos[2]-(resy-4))
  end
  selPos = {math.max(selPos[1],1),math.max(selPos[2],1)}
  selPos = {math.min(selPos[1],resx-2),math.min(selPos[2],resy-4)}
end

--- add a special entry to the undo buffer, that signifies the next n steps should be undone.
-- @tparam n int
function api.addMultiUndo(n)
  undoBuffer[#undoBuffer+1] = {1, n} -- indicate this is a group undo
end

--- set the footer to display t
-- @tparam t string
function api.setFooter(t)
  expect(1,t,"string")
  infobar.setBackgroundColor(api.hudBG)
  infobar.setTextColor(api.hudFG)
  infobar.clear()
  infobar.setCursorPos(1,1)
  infobar.write(t)
end

--- set the footer to the default
function api.resetFooter()
  api.setFooter(("GIIM v%s CTRL-H for help"):format(api.GIIM_VERSION))
end

--- get input from the footer, displaying string t
-- @tparam t string
-- @treturn string
function api.getFooter(t)
  expect(1,t,"string")
  api.setFooter(t)
  return io.read()
end

--- get a boolean from the info bar, displaying string t
-- @tparam t string
-- @treturn boolean
function api.getFooterConfirm(t)
  return api.getFooter(t):lower():sub(1,1) == "y"
end

--- get input from the info bar (enter is pushed without inputting anything returns default)
--- t should be string.format string that takes a single string (def)
-- @tparam t string
-- @param def
-- @return def or input value
function api.getFooterDefault(t,def)
  local input = api.getFooter(string.format(t,def))
  if input == "" then
    return def
  end
  return input
end


--- Get the document size
-- this is an intensive function, call only when required
-- @treturn table {res x, res y, n layers}
function api.getDocumentSize()
  local maxx = 0
  local maxy = 0
  local maxlayer = 0
  api.document.im = api.document.im or {}
  for l, layer in pairs(api.document.im) do
    maxlayer = math.max(maxlayer, l)
    for y,row in pairs(layer) do
      for x, column in pairs(row) do
        maxx = math.max(maxx, x)
      end
      maxy = math.max(maxy,y)
    end
  end
  api.cachedDocumentSize = {maxx, maxy, maxlayer}
  return api.cachedDocumentSize
end

-- whenever possible, use the values from this variable insteaed of calling `getDocumentSize` directly
-- whenever getDocumentSize is called, this value will be updated
-- This value may be larger than the document, but will never be smaller than the document.
-- If you REQUIRE precise size, then you can call getDocumentSize
api.cachedDocumentSize = {1,1,1}

--- Crop the document to fit within bounds
-- @tparam maxx int
-- @tparam maxy int
-- @tparam maxlayer int
function api.cropDocument(maxx,maxy,maxlayer)
  expect(1, maxx, "number")
  expect(2, maxy, "number")
  expect(3, maxlayer, "number")
  api.document.im = api.document.im or {}
  for l, layer in pairs(api.document.im) do
    if l > maxlayer then
      api.document.im[l] = nil
      layer = {}
    end
    for y,row in pairs(layer) do
      if y > maxy then
        api.document.im[l][y] = nil
        row = {} -- to satisfy the other for loop
      end
      for x, column in pairs(row) do
        if x > maxx then
          row[x] = nil
        end
      end
    end
  end
  api.document.pal = api.document.pal or {}
  for l, layer in pairs(api.document.pal) do
    if type(l) == "number" and l > maxlayer then
      api.document.pal[l] = nil
    end
  end
  api.cachedDocumentSize = {maxx, maxy, maxlayer}
end

--- move the {1,1} position of the document by dx,dy
--- this will CLIP anything that goes off the left and top sides (< 1)
-- @tparam dx int
-- @tparam dy int
function api.moveDocument(dx,dy)
  expect(1,dx,"number")
  expect(2,dy,"number")
  local newDocument = {im={}}
  for k,v in pairs(api.document) do
    if k ~= "im" then
      -- copy over all data that's not the image
      newDocument[k] = v
    end
  end
  api.document.im = api.document.im or {}
  for l, layer in pairs(api.document.im) do
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
  api.document = newDocument
  api.getDocumentSize()
end

--- Undo the last thing in the undo buffer
function api.undo()
  local undoinfo = undoBuffer[#undoBuffer]
  if undoinfo == nil then return end
  undoBuffer[#undoBuffer] = nil
  if undoinfo[1] == 0 then
    -- set
    local x = undoinfo[2]
    local y = undoinfo[3]
    api.document.im = api.document.im or {}
    api.document.im[api.activeLayer] = api.document.im[api.activeLayer] or {}
    api.document.im[api.activeLayer][y] = api.document.im[api.activeLayer][y] or {}
    api.document.im[api.activeLayer][y][x] = undoinfo[4]
    api.fullRender = true

  elseif undoinfo[1] == 1 then
    -- series
    for i = 1, undoinfo[2] do
      api.undo()
    end
    api.fullRender = true
  else
    error("Invalid entry in undo table")
  end
end

api.loadedPlugins = {} -- table indexed by load position
-- each element will be a 2 entry table {name, ver} where ver might be nil

-- Returns true if the provided plugin name and version are loaded
-- provide nil for version to accept any version
function api.hasPlugin(name, version)
  for k,v in ipairs(api.loadedPlugins) do
    if v[1] == name and ((not version) or v[2] == version) then
      return true
    end
  end
  return false
end

-- Throw an error if the requested plugin isn't present
-- @tparam string name
-- @tparam string name of this plugin
-- @tparam string|nil version
function api.requirePlugin(name, hname, version)
  local fstring
  if version then
    fstring = string.format("Plugin %s requires version %s %s", hname, version, name)
  else
    fstring = string.format("Plugin %s requires any version %s", hname, name)
  end
  assert(api.hasPlugin(name,version), fstring)
end

local keyLookup = {} -- private lookup field for active keys

local CONTROL_HELD = 0x10000
local ALT_HELD = 0x20000
local SHIFT_HELD = 0x40000

-- The following functions are registration functions
-- You will have access to them in your plugins

--- Add a listener for a certain key combination
-- @tparam keycode int keycode i.e keys.down
-- @tparam func function
-- @tparam info nil/string info about the keybind
-- @tparam modifiers nil/table {shift=bool,alt=bool,control=bool}
-- @treturn int index of key added
local function addKey(keycode, func, info, modifiers)
  expect(1,keycode,"number")
  expect(2,func,"function")
  expect(4,modifiers,"nil","table")
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

--- Remove a key listener
-- @tparam int keyindex
local function removeKey(keyindex)
  expect(1,keyindex,"number")
  keyLookup[keyindex] = nil
end

local formatLUT = {save={},load={}}

local pow2LUT = {}
for i = 0, 15 do
  pow2LUT[i] = 2^i
end

--- Add a new format handler
-- @tparam string name
-- @tparam nil|function save
-- @tparam nil|function load
local function addFormat(name, save, load)
  expect(1, name, "string")
  expect(2, save, "nil", "function")
  expect(3, load, "nil", "function")
  if save and formatLUT.save[name] then
    error(string.format("Format %s already has a save handler!"), name)
  elseif save then
    formatLUT.save[name] = save
  end
  if load and formatLUT.load[name] then
    error(string.format("Format %s already has a load handler!"), name)
  elseif load then
    formatLUT.load[name] = load
  end
end

local eventLookup = {}

--- Add a new event handler
-- @tparam string event name
-- @tparam function handler function, takes table.unpack({os.pullEvent()}, 2)
local function addEventHandler(name,func)
  expect(1,name,"string")
  expect(2,func,"function")
  eventLookup[name] = eventLookup[name] or {}
  eventLookup[name][#eventLookup[name]+1] = func
end

--- END OF PLUGIN ACCESSIBLE OBJECTS
--- You will NOT have access to anything below here inside of your plugin.
--- But you are welcome to look at the built in plugins


local running = true
--- Iterate through and run all the event handlers
local function callEventHandlers(name, ...)
  if eventLookup[name] then
    local n = #eventLookup[name]
    for i = n, 1, -1 do
      local data = {pcall(eventLookup[name][i], ...)}
      if not data[1] then
        -- TODO error handle gracefully
        for i = 0, 15 do
          term.setPaletteColor(pow2LUT[i], term.nativePaletteColor(pow2LUT[i]))
        end
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1,1)
        print("An error has occured while calling event handler for " .. name)
        error(data[2])
      elseif data[2] then -- call each event handler for this type
        break -- an event handler can return true to stop previously loaded plugins from executing
      end
    end
  end
end

function updateDocumentPosition()
  local docWidth, docHeight, docLayers = api.cachedDocumentSize[1], api.cachedDocumentSize[2], api.cachedDocumentSize[3]
  local docOffX, docOffY = offset[1], offset[2]
  documentRender.reposition(-docOffX, -docOffY, docWidth, docHeight)
end
--- render the FULL document
local function renderDocument(full)
  if full then
    documentRender.setVisible(false)
    local docWidth, docHeight, docLayers = api.cachedDocumentSize[1], api.cachedDocumentSize[2], api.cachedDocumentSize[3]
    documentRender.setTextColor(2^tonumber(api.selectedFG,16))
    documentRender.setBackgroundColor(2^tonumber(api.selectedBG,16))
    documentRender.clear()
    if api.activeLayer <= docLayers then
      for y = 1, docHeight do
        for x = 1, docWidth do
          documentRender.setCursorPos(x,y)
          if api.checkExists(api.document, "im", api.activeLayer, y, x) then
            -- this co-ordinate has a character defined
            local ch, fg, bg = table.unpack(api.document.im[api.activeLayer][y][x])
            documentRender.blit(ch, fg, bg or api.selectedBG)
          else
            documentRender.blit(" ",api.selectedFG,api.selectedBG)
          end
        end
      end
    end
    documentRender.setVisible(true)
  else
    documentRender.redraw()
  end
end


local leftPointer = window.create(viewport, 1, 2, 1, 1)
leftPointer.setBackgroundColor(api.hudBG)
leftPointer.setTextColor(api.hudFG)
leftPointer.setCursorPos(1,1)
leftPointer.write("\16")
local topPointer = window.create(viewport, 2, 1, 1, 1)
topPointer.setBackgroundColor(api.hudBG)
topPointer.setTextColor(api.hudFG)
topPointer.setCursorPos(1,1)
topPointer.write("\31")

local function renderAll()
  viewport.setBackgroundColor(api.hudBG)
  viewport.setVisible(false)
  viewport.clear()

  updateDocumentPosition()
  renderDocument(api.fullRender)
  api.fullRender = false

  callEventHandlers("render") -- call all registered event handlers

  -- add markers to indicate current cursor position
  local x, y = table.unpack(selPos)
  leftPointer.reposition(1,y+1)
  leftPointer.setBackgroundColor(api.hudBG)
  leftPointer.setTextColor(api.hudFG)
  leftPointer.setCursorPos(1,1)
  leftPointer.write("\16")
  topPointer.reposition(x+1,1)
  topPointer.setBackgroundColor(api.hudBG)
  topPointer.setTextColor(api.hudFG)
  topPointer.setCursorPos(1,1)
  topPointer.write("\31")

  -- redraw the documentRender
  -- then draw the docWin

  local fg
  if api.checkExists(api.document, "im", api.activeLayer, y, x, 2) then
    fg = api.furthestColorLUT[api.document.im[api.activeLayer][y][x][3]]
  else
    fg = api.selectedFG
  end
  viewport.setTextColor(2^tonumber(fg,16))
  local x, y = api.getCursorPos()
  viewport.setTextColor(2^tonumber(fg,16))
  viewport.setBackgroundColor(api.hudBG)
  viewport.setCursorPos(selPos[1]+1,selPos[2]+1)
  viewport.setCursorBlink(true)
  viewport.setVisible(true)
  infobar.redraw()

end

local _PLUGIN_ENV = setmetatable({
  api=api,
  term=viewport, -- anything you set in _ENV will be shared with other plugins
  addEventHandler=addEventHandler,
  addKey=addKey,
  removeKey=removeKey,
  addFormat=addFormat
}, {__index=_ENV})

local function bimgPlugin()
  local function loadbimg(f)
    local t = textutils.unserialise(f.readAll())
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
      api.document = {im={},pal={}}
      api.document.pal.def = _convBimgPalette(t.palette)
      for fn, frame in ipairs(t) do
        api.document.im[fn] = {}
        api.document.pal[fn] = _convBimgPalette(frame.palette)
        for y, line in pairs(frame) do
          api.document.im[fn][y] = {}
          for x = 1, string.len(line[1]) do
            api.document.im[fn][y][x] = {line[1]:sub(x,x), line[2]:sub(x,x), line[3]:sub(x,x)}
          end
        end
      end
      return true
    else
      return false, "Invalid BIMG file"
    end
  end
  -- returns a bimg compatible blit table
  local function savebimg(f)
    local function _convBimgPalette(p)
      if p == nil then return end
      local np = {}
      for k,v in pairs(p) do
        np[k] = {v}
      end
      return np
    end
    local maxx, maxy, maxlayer = table.unpack(api.getDocumentSize())
    local bimg = {}
    api.document.pal = api.document.pal or {}
    bimg.palette = _convBimgPalette(api.document.pal.def)
    for layer = 1, maxlayer do
      bimg[layer] = {}
      bimg[layer].palette = _convBimgPalette(api.document.pal[layer])
      for y = 1, maxy do
        bimg[layer][y] = {{},{},{}}
        for x = 1, maxx do
          bimg[layer][y][1][x] = api.document.im[layer][y][x][1]
          bimg[layer][y][2][x] = api.document.im[layer][y][x][2]
          bimg[layer][y][3][x] = api.document.im[layer][y][x][3]
        end
        bimg[layer][y][1] = table.concat(bimg[layer][y][1])
        bimg[layer][y][2] = table.concat(bimg[layer][y][2])
        bimg[layer][y][3] = table.concat(bimg[layer][y][3])
      end
    end
    bimg.version = "1.0.0"
    bimg.animation = maxlayer > 1
    if bimg.animation then
      -- multiple layers
      bimg.secondsPerFrame = 0.1 -- maybe make this configurable in the future?
    end
    f.write(textutils.serialise(bimg,{compact=true}))
    return true, "BIMG saved."
  end

  addFormat("bimg",savebimg,loadbimg)
  return "bimg", "1.1"
end

local function bbfPlugin()
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
      api.document = {im={},pal={}}
      if metadata.palette and #metadata.palette == 1 then
        -- there's only a single palette
        api.document.pal.def = _convBbfPalette(metadata.palette[1])
      end
      for frame = 1, frames do
        api.document.im[frame] = {}
        if metadata.palette and metadata.palette[frame] then
          api.document.pal[frame] = _convBbfPalette(metadata.palette[frame])
        end
        for y = 1, height do
          api.document.im[frame][y] = {}
          for x = 1, width do
            local char = f.read(1)
            local byte = string.byte(f.read(1))
            local fg = string.format("%x", bit32.rshift(byte, 4))
            local bg = string.format("%x", bit32.band(byte, 0xF))
            api.document.im[frame][y][x] = {char,fg,bg}
          end
        end
      end
      return true
    else
      return false, "Invalid bbf file"
    end
  end

  local function savebbf(f)
    local file = {"BLBFOR1\n"}
    local function add(...)
      for k,v in pairs({...}) do
        file[#file+1] = v
      end
    end
    local width, height, frames = table.unpack(api.getDocumentSize())
    add(width, "\n", height, "\n", frames, "\n")
    add(os.epoch("utc"), "\n")
    local palette = {}
    for k,v in ipairs(api.document.pal) do
      palette[k] = {}
      for k2,v2 in pairs(v) do
        palette[k][tostring(k2)] = v2
      end
    end
    palette[1] = api.document.pal.def or palette[1] -- make sure default palette is first
    add(textutils.serializeJSON({palette=palette}),"\n")
    for frame = 1, frames do
      for y = 1, height do
        for x = 1, width do
          local blitTable
          if api.checkExists(api.document, "im", frame, y, x) then
            blitTable = api.document.im[frame][y][x]
          else
            blitTable = {" ", api.selectedFG, api.selectedBG}
          end
          add(blitTable[1])
          local byte = bit32.lshift(tonumber(blitTable[2],16),4) + tonumber(blitTable[3],16)
          add(string.char(byte))
        end
      end
    end
    f.write(table.concat(file))
    return true
  end

  addFormat("bbf",savebbf,loadbbf)
  return "bbf", "1.0"
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
  api.document.pal = api.document.pal or {}
  local colorsUsed = {}
  for i = 0, 15 do
    local colorUsed
    if api.document.pal[api.activeLayer] and api.document.pal[api.activeLayer][i] then
      -- set the palette based off the active layer palette
      colorUsed = api.document.pal[api.activeLayer][i]
    elseif api.document.pal.def and api.document.pal.def[i] then
      -- fall back to the default document palette
      colorUsed = api.document.pal.def[i]
    else
      -- fall back to the 16 default colors
      colorUsed = colors.packRGB(term.nativePaletteColor(pow2LUT[i]))
    end
    viewport.setPaletteColor(pow2LUT[i], colorUsed)
    term.setPaletteColor(pow2LUT[i], colorUsed)
    documentRender.setPaletteColor(pow2LUT[i], colorUsed)
    infobar.setPaletteColor(pow2LUT[i], colorUsed)
    local colorAverage = _ca(colorUsed)
    if colorAverage < darkest then
      darkest = colorAverage
      api.hudBG = pow2LUT[i]
    end
    if colorAverage > brightest then
      brightest = colorAverage
      api.hudFG = pow2LUT[i]
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
    api.furthestColorLUT[ac] = api.furthestColorLUT[ac] or "0"
    local aAve = _cl(colorsUsed[a])
    for b = 0, 15 do -- really, nested loops??
      -- calculate which b color is furthest from a
      local bc = ("%x"):format(b)
      local diff = math.abs(_cl(colorsUsed[b]) - aAve) -- redundant calculations
      if diff > largestDiff then
        -- these colors are further apart
        api.furthestColorLUT[ac] = bc
        largestDiff = diff
      end
    end
  end
  viewport.setBackgroundColor(api.hudBG)
  viewport.clear()
  api.resetFooter()
end

-- loading/saving interface
-- load(f) where f is file handle
-- save(f) where f is file handle
-- return boolean of success, and an optional message
local function loadFile(fn)
  local f = fs.open(fn, "rb")
  if f then
    if fn:sub(-INTERNAL_FORMAT_EXTENSION:len()) == INTERNAL_FORMAT_EXTENSION then
      local bt = textutils.unserialise(f.readAll())
      if bt then
        api.document = bt
        api.resetFooter()
        undoBuffer = {}
      else
        api.setFooter("Invalid file")
      end
    elseif formatLUT.load[fn:sub(-3)] then
      local status, message = formatLUT.load[fn:sub(-3)](f)
      if status then
        api.setFooter(message or "Successfully opened file")
        api.activeLayer = 1
        local x, y = api.getCursorPos()
        api.offsetCursor(-x, -y)
        applyPalette()
        api.getDocumentSize()
      else
        api.setFooter(message or "Error opening file")
      end
    elseif formatLUT.load[fn:sub(-4)] then
      local status, message = formatLUT.load[fn:sub(-4)](f)
      if status then
        api.fullRender = true
        api.setFooter(message or "Successfully opened file")
        api.activeLayer = 1
        local x, y = api.getCursorPos()
        api.offsetCursor(-x, -y)
        applyPalette()
        api.getDocumentSize()
      else
        api.setFooter(message or "Error opening file")
      end
    else
      api.setFooter("Unsupported format")
    end
    f.close()
  else
    api.setFooter("Unable to open file")
  end

end

local function saveFile(fn)
  local f = fs.open(fn, "wb")
  if f then
    if fn:sub(-INTERNAL_FORMAT_EXTENSION:len()) == INTERNAL_FORMAT_EXTENSION then
      f.write(textutils.serialise(api.document,{compact=true}))
      api.setFooter("Saved file")
    elseif formatLUT.save[fn:sub(-3)] then
      local status, message = formatLUT.save[fn:sub(-3)](f)
      if status then
        api.setFooter(message or "Successfully saved file")
      else
        api.setFooter(message or "Error saving file")
      end
    elseif formatLUT.save[fn:sub(-4)] then
      local status, message = formatLUT.save[fn:sub(-4)](f)
      if status then
        api.setFooter(message or "Successfully saved file")
      else
        api.setFooter(message or "Error saving file")
      end
    else
      api.setFooter("Unsupported format")
    end
    f.close()
  else
    api.setFooter("Unable to open file")
  end
end

-- takes an initialization function for a plugin
-- sets the env properly, and calls it
local function registerPlugin(func)
  setfenv(func, _PLUGIN_ENV)
  local pluginInfo = {func()} -- this should initialize all listeners, keys, etc
  api.loadedPlugins[#api.loadedPlugins+1] = pluginInfo
  assert(pluginInfo[1], "Plugin did not return a name")
  if pluginInfo[2] then
    print(("[%s](%s) Loaded"):format(pluginInfo[1],pluginInfo[2]))
  else
    print(("[%s] Loaded"):format(pluginInfo[1]))
  end
end


--- HERE are the default plugins
-- any of the contents of these functions *could* be placed into their own file, and loaded externally

-- This plugin manages the `control+a` left margin stuff, and the enter keybind
local function marginPlugin()
  -- initialization function for the margin plugin, a default plugin
  api.requirePlugin("basicKeys", "margin")
  local leftMargin = 1
  local rightMargin = 1
  local useRightMargin = false
  addEventHandler("render",function()
    -- add a marker for the current X anchor position
    local x = leftMargin - offset[1] + 2
    if x > 0 and x < resx then
      term.setCursorPos(x,1)
      term.write("\25")
    end
    if useRightMargin then
      x = rightMargin - offset[1] + 2
      if x > 0 and x < resx then
        term.setCursorPos(x,1)
        term.write("\25")
      end
    end
  end)
  addEventHandler("char",function()
    local x, _ = api.getCursorPos()
    if useRightMargin and x > rightMargin then
      api.offsetCursor(leftMargin-x, 1)
    end
  end) -- this should occur before the main char event
  addEventHandler("key",function(key)
    local x, _ = api.getCursorPos()
    if useRightMargin and key == keys.backspace and x == leftMargin then
      api.offsetCursor(rightMargin-leftMargin+1,-1)
    end
  end)
  addKey(keys.enter,function()
    local xpos, _ = api.getCursorPos()
    api.offsetCursor(leftMargin-xpos,1)
  end)
  addKey(keys.a,function()
    leftMargin, _ = api.getCursorPos()
    api.setFooter(("Set lMargin to %u"):format(leftMargin))
  end,"Set left margin",{control=true})
  addKey(keys.e,function()
    rightMargin, _ = api.getCursorPos()
    useRightMargin = not useRightMargin
    if useRightMargin then
      api.setFooter(("Set rMargin to %u"):format(rightMargin))
    else
      api.setFooter("Disabled rMargin")
    end
  end, "Set right margin", {control=true})
  return "margin", "1.1"
end

-- This plugin adds a hidable color picker to the right side of the screen
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
        local fg = api.furthestColorLUT[char]
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
  return "colorPicker", "1.0"
end

-- This plugin adds the ability to use the mouse to drag around the canvas
-- this plugin also adds "paint mode"
local function mouseControlPlugin()
  local mouseAnchor = {1,1}
  local paintMode = false
  local paintChar = " "
  local paintLength = 0
  addEventHandler("mouse_drag", function(button,x,y)
    if x > 1 and y > 1 and y < resy-2 and x < resx then
      selPos = {x-1,y-1}
      if (not paintMode) or button > 1 then
        local dx, dy = mouseAnchor[1] - x, mouseAnchor[2] - y
        api.offsetViewport(dx,dy)
      elseif paintMode then
        api.writeChar(paintChar)
        paintLength = paintLength + 1
      end
      mouseAnchor = {x,y}
    end
  end)
  addEventHandler("mouse_up", function()
    if paintLength > 0 then
      api.addMultiUndo(paintLength) -- indicate this is a group undo
      paintLength = 0
    end
  end)
  addEventHandler("mouse_click",function(button,x,y)
    if x > 1 and y > 1 and y < resy - 2 and x < resx then
      -- click on document area
      selPos = {x-1,y-1}
      if paintMode and button == 1 then
        -- left click and paint mode
        api.writeChar(paintChar)
        paintLength = 1
      end
    end
    mouseAnchor = {x,y}
  end)
  addEventHandler("mouse_scroll",function(dir)
    if api.controlHeld then
      api.offsetViewport(dir*3,0)
    else
      api.offsetViewport(0, dir*3)
    end
  end)
  addKey(keys.p,function()
    if not paintMode then
      -- ask what character to paint with
      local char = tonumber(api.getFooter("Character code? "))
      if char then
        paintChar = string.char(char)
        paintMode = true
        api.setFooter("Paint mode enabled")
      else
        api.setFooter("Invalid character code")
      end
    else
      paintMode = false
      api.setFooter("Paint mode disabled")
    end
  end,"Toggle paint mode", {control=true})

  return "basicMouse", "1.0"
end

-- This plugin adds basic movement controls like arrows, home, and layer naviagtion
local function movementKeyPlugin()
  addKey(keys.backspace,function()
    api.offsetCursor(-1,0)
    api.writeChar()
  end)
  addKey(keys.delete,function()
    api.writeChar()
  end)
  addKey(keys.home,function()
    local x, y = api.getCursorPos()
    api.offsetCursor(-x,0)
  end)
  addKey(keys.left,function()
    api.offsetCursor(-1,0)
  end)
  addKey(keys.right,function()
    api.offsetCursor(1,0)
  end)
  addKey(keys.up,function()
    api.offsetCursor(0,-1)
  end)
  addKey(keys.down,function()
    api.offsetCursor(0,1)
  end)
  addKey(keys.l,function()
    local targetLayer = tonumber(api.getFooterDefault("Layer [%u]? ", api.activeLayer))
    if targetLayer and targetLayer > 0 then
      api.activeLayer = targetLayer
      api.resetFooter()
      applyPalette()
      undoBuffer = {} -- empty the undo buffer
    else
      api.setFooter("Invalid layer")
    end
  end,"Change layer",{control=true})
  addKey(keys.g, function()
    local currentx, currenty = api.getCursorPos()
    local targetx = tonumber(api.getFooterDefault("X [%u]? ", currentx))
    local targety = tonumber(api.getFooterDefault("Y [%u]? ", currenty))
    if targetx and targety then
      api.offsetCursor(targetx-currentx,targety-currenty)
    end
    api.resetFooter()
  end, "Goto", {control=true})

  return "basicKeys", "1.0"
end

-- This plugin adds some basic features for editing
local function editingPlugin()
  addKey(keys.f,function()
    local char = tonumber(api.getFooter("Character code? "))
    if char and char >= 0 and char <= 255 then
      local width = tonumber(api.getFooterDefault("Width [%u]? ",1))
      local height = tonumber(api.getFooterDefault("Height [%u]? ",1))
      if width and height and width > 0 and height > 0 then
        local x, y = api.getCursorPos()
        for dx = 1, width do
          for dy = 1, height do
            api.setChar(x+dx-1, y+dy-1, string.char(char))
          end
        end
        api.offsetCursor(width,height-1)
        api.resetFooter()
        api.addMultiUndo(width*height) -- indicate this is a group undo
      else
        api.setFooter("Invalid size")
      end
    else
      api.setFooter("Invalid color code")
    end
  end,"Fill",{control=true})
  addKey(keys.i,function()
    local maxx, maxy, maxlayer = table.unpack(api.getDocumentSize())
    local pagen = math.ceil(maxx/api.PAPER_WIDTH) * math.ceil(maxy/api.PAPER_HEIGHT)
    local pagetotal = pagen * maxlayer
    local cursorPos = {api.getCursorPos()}
    api.setFooter(string.format("%ux%u[%uPT @ %uP/L](%uL) Curs@(%u,%u)", maxx, maxy, pagetotal, pagen, maxlayer,cursorPos[1],cursorPos[2]))
    -- x by y [pages total@pages per layer](layers)@(xpos,ypos)
  end,"Info",{control=true})
  addKey(keys.d,function()
    local targetFG = tonumber(api.getFooterDefault("Default FG [%s]? ", api.selectedFG),16)
    local targetBG = tonumber(api.getFooterDefault("Default BG [%s]? ", api.selectedBG),16)
    if targetBG and targetBG <= 15 and targetBG >= 0 and targetFG and targetFG <= 15 and targetFG >= 0 then
      -- valid
      api.selectedBG = string.format("%x", targetBG)
      api.selectedFG = string.format("%x", targetFG)
      api.setFooter("Changed colors")
    else
      api.setFooter("Invalid colors")
    end
  end,"Change default background",{control=true})
  addKey(keys.b,function()
    local changeDef = api.getFooterConfirm("Change default (y/*)? ")
    local blitChar = tonumber(api.getFooter("Blit Char? "),16)
    if blitChar and blitChar >= 0 and blitChar <= 15 then
      api.document.pal = api.document.pal or {}
      api.document.pal.def = api.document.pal.def or {}
      local currentCol
      if changeDef then
        currentCol = (api.checkExists(api.document, "pal", "def") and api.document.pal.def[blitChar]) or term.nativePaletteColor(2^blitChar)
      else
        currentCol = (api.checkExists(api.document, "pal", api.activeLayer) and api.document.pal[api.activeLayer][blitChar]) or term.nativePaletteColor(2^blitChar)
      end
      local newCol = tonumber(api.getFooterDefault("Color [%6x]? ", currentCol))
      local layer = (changeDef and api.document.pal.def) or api.document.pal[api.activeLayer]
      if newCol >= 0 and newCol <= 0xFFFFFF then
        layer[blitChar] = newCol
        applyPalette()
        api.setFooter("Color applied")
      else
        api.setFooter("Invalid color")
      end
    else
      api.setFooter("Invalid blit char")
    end
  
  end, "Change palette color", {control=true})
  addKey(keys.m,function()
    local offsetx = tonumber(api.getFooterDefault("X offset [%u]? ", 0))
    local offsety = tonumber(api.getFooterDefault("Y offset [%u]? ", 0))
    if offsetx and offsety then
      api.moveDocument(offsetx,offsety)
      undoBuffer = {} -- empty the undo buffer
    end
    api.resetFooter()
  end, "Move document", {control=true})
  addKey(keys.k,function()
    local currentWidth, currentHeight, currentLayers = table.unpack(api.getDocumentSize())
    local targetWidth = tonumber(api.getFooterDefault("Width ("..api.PAPER_WIDTH.."pp) [%u]: ", currentWidth))
    local targetHeight = tonumber(api.getFooterDefault("Height ("..api.PAPER_HEIGHT.."pp) [%u]: ",currentHeight))
    local targetLayers = tonumber(api.getFooterDefault("Layers [%u]: ",currentLayers))
    if targetWidth and targetHeight and targetLayers then
      api.cropDocument(targetWidth, targetHeight,targetLayers)
      api.resetFooter()
    else
      api.setFooter("Invalid input.")
    end
  end, "Crop", {control=true})
  addEventHandler("char",function(char)
    api.writeChar(char)
    api.offsetCursor(1,0)
  end)
  return "basicEditing", "1.0"
end

-- This plugin adds some ruler rendering features
local function rulersPlugin()
  addEventHandler("render", function()
    -- generate the horizontal ruler
    local hozruler = ""
    local sideString = string.rep(" ", math.floor((api.PAPER_WIDTH-2-3)/2))
    -- possible bug for if paper width is even
    for x = math.ceil(offset[1]/api.PAPER_WIDTH)-1,
    math.ceil((offset[1]+resx)/api.PAPER_WIDTH) do
      hozruler = hozruler..
      string.format("|"..sideString.."%3u"..sideString.."|", x)
    end
    term.setBackgroundColor(api.hudBG)
    term.setTextColor(api.hudFG)
    term.setCursorPos(2,1)
    term.write(hozruler:sub(((offset[1]-1)%api.PAPER_WIDTH)+1+api.PAPER_WIDTH))

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
      term.setCursorPos(1,y)
      term.write(verruler:sub(sindex,sindex))
      sindex = sindex + 1
    end
  end)

  return "rulers", "1.0"
end

-- this plugin adds a modifier key indicator in the top left corner
local function keyIndicatorPlugin()
  local control = 2^2
  local alt = 2^3
  local shift = 2^0
  local keyIndicatorSpot = window.create(viewport,1,1,1,1)
  addEventHandler("render", function()
    keyIndicatorSpot.setCursorPos(1,1)
    local char = ((api.controlHeld and control) or 0 )
    char = char+((api.altHeld and alt) or 0)
    char = char+((api.shiftHeld and shift) or 0)
    char = char + 128
    keyIndicatorSpot.setBackgroundColor(api.hudBG)
    keyIndicatorSpot.setTextColor(api.hudFG)
    keyIndicatorSpot.write(string.char(char))
  end)
  return "keyIndicator", "1.1"
end

--- Always enabled bare minimum keybinds and event listeners
local function registerDefault()
  print("Registering base keys..")
  addKey(keys.q, function()
    if api.getFooterConfirm("Really quit? ") then
      running = false
    end
    api.resetFooter()
  end, "Quit", {control=true})
  addKey(keys.h,function() -- TODO, redo this
    term.setBackgroundColor(api.hudBG)
    term.setTextColor(api.hudFG)
    term.clear()
    term.setCursorPos(1,1)
    local t = {"",""}-- couple blank strings to counter repeated char events
    for k,v in pairs(keyLookup) do
      if v.help then
        t[#t+1] = v.help
      end
    end
    textutils.pagedPrint(table.concat(t,"\n"))
    print("Press enter to continue")
    ---@diagnostic disable-next-line: discard-returns
    io.read()
    api.resetFooter()
  end, "Help", {control=true})
  addKey(keys.o,function()
    local fn = api.getFooter("Open file? ")
    if fn ~= "" then
      loadFile(fn)
    else
      api.resetFooter()
    end
  end,"Open",{control=true})
  addKey(keys.s,function()
    local fn = api.getFooter("Save file? ")
    if fn ~= "" then
      saveFile(fn)
    else
      api.resetFooter()
    end
  end,"Save",{control=true})
  addKey(keys.z,function()
    api.undo()
  end, "Undo", {control=true})

  addEventHandler("key", function(code)
    if code == keys.leftCtrl then
      if api.toggleMods then
        api.controlHeld = not api.controlHeld
      else
        api.controlHeld = true
      end
    elseif code == keys.leftAlt then
      if api.toggleMods then
        api.altHeld = not api.altHeld
      else
        api.altHeld = true
      end
    elseif code == keys.leftShift then
      if api.toggleMods then
        api.shiftHeld = not api.shiftHeld
      else
        api.shiftHeld = true
      end
    else
      -- perform lookup into shortcut table
      code = code + ((api.controlHeld and CONTROL_HELD) or 0)
      code = code + ((api.altHeld and ALT_HELD) or 0)
      code = code + ((api.shiftHeld and SHIFT_HELD) or 0)
      if keyLookup[code] then
        keyLookup[code].func()
        api.controlHeld = false
        api.altHeld = false
        api.shiftHeld = false
      end
    end
  end)
  addEventHandler("key_up",function(code)
    if code == keys.leftCtrl and not api.toggleMods then
      api.controlHeld = false
    elseif code == keys.leftAlt and not api.toggleMods then
      api.altHeld = false
    elseif code == keys.leftShift and not api.toggleMods then
      api.shiftHeld = false
    end
  end)
end

local internalPluginsList = {
  -- order list
  "basicKeys",
  "basicMouse",
  "rulers",
  "margin",
  "colorPicker",
  "basicEditing",
  "keyIndicator",
  "bbf",
  "bimg",
  -- function lookup
  margin=marginPlugin,
  colorPicker=colorPickerPlugin,
  basicMouse=mouseControlPlugin,
  bbf=bbfPlugin,
  bimg=bimgPlugin,
  basicKeys=movementKeyPlugin,
  basicEditing=editingPlugin,
  keyIndicator=keyIndicatorPlugin,
  rulers=rulersPlugin,
}

local function loadPlugins()
  local function _writeDefaultPlugins(f)
    for k,v in ipairs(internalPluginsList) do
      f.writeLine("!"..v)
      registerPlugin(internalPluginsList[v])
    end
  end
  if fs.exists("gplugins") then
    if fs.exists("gplugins/plugins") then
      local f = assert(fs.open("gplugins/plugins","r"))
      local pluginNames = {}
      repeat
        local fn = f.readLine()
        if fn and fn:sub(1,1) ~= "#" then
          -- ignore lines with # at the start
          pluginNames[#pluginNames+1] = fn
        end
      until fn == nil
      f.close()
      for i,n in ipairs(pluginNames) do
        local f, err
        if n:sub(1,1) == "!" then
          f = internalPluginsList[n:sub(2)]
          err = "Invalid internal plugin"
        else
          f, err = loadfile(fs.combine("gplugins/",n), nil)
        end
        if f then
          registerPlugin(f)
        else
          print(string.format("Unable to load plugin %s: %s",n, err))
          print("Push enter to continue, anything else to exit")
          local e,k = os.pullEvent("key")
          if k ~= keys.enter then
            return false
          end
        end
      end
    else
      local f = fs.open("gplugins/plugins","w")
      _writeDefaultPlugins(f)
      f.close()
    end
  else
    fs.makeDir("gplugins")
    local f = fs.open("gplugins/plugins","w")
    _writeDefaultPlugins(f)
    f.close()
  end
  return true
end

local function tick()
  callEventHandlers("main")
  local event = {os.pullEventRaw()}
  if event[1] == "terminate" then
    running = false
  else
    callEventHandlers(event[1], table.unpack(event, 2))
  end
  if event[1] == "term_resize" then
    resx, resy = term.getSize()
    infobar.reposition(1,resy-1,resx,2)
    viewport.reposition(1,1,resx,resy-2)
  end
end

local function main(arg)
  registerDefault()
  if not loadPlugins() then
    return
  end
  print(("Plugins loaded. GIIM v%s"):format(api.GIIM_VERSION))
  -- if a filename is passed in, attempt to load that image
  if arg[1] then
    loadFile(arg[1])
  end
  applyPalette()
  api.resetFooter()
  while running do
    renderAll()
    tick()
  end
  for i = 0, 15 do
    term.setPaletteColor(pow2LUT[i], term.nativePaletteColor(pow2LUT[i]))
  end
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1,1)
  print(("Thank you for using GIIM v%s"):format(api.GIIM_VERSION))
  print("Licensed under MIT, source available at:")
  print("https://github.com/MasonGulu/cc-giim")
end



main({...})
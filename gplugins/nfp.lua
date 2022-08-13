addFormat("nfp", function(f) -- save
  local layer = api.document.im[api.activeLayer]
  local res = api.getDocumentSize()
  for y = 1, res[2] do
    local lineStr = {}
    local line = layer[y] or {}
    for x = 1, res[1] do
      local blit = line[x] or {[3]=api.selectedBG}
      lineStr[x] = blit[3]
    end
    f.write(table.concat(lineStr).."\n")
  end
  return true, "NFP saved, detail may be lost!"
end, function(f) -- load
  api.document = {im={{}}}
  local y = 1
  repeat
    local line = f.readLine()
    if line == nil then break end
    api.document.im[1][y] = {}
    local lineTab = api.document.im[1][y]
    for char in line:gmatch(".") do
      lineTab[#lineTab+1] = {"\143", char, char}
    end
    y = y + 1
  until line == nil
  return true
end)

return "nfp", "1.0"
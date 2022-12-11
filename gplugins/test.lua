local win = window.create(viewport, 2, 2, 20,1)
local i = 0

addEventHandler("render", function()
  win.setVisible(false)
  win.setCursorPos(1,1)
  win.write(i)
  i = i + 1
  win.setVisible(true)
end)

return "test"
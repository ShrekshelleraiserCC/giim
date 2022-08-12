--- This is an example plugin
-- All this does is add a feature where 
-- upon pressing control+alt+shift D
-- all of the loaded plugins will be printed out.

-- Register a key
addKey(keys.d, function()
  term.clear() -- term is actually a reference to the docWin.
  term.setCursorPos(1,1)
  for k,v in ipairs(api.loadedPlugins) do
    print(k, v[1], v[2])
  end
  print("click")
  os.pullEvent("mouse_click")
end, "DEBUG", {control=true,alt=true,shift=true})
-- These are all the allowed modifiers

return "debug-demo" -- return the plugin name (excluding the version in this example)
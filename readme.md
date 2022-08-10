
# GIIM
A weird text/image editor that looks vaguely like VIM. You can type a filename as you run the script to open the image directly, 
otherwise push control+o to open a document.

## Supported formats
GIIM currently supports saving and loading in

* [BIMG](https://github.com/SkyTheCodeMaster/bimg)
* [BBF](https://github.com/9551-Dev/BLBFOR)
* GIIM - incredibly large internal file format, currently offers no advantage over either of the other 2 formats.

The format used is determined solely by the file extension.

## PLUGINS
In order to make a plugin, simply make a normal `lua` file in the `gplugins` directory. The file should return the plugin's name, and the plugin's version.

You have access to a few registry functions, and the entire api table (look in `giim.lua` for more info).

`addKey(keycode, func, info, modifiers)` This function allows you to register callback functions that will be called on the set keybind being pressed.

`addFormat(name, save, load)` This function allows you to add a save/load function to add support for other image and document formats. More details below.

* `save(f) : boolean, string` 
  * `f` is the file handle to the file to save. 
  * Returns boolean of success.
  * And returns message to display (optional).
* `load(f) : boolean | string` 
  * `f` is the file handle to the file we wish to open
  * should modify `api.document` to match the loaded document
  * Returns boolean of success.
  * And returns message to display (optional)

`addEventHandler(name,func)` This function allows you to add an event handler. The `func` provided should take `table.unpack({os.pullEvent},2)` as its parameters. There are 2 special event names, `render` which runs every frame after drawing the rulers and image but before making the window visible again, and `main`, which runs every frame after `render`, but before `os.pullEvent`. If you return `true` then all event handlers for this function that were registered before this plugin was will be skipped.


### Example

```lua
addKey(keys.e, function()
  api.writeChar("!")
end, "Example plugin", {control=true,shift=true})

return "examplePlugin", "1.0" -- your plugin should return a name at least, version is optional but allows for interplugin operation
```
For more examples, look in `giim.lua` in the lower sections of the files. There are several built in plugins.

### Plugin loading
In `gplugins/` there is a file `plugins`, simply write a single filename per line, the plugins will be loaded in the order that they are in the file.

Lines beginning with # are treated as comments, and will not be loaded. Lines beginning with `!` mark an internal plugin, you can disable internal plugins, but doingso without an adequite replacement may render the editor unusable. When generating a new `gplugins/plugin` file, the default plugins are automatically populated.
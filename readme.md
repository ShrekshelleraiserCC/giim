
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
In order to make a plugin, simply make a normal `lua` file in the `gplugins` directory.

You have access to a few registry functions, and the entire api table (look in `giim.lua` for more info).

`addKey(keycode, func, info, modifiers)` This function allows you to register callback functions that will be called on the set keybind being pressed.

`addFormat(name, save, load)` This function allows you to add a save/load function to add support for other image and document formats. More details below.

* `save(f) : boolean, string` 
  * `f` is the file handle to the file to save. 
  * Returns boolean of success.
  * And returns message to display (optional).
* `load(f) : nil | table` 
  * `f` is the file handle to the file we wish to open
  * Returns boolean of success.
  * And returns message to display (optional)

`addEventHandler(name,func)` This function allows you to add an event handler. The `func` provided should take `table.unpack({os.pullEvent},2)` as its parameters. There are 2 special event names, `render` which runs every frame after drawing the rulers and image but before making the window visible again, and `main`, which runs every frame after `render`, but before `os.pullEvent`.
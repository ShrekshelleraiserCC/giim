
# GIIM
A weird text/image editor that looks vaguely like VIM. You can type a filename as you run the script to open the image directly, 
otherwise push control+o to open a document.

## Supported formats
GIIM currently supports saving and loading in

* [BIMG](https://github.com/SkyTheCodeMaster/bimg)
* [BBF](https://github.com/9551-Dev/BLBFOR)
* GIIM - incredibly large internal file format, currently offers no advantage over either of the other 2 formats.

The format used is determined solely by the file extension.

### Plugin support??
File should just be a onetime executable. The _ENV of the file will be set to contain some API features. 

Can inject its code into the render routine, and into the main event loop

### Custom formats support???
Add a directory containing scripts named by file extension.

these scripts should follow a typical `require` format, returning a table of functions after execution.

This table of functions should contain at least 1 of the following:

* `save(t,f) : boolean, string` 
  * `t` is a table in the GIIM internal format
  * `f` is the file handle to the file to save. 
  * Returns boolean of success.
  * And returns message to display (optional).
* `load(f) : nil | table` 
  * `f` is the file handle to the file we wish to open
  * Return `nil` or a table in the GIIM internal format
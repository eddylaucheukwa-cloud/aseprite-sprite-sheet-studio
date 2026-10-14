local root=app.fs.joinPath(app.fs.userConfigPath,'extensions','sprite-sheet-studio')
local studio=dofile(app.fs.joinPath(root,'main.lua'))
studio.show(root)

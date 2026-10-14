local root=app.params.root
app.fs.makeAllDirectories(app.fs.joinPath(root,'test-output'))
local M=dofile(app.fs.joinPath(root,'core.lua'))
local E=dofile(app.fs.joinPath(root,'effects.lua'))
local pc=app.pixelColor
local square=M.layout{cellWidth=64,cellHeight=64,columns=8,rows=10}
assert(square.capacity==80 and square.width==512 and square.height==640)
assert(M.position(80,square)==Point(448,576))
for _,invalid in ipairs({{cellWidth=0},{cellHeight=-1},{columns=1.5},{rows='bad'},
  {columns=1025},{cellWidth=16385},{cellWidth=4096,cellHeight=4096,columns=2,rows=2}}) do
  assert(not pcall(M.layout,invalid),'Invalid or oversized layouts must be rejected')
end

local layout=M.layout{cellWidth=32,cellHeight=48,columns=8,rows=10}
local entries={}
for slot=1,80 do
  local image=Image(32,48,ColorMode.RGB)
  image:drawPixel(1,2,pc.rgba(slot,10,20,127))
  entries[slot]={name='Sprite '..slot,image=image}
end
local state=M.newSheet(entries,layout)
assert(not pcall(M.newSheet,{{name='wrong size',image=Image(64,64,ColorMode.RGB)}},layout),
  'Custom imports must reject the wrong sprite resolution before making a document')
assert(state.sprite.width==256 and state.sprite.height==480 and state.layout.capacity==80)
for slot=1,80 do assert(state.slots[slot].position==M.position(slot,layout)) end
local output=app.fs.joinPath(root,'test-output','layout-80.aseprite')
state.sprite:saveAs(output)
local reopened=app.open(output)
state=M.fromSprite(reopened)
assert(state.layout.cellWidth==32 and state.layout.cellHeight==48 and state.layout.columns==8 and state.layout.rows==10)
assert(M.editSheet(reopened,M.layout()).sprite==reopened,'Saved projects must restore their own layout')
local first=Image(M.cellImage(state,1))
M.swap(state,1,80)
assert(M.cellImage(state,80):isEqual(first))
M.flip(state,{[80]=true},false)
assert(M.cellImage(state,80):getPixel(30,2)==first:getPixel(1,2))
local copies=M.copy(state,{[80]=true})
M.remove(state,{[79]=true})
assert(M.paste(state,copies,79)[1]==79)
assert(not pcall(M.paste,state,{{name='wrong',image=Image(64,64,ColorMode.RGB)}},1))
assert(E.apply(state,{[80]=true},{brightness=50}),'Recolor must include cells past 40')
assert(#E.frames('1-80',80)==80 and table.concat(E.frames('77-80',80),',')=='77,78,79,80')
assert(#E.frames('1-512',512)==512,'All frames must work for grids larger than 400 cells')
local png=app.fs.joinPath(root,'test-output','layout-80.png')
M.exportPNG(state,png)
local image=Image{fromFile=png}
assert(image.width==256 and image.height==480 and pc.rgbaA(image:getPixel(254,434))==127)
local original=Image(reopened)
app.activeSprite=reopened
app.command.FlattenLayers()
local split=M.editSheet(reopened)
assert(split.sprite~=reopened and #split.sprite.layers==80 and Image(split.sprite):isEqual(original),
  'Flattened custom sheets must split losslessly using their saved layout')
local flat=Sprite(256,480,ColorMode.RGB)
flat.cels[1].image=image
local fromPNG=M.editSheet(flat,layout)
assert(#fromPNG.sprite.layers==80 and Image(fromPNG.sprite):isEqual(image))
assert(not pcall(M.editSheet,flat,M.layout()),'A mismatched flat layout must be rejected without cropping')

local folder=app.fs.joinPath(root,'test-output','custom-size-folder')
app.fs.makeAllDirectories(folder)
entries[1].image:saveAs(app.fs.joinPath(folder,'frame0015.png'))
entries[2].image:saveAs(app.fs.joinPath(folder,'frame0005.png'))
local imported=M.importFolder(folder,layout)
assert(imported.slots[1].image:getPixel(1,2)==entries[2].image:getPixel(1,2))
local added=M.addFolder(imported,folder)
assert(added.slots[4] and added.layout.capacity==80)
app.activeSprite=added.sprite
app.command.Undo()
assert(not M.fromSprite(added.sprite).slots[4])
app.command.Redo()
assert(M.fromSprite(added.sprite).slots[4])

local legacy=M.newSheet{{name='legacy',image=Image(64,64,ColorMode.RGB)}}
legacy.sprite.properties.sheetBuilderLayout=nil
assert(M.fromSprite(legacy.sprite).layout.capacity==40,'Old saved projects must remain editable')
assert(state.layout.capacity==80,'Different documents must not share mutable layout settings')
print('PASS: 8x10/80 cells, rectangular sprites, validation, imports/add/Undo, positions, save/reopen, high-cell swap/flip/copy/paste/recolor, export, lossless flatten split, legacy layouts and document isolation')

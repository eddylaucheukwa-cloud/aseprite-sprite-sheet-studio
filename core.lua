local M = { cell = 64, columns = 4, capacity = 40, width = 256, height = 640 }

function M.layout(options)
  options = options or {}
  local layout = {}
  for _,key in ipairs({'cellWidth','cellHeight','columns','rows'}) do
    local defaults={cellWidth=64,cellHeight=64,columns=4,rows=10}
    local value=tonumber(options[key] or defaults[key])
    assert(value and value>=1 and value==math.floor(value), 'Enter positive whole numbers for sprite size and grid')
    layout[key]=value
  end
  layout.capacity=layout.columns*layout.rows
  layout.width=layout.cellWidth*layout.columns
  layout.height=layout.cellHeight*layout.rows
  assert(layout.capacity<=1024, 'Use at most 1024 cells')
  assert(layout.width<=16384 and layout.height<=16384 and layout.width*layout.height<=16777216,
    'Sheet is too large: use at most 16384 pixels per side and 16 million pixels total')
  return layout
end

local function dimensions(layout) return layout.width..'x'..layout.height end

local function naturalKey(name)
  return name:lower():gsub('%d+', function(n) return string.format('%020d', tonumber(n)) end)
end

function M.position(slot, layout)
  layout=layout or M.layout()
  assert(slot >= 1 and slot <= layout.capacity and slot==math.floor(slot), 'Cell must be between 1 and '..layout.capacity)
  return Point(((slot - 1) % layout.columns) * layout.cellWidth, math.floor((slot - 1) / layout.columns) * layout.cellHeight)
end

function M.listPNGs(folder, layout)
  layout=layout or M.layout()
  assert(app.fs.isDirectory(folder), 'Choose a folder containing your PNG exports')
  local files = {}
  for _, name in ipairs(app.fs.listFiles(folder)) do
    local path = app.fs.joinPath(folder, name)
    if name:lower():match('%.png$') and app.fs.isFile(path) then files[#files + 1] = path end
  end
  table.sort(files, function(a, b)
    local ka, kb = naturalKey(app.fs.fileName(a)), naturalKey(app.fs.fileName(b))
    if ka == kb then return a < b end
    return ka < kb
  end)
  assert(#files > 0, 'No PNG files were found in this folder')
  assert(#files <= layout.capacity, 'This sheet fits at most '..layout.capacity..' sprites. Increase the grid or choose fewer PNGs.')
  return files
end

local function validateEntries(entries, layout)
  for _, entry in ipairs(entries) do
    assert(entry.image.width == layout.cellWidth and entry.image.height == layout.cellHeight,
      (entry.name or 'Image') .. ': expected '..layout.cellWidth..'x'..layout.cellHeight..' pixels; no resizing or cropping was applied')
    assert(entry.image.colorMode == ColorMode.RGB, (entry.name or 'Image') .. ': export as an RGBA PNG first')
  end
end

function M.newSheet(entries, options)
  local layout=M.layout(options)
  assert(#entries > 0 and #entries <= layout.capacity, 'Import between 1 and '..layout.capacity..' sprites')
  validateEntries(entries, layout)
  local sprite = Sprite(layout.width, layout.height, ColorMode.RGB)
  sprite.gridBounds = Rectangle(0, 0, layout.cellWidth, layout.cellHeight)
  sprite.properties.sheetBuilderLayout=layout
  app.transaction('Import sprite sheet', function()
    for slot, entry in ipairs(entries) do
      local layer = slot == 1 and sprite.layers[1] or sprite:newLayer()
      layer.name = entry.name or ('Sprite ' .. slot)
      layer.properties.sheetBuilder = true
      layer.properties.sheetBuilderSource = entry.path or ''
      sprite:newCel(layer, 1, entry.image, M.position(slot,layout))
    end
  end)
  return M.fromSprite(sprite)
end

local function loadEntries(files)
  local entries = {}
  for _, path in ipairs(files) do
    entries[#entries + 1] = { name = app.fs.fileName(path), path = path, image = Image{ fromFile = path } }
  end
  return entries
end

function M.importFolder(folder, layout)
  return M.newSheet(loadEntries(M.listPNGs(folder,layout)),layout)
end

function M.addFolder(state, folder)
  state = M.fromSprite(state.sprite)
  local layout=state.layout
  local empty = {}
  for slot = 1, layout.capacity do
    if not state.slots[slot] then empty[#empty + 1] = slot end
  end
  local files = M.listPNGs(folder,layout)
  assert(#files <= #empty,
    'This folder has ' .. #files .. ' sprites, but only ' .. #empty .. ' cells are free. Nothing was added.')
  local entries = loadEntries(files)
  validateEntries(entries,layout)
  app.transaction('Add sprites from folder', function()
    for i, entry in ipairs(entries) do
      local layer = state.sprite:newLayer()
      layer.name = entry.name
      layer.properties.sheetBuilder = true
      layer.properties.sheetBuilderSource = entry.path
      state.sprite:newCel(layer, 1, entry.image, M.position(empty[i],layout))
    end
  end)
  return M.fromSprite(state.sprite)
end

function M.splitSheet(image, sourcePath, options)
  local layout=M.layout(options)
  assert(image.width == layout.width and image.height == layout.height, 'The existing sheet must be exactly '..dimensions(layout)..' pixels; change Sheet size first')
  local entries = {}
  for slot = 1, layout.capacity do
    local point = M.position(slot,layout)
    entries[slot] = { name = 'Sprite ' .. slot, path = sourcePath,
      image = Image(image, Rectangle(point.x, point.y, layout.cellWidth, layout.cellHeight)) }
  end
  return M.newSheet(entries,layout)
end

function M.editSheet(sprite, options)
  local layout=M.layout(sprite.properties.sheetBuilderLayout or options)
  assert(sprite.width == layout.width and sprite.height == layout.height and #sprite.frames == 1,
    'Open a '..dimensions(layout)..' sheet with one timeline frame; change Sheet size to match your PNG')
  local valid, state = pcall(M.fromSprite, sprite)
  if valid then return state end
  -- Render into RGBA so flattened indexed/grayscale sheets can also be edited.
  local image = Image(layout.width, layout.height, ColorMode.RGB)
  image:drawSprite(sprite, 1, Point(0, 0))
  return M.splitSheet(image, sprite.filename,layout)
end

function M.fromSprite(sprite)
  local layout=M.layout(sprite.properties.sheetBuilderLayout)
  assert(sprite.width == layout.width and sprite.height == layout.height and #sprite.frames == 1,
    'Open a '..dimensions(layout)..' Sheet Builder document with one frame')
  assert(sprite.colorMode == ColorMode.RGB, 'Make an RGBA editable copy with Edit current sheet')
  local state = { sprite = sprite, layout=layout, slots = {}, sourcePaths = sprite.properties.sheetBuilderSourcePaths or {} }
  for _, layer in ipairs(sprite.layers) do
    assert(layer.properties.sheetBuilder == true, 'This is a flat sheet. Use Edit current sheet to make an editable copy.')
    local cel = layer:cel(1)
    assert(cel, 'A sprite layer has no cel')
    assert(cel.image.width <= layout.cellWidth and cel.image.height <= layout.cellHeight, 'This sheet needs to be split into grid cells first')
    local x, y = cel.position.x, cel.position.y
    assert(x >= 0 and y >= 0 and x < layout.width and y < layout.height and x % layout.cellWidth == 0 and y % layout.cellHeight == 0,
      'A sprite is outside its grid cell')
    local slot = math.floor(y / layout.cellHeight) * layout.columns + math.floor(x / layout.cellWidth) + 1
    assert(not state.slots[slot], 'Two sprite layers occupy the same cell')
    state.slots[slot] = cel
    local path = layer.properties.sheetBuilderSource
    if path and path ~= '' then state.sourcePaths[path:lower()] = true end
  end
  return state
end

function M.cellImage(state, slot)
  M.position(slot,state.layout)
  local image = Image(state.layout.cellWidth, state.layout.cellHeight, ColorMode.RGB)
  local cel = state.slots[slot]
  if cel then image:drawImage(cel.image, Point(0, 0)) end
  return image
end

function M.swap(state, a, b)
  M.position(a,state.layout); M.position(b,state.layout)
  if a == b then return false end
  local first, second = state.slots[a], state.slots[b]
  if not first and not second then return false end
  app.transaction('Swap sprite cells', function()
    if first then first.position = M.position(b,state.layout) end
    if second then second.position = M.position(a,state.layout) end
  end)
  state.slots[a], state.slots[b] = second, first
  app.refresh()
  return true
end

function M.flip(state, selected, vertical)
  local hasSprite = false
  for slot in pairs(selected) do if state.slots[slot] then hasSprite=true; break end end
  if not hasSprite then return false end
  app.transaction(vertical and 'Flip sprites vertically' or 'Flip sprites horizontally', function()
    for slot in pairs(selected) do
      local cel = state.slots[slot]
      if cel then
        local image = Image(cel.image)
        image:flip(vertical and FlipType.VERTICAL or FlipType.HORIZONTAL)
        cel.image = image
      end
    end
  end)
  app.refresh()
  return true
end

function M.copy(state, selected)
  local entries = {}
  for slot = 1, state.layout.capacity do
    local cel = selected[slot] and state.slots[slot]
    if cel then
      entries[#entries + 1] = { image=Image(cel.image), name=cel.layer.name,
        path=cel.layer.properties.sheetBuilderSource }
    end
  end
  return entries
end

function M.remove(state, selected)
  local layers = {}
  for slot = 1, state.layout.capacity do
    if selected[slot] and state.slots[slot] then
      layers[#layers + 1] = state.slots[slot].layer
    end
  end
  if #layers == 0 then return false end
  app.transaction('Delete sprites', function()
    state.sprite.properties.sheetBuilderSourcePaths = state.sourcePaths
    for _, layer in ipairs(layers) do state.sprite:deleteLayer(layer) end
  end)
  for slot in pairs(selected) do state.slots[slot] = nil end
  return true
end

function M.paste(state, entries, startSlot)
  assert(entries and #entries > 0, 'Copy one or more sprites first')
  M.position(startSlot,state.layout)
  local targets = {}
  for offset = 0, state.layout.capacity - 1 do
    local slot = (startSlot - 1 + offset) % state.layout.capacity + 1
    if not state.slots[slot] then targets[#targets + 1] = slot end
    if #targets == #entries then break end
  end
  assert(#targets == #entries, 'Not enough empty cells to paste. Nothing was changed.')
  validateEntries(entries,state.layout)
  app.transaction('Paste sprites', function()
    for i, entry in ipairs(entries) do
      local layer = state.sprite:newLayer()
      layer.name = entry.name .. ' (copy)'
      layer.properties.sheetBuilder = true
      layer.properties.sheetBuilderSource = entry.path or ''
      local cel = state.sprite:newCel(layer, 1, Image(entry.image), M.position(targets[i],state.layout))
      state.slots[targets[i]] = cel
      if entry.path and entry.path ~= '' then state.sourcePaths[entry.path:lower()] = true end
    end
    state.sprite.properties.sheetBuilderSourcePaths = state.sourcePaths
  end)
  return targets
end

function M.exportPNG(state, path)
  assert(not state.sourcePaths[path:lower()], 'Choose a new output file; original input PNGs are protected')
  assert(path:lower():match('%.png$'), 'Choose a .png output filename')
  local image = Image(state.sprite)
  assert(image:saveAs(path), 'Could not save the PNG')
end

return M

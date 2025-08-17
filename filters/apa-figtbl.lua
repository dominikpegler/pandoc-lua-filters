local utils = require 'pandoc.utils'

local labels = { fig = {}, tbl = {} }      -- declared (header seen)
local realized = { fig = {}, tbl = {} }    -- actually transformed (image/table found)

local function is_org()
  return FORMAT and FORMAT:match('org')
end

local function norm_spaces(s)
  s = s:gsub('\194\160', ' ')     -- NBSP -> space
  s = s:gsub('%s+', ' ')
  return s:gsub('^%s+', ''):gsub('%s+$', '')
end

local function parse_ft_header(txt)
  local s = norm_spaces(txt)
  local n = s:match('^[Ff]igure%s+(%d+)$')
  if n then return 'fig', n end
  n = s:match('^[Tt]able%s+(%d+)$')
  if n then return 'tbl', n end
  return nil, nil
end

local function italics_caption_inlines(blk)
  if not blk or blk.t ~= 'Para' then return nil end
  local got = {}
  for _, inl in ipairs(blk.content) do
    if inl.t == 'Emph' then
      for _, ii in ipairs(inl.content) do table.insert(got, ii) end
    elseif inl.t == 'Space' or inl.t == 'SoftBreak' then
      table.insert(got, inl)
    else
      return nil
    end
  end
  if #got > 0 then return got end
  return nil
end

local function mk_caption_cap(inls)
  if pandoc.Caption then
    return pandoc.Caption({}, { pandoc.Plain(inls) })
  else
    return { short = {}, long = { pandoc.Plain(inls) } }
  end
end

-- Find first Image inline in a block (searching nested structures)
local function find_first_image(block)
  local found = nil
  local function walker(el)
    if el.t == 'Image' and not found then
      found = el
    end
    return nil
  end
  pandoc.walk_block(block, { Image = walker })
  return found
end

-- Search forward up to max_ahead blocks for a block containing an image/table
local function find_target_block(blocks, start_idx, kind, max_ahead)
  local limit = math.min(#blocks, start_idx + max_ahead)
  for j = start_idx, limit do
    local b = blocks[j]
    if kind == 'fig' then
      local img = b and find_first_image(b) or nil
      if img then return j, b, img end
    else
      if b and b.t == 'Table' then return j, b, nil end
    end
  end
  return nil, nil, nil
end

-- Build figure blocks for output
local function figure_blocks_for_output(img, id, cap_inls)
  if is_org then
    local cap_txt = utils.stringify(cap_inls or {})
    local header = '#+name: ' .. id .. '\n' .. '#+caption: ' .. cap_txt .. '\n'
    return {
      pandoc.RawBlock('org', header),
      pandoc.Para({ img })
    }
  elseif pandoc.Figure then
    -- Pandoc >= 3: native Figure
    local fig = pandoc.Figure(pandoc.Attr(id, {}, {}), mk_caption_cap(cap_inls or {}), { pandoc.Para({ img }) })
    return { fig }
  else
    -- Fallback: Div with id and figcaption paragraph
    local cap_para = (cap_inls and #cap_inls > 0) and pandoc.Para(cap_inls) or nil
    local content = { pandoc.Para({ img }) }
    if cap_para then table.insert(content, cap_para) end
    return { pandoc.Div(content, pandoc.Attr(id, {'figure'}, {})) }
  end
end

-- Build table blocks for output
local function table_blocks_for_output(tbl, id, cap_inls)
  if is_org then
    local cap_txt = utils.stringify(cap_inls or {})
    local header = '#+name: ' .. id .. '\n' .. '#+caption: ' .. cap_txt .. '\n'
    return {
      pandoc.RawBlock('org', header),
      tbl
    }
  else
    tbl.attr = tbl.attr or pandoc.Attr()
    tbl.attr.identifier = id
    tbl.caption = mk_caption_cap(cap_inls or {})
    return { tbl }
  end
end

-- Replace in-text "Figure N"/"Table N" with references, but only if realized
local function replace_refs_in_inlines(inlines)
  local res = {}
  local i = 1
  while i <= #inlines do
    local a = inlines[i]
    local replaced = false
    if a.t == 'Str' then
      local word = a.text
      local lw = word:lower()
      if lw == 'figure' or lw == 'table' then
        local j = i + 1
        while j <= #inlines and (inlines[j].t == 'Space' or inlines[j].t == 'SoftBreak') do
          j = j + 1
        end
        if j <= #inlines and inlines[j].t == 'Str' then
          local digits = inlines[j].text:match('^(%d+)$')
          if digits then
            local k = (lw == 'figure') and 'fig' or 'tbl'
            local id = (k == 'fig' and 'fig-' or 'tbl-') .. digits
            if realized[k][digits] then
              if is_org() then
                table.insert(res, pandoc.Str('ref:' .. id))
              else
                local disp = { pandoc.Str(word), pandoc.Space(), pandoc.Str(digits) }
                table.insert(res, pandoc.Link(disp, '#' .. id))
              end
              i = j + 1
              replaced = true
            end
          end
        end
      end
    end
    if not replaced then
      table.insert(res, a)
      i = i + 1
    end
  end
  return res
end

local function process_blocks(blocks)
  local out = {}
  local i = 1
  while i <= #blocks do
    local b = blocks[i]
    if b.t == 'Header' and b.level == 2 then
      local kind, num = parse_ft_header(utils.stringify(b.content))
      if kind and num then
        local id = (kind == 'fig' and 'fig-' or 'tbl-') .. num
        labels[kind][num] = id

        -- optional italic caption line
        local cap_inls = nil
        if i + 1 <= #blocks then
          cap_inls = italics_caption_inlines(blocks[i + 1])
        end
        local skip = 1
        if cap_inls then skip = 2 else cap_inls = {} end

        -- search ahead up to 5 blocks for the image/table
        local idx, target_blk, img = find_target_block(blocks, i + skip, kind, 5)

        -- Drop the header (and caption if present)
        if idx then
          if kind == 'fig' and img then
            realized.fig[num] = true
            -- Ensure image has id and (for non-org/non-Figure) caption carried
            img.attr = img.attr or pandoc.Attr()
            img.attr.identifier = id
            -- For Pandoc <= 2.x, image caption lives in its "alt-text"; for >=3.x, both work as content.
            img.caption = cap_inls
            local figs = figure_blocks_for_output(img, id, cap_inls)
            for _, blk in ipairs(figs) do table.insert(out, blk) end
          elseif kind == 'tbl' and target_blk.t == 'Table' then
            realized.tbl[num] = true
            local tbls = table_blocks_for_output(target_blk, id, cap_inls)
            for _, blk in ipairs(tbls) do table.insert(out, blk) end
          else
            -- Could not find matching content; just drop header/caption
          end
          -- advance past consumed blocks
          i = idx + 1
        else
          -- No target found; just drop header/caption
          i = i + skip + 1
        end
      else
        table.insert(out, b); i = i + 1
      end
    else
      table.insert(out, b); i = i + 1
    end
  end
  return out
end

function Pandoc(doc)
  doc.blocks = process_blocks(doc.blocks)
  -- Replace in-text references only for realized figures/tables
  doc = doc:walk({
    Para = function(el) el.content = replace_refs_in_inlines(el.content); return el end,
    Plain = function(el) el.content = replace_refs_in_inlines(el.content); return el end,
    Header = function(el) el.content = replace_refs_in_inlines(el.content); return el end,
  })
  return doc
end



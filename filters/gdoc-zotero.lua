local json = require 'pandoc.json'

local function extract_json(s)
  return s:match('%b{}') -- first {...}
end

local function inlines(s)
  if not s or s == '' then return {} end
  return { pandoc.Str(tostring(s)) }
end

local label_map = {
  page = 'p.', ['page-range'] = 'pp.', chapter = 'ch.', section = 'sec.',
  volume = 'vol.', number = 'no.', issue = 'no.', figure = 'fig.',
  table = 'tbl.', paragraph = 'para.', part = 'pt.', book = 'bk.',
  supplement = 'suppl.'
}

local function locator_suffix(label, locator)
  if not locator or locator == '' then return {} end
  local lab = label_map[label or ''] or label
  local suf = {}
  if lab and lab ~= '' then
    table.insert(suf, pandoc.Str(lab))
    table.insert(suf, pandoc.Space())
  end
  table.insert(suf, pandoc.Str(tostring(locator)))
  return suf
end

function Link(el)
  if not el.target:match('^https?://www%.zotero%.org/google%-docs/') then return nil end
  local js = extract_json(pandoc.utils.stringify(el.content))
  if not js then return nil end
  local ok, data = pcall(json.decode, js)
  if not ok or not data or not data.citationItems then return nil end

  local cites = {}
  for _, it in ipairs(data.citationItems) do
    local id =
      it['citation-key'] or
      (it.itemData and it.itemData['citation-key']) or
      (it.uris and it.uris[1]) or
      (it.id and tostring(it.id))
    if id then
      local mode = 'NormalCitation'
      if it['suppress-author'] then
        mode = 'SuppressAuthor'
      elseif it['authorInText'] or it['author-only'] then
        mode = 'AuthorInText'
      end
      local suf = locator_suffix(it.label, it.locator)
      local user_suf = inlines(it.suffix)
      if #user_suf > 0 then
        if #suf > 0 then table.insert(suf, pandoc.Space()) end
        for _, x in ipairs(user_suf) do table.insert(suf, x) end
      end
      local c = pandoc.Citation(id, mode, inlines(it.prefix), suf, 0, 0)
      table.insert(cites, c)
    end
  end
  if #cites > 0 then
    return pandoc.Cite({}, cites)
  end
end

function Para(el)
  if pandoc.utils.stringify(el):match('^ZOTERO_TRANSFER_DOCUMENT') then
    return {}
  end
end



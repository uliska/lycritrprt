local err, warn, info, log = luatexbase.provides_module({
    name               = "lycritrprt",
    version            = '0',
    date               = "2018/06/01",
    description        = "Module lycritrprt.",
    author             = "Urs Liska <ul@openlilylib.org>",
    copyright          = "2018 Urs Liska",
    license            = "GPL v3",
})

local lfs = require 'lfs'
local md5 = require 'md5'

local annotations = {}
local ANNOTATIONS = {}
local SCORES = {}
local source = {}
local util = {}

local lycritrprt = {}

local REPORTS = {}


---------------------------------
-- TEMPLATES
---------------------------------

local TEMPLATES = {}

--[[
  Each element of the TEMPLATES table is in itself a table with entries
  for different "styles". One entry 'default' is mandatory, adding more
  fields effectively adds different report styles.
  Each template style may consist either of a single value (as is the case
  with TEMPLATES.annotation) or a *flat* table (see TEMPLATES.ann_fields).

  Templates are retrieved with the TEMPLATES.get(type, style) function.
  If the requested style has not been defined for the requested template the
  'default' template is returned instead.
  If the template is a table of sub-items then a style may "override" all
  sub-items or only selected fields, in which case undefined fields are
  populated with the values of the default template.
--]]

--[[
  Templates for all supported annotation fields.
  Fields for which there are no templates are silently ignored
  (for example all the different fields about the rhythmic location).
  On the other hand this means that custom annotation fields can easily
  be supported by adding field templates.
  Each template is a table with one or two elements. If a second element
  is present this is used when the annotation field is not present. Otherwise
  the keyword in the template is simply removed.

  Items can be arbitrarily styled, and non-standard macros can be used
  when they are defined elsewhere.

  The top-level entries represent report styles. If a different style than
  'default' is requested then fields present in the given style will override
  the ones in the 'default' template.
  NOTE: This is not implemented yet.
--]]
TEMPLATES.ann_fields = {
  ['default'] = {
    ['measure-no'] = { [[<<<measure-no>>>)]] },
    ['beat-string'] =  { [[<<<beat-string>>> |]] },
    ['beat-string-lilyglyphs'] = { [[<<<beat-string-lilyglyphs>>>\ |]]},
    ['context-id'] = { [[<<<context-id>>>\\]] },
    ['message'] = { [[<<<message>>>]] },
    ['author'] = { [[\emph{(<<<author>>>, ]], [[\emph{(]]},
    ['type'] = { [[<<<type>>>)}]]},
    ['location'] = { [[\href{textedit://<<<location>>>}{Ursprung}]]}
  }
}


--[[
  Overall template for a single annotation entry.
  This defines the basic outline of a report entry, the order and selection
  of fields. The actual content of the fields (including behaviour for missing
  entries) is specified in the ann_fields template.

  The top-level entries represent report styles. If a different style than
  'default' is requested then fields present in the given style will override
  the ones in the 'default' template.
  NOTE: This is not implemented yet.
--]]
TEMPLATES.annotation = {
  ['default'] = [[
\begin{annotation}
<<<measure-no>>>
<<<beat-string-lilyglyphs>>>
<<<context-id>>>
<<<message>>>
<<<author>>><<<type>>>
<<<location>>>
\end{annotation}
]]
}

--[[
  Overall template for a single report.
--]]
TEMPLATES.report = {
  ['default'] = [[
\small
\setlength{\parindent}{0pt}
<<<entries>>>
\normalsize
]]
}


--[[
  Parse an annotation (string), create a table from it, add it to the
  corresponding annotations sub-table.
--]]
function annotations.add_annotation(text)
  local ann, score = annotations.parse_annotation(text)
  if not SCORES[score] then
     ANNOTATIONS[score] = {}
     SCORES[score] = score
   end
  table.insert(ANNOTATIONS[score], ann)
end


--[[
  Read the annotations (configured by the options argument),
  generate and return TeX code to print a report.

  NOTE: options currently is simply expected to contain a string
  key for the ANNOTATIONS.score table. All the configuration remains
  to be implemented.
--]]
function annotations.make(options)
  local ann_list = ANNOTATIONS[options['score-id']]
  result = ''
  for i, ann in ipairs(ann_list) do
    result = result..annotations.make_annotation(ann, options)
  end
  return result
end


--[[
  Interpolate a single entry within an annotation with the value
  from the annotation.
  If the entry is missing and an alternative field template is defined
  that is used, otherwise the empty value is interpolated with the
  regular template.
--]]
function annotations.interpolate(ann, element, tpl)
  local content = ann[element] or ''
  if ((content == '') and (#tpl == 2)) then
    return tpl[2]
  else
    return tpl[1]:gsub('<<<'..util.quote_hyphens(element)..'>>>', content)
  end
end


--[[
  Retrieve a template with a given style.
  If the requested style is not defined for the template
  the 'default' is returned.
  If the template is a table then fields from the style will
  override those from the default, using the default for fields
  not defined in the style.
--]]
function TEMPLATES.get(tpl_type, style)
  local tpl = TEMPLATES[tpl_type]
  if not tpl then err('Undefined template: '..tpl_type) end

  -- No specific style requested
  if not style then return tpl.default end

  -- Requested style is not defined
  if not tpl[style] then
    warn('No style "'..style..'" defined for template "'..tpl_type..'".\nFall back to default.')
    return tpl.default
  end

  -- We know there *is* a template for the style.
  -- If it's not a table, simple return it.
  if type(tpl[style]) ~= 'table' then return tpl[style] end

  -- Style template is a table. Fields defined in the style override defaults.
  local tpl_result = {}
  for k,v in pairs(tpl.default) do
    tpl_result[k] = tpl[style][k] or tpl.default[k]
  end

  return tpl_result
end


--[[
  Create and return a string of TeX code representing the given
  annotation.
  If options has a 'type' field then filter by that.
  NOTE: Currently it is only supported to filter by (i.e. include )*one* type
--]]
function annotations.make_annotation(ann, options)
  if options.type and (ann.type ~= options.type) then return '' end
  local tpl = TEMPLATES.get('annotation', options.style)
  local field_tpl = TEMPLATES.get('ann_fields', options.style)
  for element in tpl:gmatch('<<<(.-)>>>') do
    tpl = tpl:gsub(
      '<<<'..util.quote_hyphens(element)..'>>>',
      annotations.interpolate(ann, element, field_tpl[element]))
  end
  return tpl
end


--[[
  Parse a block of LaTeX key=value assignments.
  Assignments spanning multiple lines are concatenated to a single string,
  Line comments are currently not supported
  (i.e. ignored and will probably cause errors).
  NOTE: The "values" are returned as strings, so any "Scheme-y" interpretation
  has to be done afterwards.
--]]
function annotations.parse_annotation(input)
  local result = {}
  local from, to = input:find('(%g-)%s-=')
  local key = input:sub(from, to-1)
  input = input:sub(to+1)
  for value, next_key in input:gmatch('%s-(.-)%s-\n-%s-(%g-)%s-=')
  do
    result[key] = util.unbracify(value)
    key = next_key
  end
  result[key] = util.unbracify(input:match('.*=(.*)'))
  return result, result['score-id']
end


--[[
  Split the original input file into annotations and parse them.
  After this function the annotations are available in the
  ANNOTATIONS[score-id] tables.
--]]
function source.parse()
  for _, ann, _ in string.gmatch(source.raw, '(\\.-%[%s-)(%g.-)(%]%s-\n)') do
    annotations.add_annotation(ann)
  end
end




--[[
  Parse a key=val,key=val string into a table.
  TODO: comma-separated lists within a value are not supported yet.
--]]
function util.parse_keyvals(input)
  local result = {}
  -- determine first key
  local from, to = input:find('(%g-)%s-=')
  local key = input:sub(from, to-1)
  input = input:sub(to+1)
  -- find pairs of value/next key for the remainder of the input string
  for value, next_key in input:gmatch('%s-(.-),(%g-)=')
  do
    result[key] = util.unbracify(value)
    key = next_key
  end
  -- find the last value.
  result[key] = util.unbracify(input:match('.*=(.*)') or input)
  return result
end




-- Print (to TeX) the given string as a sequence of strings
function util.print_latex(content)
  local lines = content:explode('\n')
  for _, line in ipairs(lines) do
    tex.print(line)
  end
end


-- Take a string (for use as pattern) and quote any hyphens
function util.quote_hyphens(input)
  return input:gsub('%-', '%%-')
end


--[[
  Replaces fields in a template string with values from the tbl table.
  A field is wrapped in three angled brackets and must match a top-level entry
  in tpl.
  Fields that are *not* found in the tables are ignored (i.e. kept in their
  template state) and should be handled specifically afterwards.
]]
function util.replace(template, tbl)
  local value
  for element in template:gmatch('<<<(.-)>>>') do
    value = tbl[element]
    if value then
      template = template:gsub('<<<'..util.quote_hyphens(element)..'>>>', value)
    end
  end
  return template
end


-- Remove leading and trailing curly braces from a string
function util.unbracify(input)
  return input:match('^{?(.-)}?,?$')
end


--[[
  Load a critical report from a file, parse and store its annotations.
  The given 'basename' argument may directly point to a file, to a file
  basename.inp, or basename.annotations.inp
--]]
function lycritrprt.load_critical_report(basename)
  local report_file = ''
  if lfs.isfile(basename) then report_file = basename
  elseif lfs.isfile(basename..'.inp') then
    report_file = basename..'.inp'
  elseif lfs.isfile(basename..'.annotations.inp') then
    report_file = basename..'.annotations.inp'
  else
    warn("No critical report file found for "..basename..
  "\nSkip generating reports.")
  end

  local f = io.open(report_file, 'r')
  source.raw = f:read('*a')
  f:close()

  source.parse()

end


--[[
  Load a file with custom style definitions.
  Any style definitions in that file will overwrite the default ones.
  It is possible to define completely new styles or to adjust the 'default'
  which is defined in the package.
--]]
function lycritrprt.load_styles(file)
  -- Try loading the given file which has to return a compatible templates table
  local success, custom_tpls = pcall(require, file)
  if not success then
    warn(string.format([[
Failed to find custom stylesheet "%s" for critical reports.
Fall back to default styles.
    ]], file))
    return
  end

  -- Iterate over *our* defined templates
  for k, tpl in pairs(TEMPLATES) do
    if custom_tpls[k] then
      -- There is a custom template defined,
      -- iterate over styles defined in the custom template
      for style, def in pairs(custom_tpls[k]) do
        if (not TEMPLATES[k][style]) or (type(def) ~= 'table')
        then
          --[[
            If the existing template doesn't have a field for the
            style we're currently iterating over it means we add a
            "new" custom style, so we can simply insert it into the
            template table.
            If the style definition is not a table (i.e. a simple value)
            we can also simply overwrite the current value.
          --]]
          TEMPLATES[k][style] = def
        else
          --[[
            Iterate over the fields in the custom style definition,
            overwriting each field that is present in the custom definition,
            leaving the others at their default values.
          --]]
          for field, val in pairs(def) do
            TEMPLATES[k][style][field] = def[field]
          end
        end
      end
    end
  end
end


--[[
  Generate code for a critical report and 'print' it to the TeX document.
  NOTE: The options are currently simply a string referencing the score-id.
  Proper configuration remains to be implemented.
--]]
function lycritrprt.print_critical_report(options)
  options = util.parse_keyvals(options)
  if not options.style then options.style = 'default' end
  util.print_latex(
    util.replace(
      TEMPLATES.get('report', options.style), {
        ['entries'] = annotations.make(options)
      }))
end

return lycritrprt

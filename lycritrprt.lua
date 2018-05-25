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


function annotations.add_annotation(text)
  local ann, score = annotations.parse_annotation(text)
  if not SCORES[score] then
     ANNOTATIONS[score] = {}
     SCORES[score] = score
   end
  table.insert(ANNOTATIONS[score], ann)
end

--[[
  Parse a blcok of LaTeX key=value assignments.
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



function source.parse()
  for _, ann, _ in string.gmatch(source.raw, '(\\.-%[%s-)(%g.-)(%]%s-\n)') do
    annotations.add_annotation(ann)
  end
end

end









function util.unbracify(input)
  return input:match('^{?(.-)}?,?$')
end





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

function lycritrprt.print_critical_report(options)
  print()
  tex.print("I would now print a critical report with\\\\")
  tex.print(options.."\\\\")
end

return lycritrprt

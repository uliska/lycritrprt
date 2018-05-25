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

local lycritrprt = {}

function lycritrprt.load_critical_report(basename)
  print()
  print("Stub for loading the critical report from "..basename)
end

function lycritrprt.print_critical_report(options)
  print()
  tex.print("I would now print a critical report with\\\\")
  tex.print(options.."\\\\")
end

return lycritrprt

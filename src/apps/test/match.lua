module(...,package.seeall)

local ffi = require("ffi")
local C = ffi.C
local lib = require("core.lib")

local function dump (p)
   return lib.hexdump(ffi.string(packet.data(p), packet.length(p)))
end

Match = {}

function Match:new (arg)
   local conf = arg and config.parse_app_arg(arg) or {}
   return setmetatable({ fuzzy = conf.fuzzy,
                         modest = conf.modest,
                         seen = 0,
                         errs = { } },
                       { __index=Match })
end

function Match:push ()
   while not link.empty(self.input.rx) do
      local p = link.receive(self.input.rx)
      local cmp = link.front(self.input.comparator)
      if not cmp then
      elseif packet.length(cmp) ~= packet.length(p)
         or C.memcmp(packet.data(cmp), packet.data(p), packet.length(cmp)) ~= 0 then
         if not self.fuzzy then
            table.insert(self.errs, "Mismatch:\n"..dump(cmp).."\n"..dump(p))
         end
      else
         self.seen = self.seen + 1
         packet.free(link.receive(self.input.comparator))
      end
      packet.free(p)
   end
end

function Match:report ()
   for _, error in ipairs(self:errors()) do
      print(error)
   end
end

function Match:errors ()
   if not (self.modest and self.seen > 0) then
      while not link.empty(self.input.comparator) do
         local p = link.receive(self.input.comparator)
         table.insert(self.errs, "Not matched:\n"..dump(p))
         packet.free(p)
      end
   end
   return self.errs
end

function selftest()
   local basic_apps = require("apps.basic.basic_apps")
   local c = config.new()

   config.app(c, "sink", Match, {modest=true})
   config.app(c, "comparator", basic_apps.Source, 8)
   config.link(c, "comparator.output -> sink.comparator")
   engine.configure(c)
   engine.app_table.sink.input.rx = link.new("null")
   engine.app_table.sink.seen = 1
   engine.main({duration=0.0001})
   assert(#engine.app_table.sink:errors() == 0)

   engine.configure(config.new())
   config.app(c, "sink", Match)
   config.app(c, "src", basic_apps.Source, 8)
   config.link(c, "src.output -> sink.rx")
   engine.configure(c)
   engine.main({duration=0.0001})
   assert(#engine.app_table.sink:errors() == 0)

   engine.configure(config.new())
   config.app(c, "comparator", basic_apps.Source, 12)
   engine.configure(c)
   engine.main({duration=0.0001})
   assert(#engine.app_table.sink:errors() > 0)

   engine.configure(config.new())
   config.app(c, "sink", Match, {fuzzy=true})
   config.app(c, "comparator", basic_apps.Source, 8)
   config.app(c, "garbage", basic_apps.Source, 12)
   config.app(c, "join", basic_apps.Join)
   config.link(c, "src.output -> join.src")
   config.link(c, "garbage.output -> join.garbage")
   config.link(c, "join.out -> sink.rx")
   engine.configure(c)
   engine.main({duration=0.0001})
   assert(#engine.app_table.sink:errors() == 0)
end

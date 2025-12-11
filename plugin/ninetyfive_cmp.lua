local ok, cmp = pcall(require, "cmp")
if not ok then
    return
end

local Source = require("ninetyfive.cmp")

cmp.register_source("ninetyfive", Source.new())

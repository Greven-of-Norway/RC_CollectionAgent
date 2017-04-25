--[[
        Shutdown.lua
        
        Generic shutdown module.
        
        Just sets shutdown flag, which often is enough.
        
        May be copied, but will not be customized by plugin generator.
--]]

if rawset then
    rawset( _G, 'shutdown', true ) -- I've never had problem using _G.shutdown = true, but it seems like cheap insurance to just set raw:
        -- dont want a problem reloading due to some minor strictness snafu...
else
    _G.shutdown = true -- gotta try this if no rawset...
end
-- the end.
--[[
        ExtendedObjectFactory.lua
        
        Creates special objects used in the guts of the framework.
        
        This is what you edit to change the classes of framework objects
        that you have extended.
--]]

local ExtendedObjectFactory, dbg, dbgf = ObjectFactory:newClass{ className = 'ExtendedObjectFactory', register = false }



--- Constructor for extending class.
--
--  @usage  I doubt this will be necessary, since there is generally
--          only one special object factory per plugin, mostly present
--          for the sake of completeness...
--
function ExtendedObjectFactory:newClass( t )
    return ObjectFactory.newClass( self, t )
end



--- Constructor for new instance.
--
function ExtendedObjectFactory:new( t )
    local o = ObjectFactory.new( self, t )
    return o
end



--- Framework module loader.
--
--  @usage      Generally better to handle in other ways,
--              but this method can help when in a jam...
--
--  @return     loaded module return value, or if code is programmed for module to be optional, can return nil to exclude module.
--
function ExtendedObjectFactory:frameworkModule( spec )
    --if spec == 'System/Preferences' then
    --    return nil - at the moment, this is the only way to kill the preference preset manager.
    --else
        return ObjectFactory.frameworkModule( self, spec )
    --end
end



--- Creates instance object of specified class.
--
--  @param      class       class object OR string specifying class.
--  @param      ...         initial table params forwarded to 'new' constructor.
--
function ExtendedObjectFactory:newObject( class, ... )
    if type( class ) == 'table' then
        --if class == Manager then
        --    return ExtendedManager:new( ... )
        --end
    elseif type( class ) == 'string' then
        if class == 'Manager' then
            return ExtendedManager:new( ... )
        elseif class == 'ExportDialog' then
            return ExtendedExport:newDialog( ... )
        elseif class == 'Export' then
            return ExtendedExport:newExport( ... )
        end
    end
    return ObjectFactory.newObject( self, class, ... )
end



return ExtendedObjectFactory 
-- the end.
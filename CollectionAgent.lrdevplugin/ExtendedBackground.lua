--[[
        ExtendedBackground.lua
--]]

local ExtendedBackground, dbg, dbgf = Background:newClass{ className = 'ExtendedBackground' }



--- Constructor for extending class.
--
--  @usage      Although theoretically possible to have more than one background task,
--              <br>its never been tested, and its recommended to just use different intervals
--              <br>for different background activities if need be.
--
function ExtendedBackground:newClass( t )
    return Background.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage      Although theoretically possible to have more than one background task,
--              <br>its never been tested, and its recommended to just use different intervals
--              <br>for different background activities if need be.
--
function ExtendedBackground:new( t )
    local interval
    local minInitTime
    local idleThreshold
    if app:getUserName() == '_RobCole_' and app:isAdvDbgEna() then
        interval = 1
        idleThreshold = 1
        minInitTime = 3
    else
        interval = 1
        idleThreshold = 1
        -- default min-init-time is 10-15 seconds or so.
    end    
    local o = Background.new( self, { interval=interval, minInitTime=minInitTime, idleThreshold=idleThreshold } )
    return o
end



--- Initialize background task.
--
--  @param      call object - usually not needed, but its got the name, and context... just in case.
--
function ExtendedBackground:init( call )
    self.initStatus = true
    -- this pref name is not assured nor sacred - modify at will.
    if not app:getPref( 'background' ) then -- check preference that determines if background task should start.
        self:quit() -- indicate to base class that background processing should not continue past init.
    end
    self.syncCollLookup = {}
    local nSync = 0
    local getter = app:getPref( 'getDumbCollName' ) or error( "?" )
    local smartCollItems = cat:getSmartCollectionPopupItems( catalog )
    local s, m = cat:update( 300, "Assure dumb collections", function()
        for i, item in ipairs( smartCollItems ) do
            if tonumber( item.value ) then -- it's a local collection ID.
                local coll, name, path = cat:getSmartCollection( item.value ) -- init upon first use if not explictly pre-initialized.
                if coll then
                    local searchDescr = coll:getSearchDescription() -- hybrid table: combine + rules..
                    for i, rule in ipairs( searchDescr ) do
                        if rule.value == "__CollectionAgent_AutoUpdateDumbColl__" then -- special "null" rule that serves as a tag.
                            local assured, darn = self:assureSync( coll, true, nil, getter )
                            if assured then
                                nSync = nSync + 1
                            else
                                error( darn )
                            end
                            break
                        end
                    end
                end
            end
        end
    end )
    if s then
        app:log( "^1 pair(s) to sync", nSync )
    else
        self.initStatus = false
        app:logError( "Unable to initialize due to error: " .. str:to( m ) )
        app:show( { error="Unable to initialize - check log file for details." } )
    end        
end



function ExtendedBackground:assureSync( smartColl, enable, dumbColl, getter )
    if self.syncCollLookup[smartColl] then
        if enable then
            return true
        else
            self.syncCollLookup[smartColl] = nil
            return true
        end
    else -- not listed
        if enable then -- should be
            -- fall
        else
            return true
        end
    end
    -- list
    getter = getter or app:getPref( 'getDumbCollName' ) or error( "?" )
    local dumbCollName = getter{ smartCollName = smartColl:getName() }
    if str:is( dumbCollName ) then
        -- Debug.pause( smartColl:getParent(), dumbCollName ) - parent is correct
        dumbColl = dumbColl or catalog:createCollection( dumbCollName, smartColl:getParent(), true ) -- ###1 parent
        if dumbColl then
            self.syncCollLookup[smartColl] = dumbColl
            return true
        else
            Debug.pause( dumbCollName, smartColl:getParent():getName(), catalog.hasWriteAccess )
            return false, str:fmtx( "cant create/assure dumb coll named '^1' in '^2'", dumbCollName, smartColl:getParent() or "root of catalog" )
        end
    elseif dumbCollName then -- empty string.
        return true -- reminder: empty string means "dont sync", whereas nil is considered an error. Although this is required during init, it may not be perfect handling post-init (?) - oh well: user can always reload..
    else -- nil
        return false, "no dumb coll name"
    end
end



--- Background processing method.
--
--  @param      call object - usually not needed, but its got the name, and context... just in case.
--
function ExtendedBackground:process( call )

    for smartColl, dumbColl in pairs( self.syncCollLookup ) do
        local searchDescr = smartColl:getSearchDescription()
        local photos = catalog:findPhotos{ searchDesc=searchDescr } -- note: no 'r'.
        local sts, nPlus, nMinus = LrTasks.pcall( cat.setCollectionPhotos, cat, dumbColl, photos, -5 ) -- 5 seconds, but don't trip if no can do..
        if sts then
            -- nPlus & nMinus are always number (never nil).
            if nPlus > 0 or nMinus > 0 then
                app:log( "Dumb collection updated - ^1 added, ^2 removed.", nPlus, nMinus )
            else -- collection not changed.
                --Debug.pause( "status quo.." )
            end
            self:clearError( smartColl.localIdentifier )
        else
            app:logV( "*** Unable to set collection photos to honor syncing ^1 - ^2", smartColl:getName(), nPlus )
            self:displayError( nPlus, smartColl.localIdentifier, false, true ) -- false => not immediate, true => prompt to view log file when scope canceled.
            app:sleep( 1 ) -- in case error persists.
        end
    end
end
    


return ExtendedBackground

--[[
        CollectionAgent.lua
--]]


local CollectionAgent, dbg, dbgf = Object:newClass{ className = "CollectionAgent", register = true }



--- Constructor for extending class.
--
function CollectionAgent:newClass( t )
    return Object.newClass( self, t )
end


--- Constructor for new instance.
--
function CollectionAgent:new( t )
    local o = Object.new( self, t )
    return o
end



-- Common initialization.
function CollectionAgent:_init( call )
    self.call = call
    self.smartDir = LrPathUtils.child( cat:getCatDir(), "Smart Collection Definitions" )
    self.pubSmartDir = LrPathUtils.child( cat:getCatDir(), "Publish Collection Definitions" )
    if fso:existsAsDir( self.smartDir ) then
        app:log( "Smart collections root dir: ^1", self.smartDir )
    else
        app:logWarning( "Smart collections root dir '^1' does not exist. It must exist and be populated with smart collection definitions in order to duplicate smart collections (exported in same hierarchical structure as collection sets, like SQLiteroom will do automatically).", self.smartDir )
    end
    if fso:existsAsDir( self.pubSmartDir ) then
        app:log( "Publish smart collections root dir: ^1", self.pubSmartDir )
    else
        app:log( "*** Publish smart collections root dir '^1' does not exist. It must exist and be populated with smart collection definitions in order to duplicate smart collections in publish services (exported in same hierarchical structure as collection sets, like SQLiteroom will do automatically).", self.pubSmartDir )
    end
end



function CollectionAgent:_createScope( title, subtitle )
    self.scope = LrProgressScope {
        title=title,
        caption=subtitle,
        functionContext = self.call.context,
    }
end
    


function CollectionAgent:_killScope()
    if self.scope then
        self.scope:done()
    end
end



-- at the moment, it gets path to parent directory of smart collection, not smart collection file itself.
function CollectionAgent:_getSmartPath( coll, isPub )
    local collSet = coll:getParent()
    if collSet == nil then
        if coll.getService then
            -- coll set is pub serv
            return LrPathUtils.child( self.pubSmartDir, coll:getService():getName() )
        else
            -- coll set is catalog
            return self.smartDir
        end
    end
    local smartDir
    if isPub then
        smartDir = self.pubSmartDir
    else
        smartDir = self.smartDir
    end
    assert( collSet.getName ~= nil, "no collset getname" )
    Debug.logn( "Getting smart path for", collSet:getName() )
    local smartPath = smartDir
    local parent = collSet -- :getParent()
    local parents = {}
    while parent do
        parents[#parents + 1] = parent
        if parent.getParent then
            parent = parent:getParent()
        else
            break
        end
    end
    for i = #parents, 1, -1 do
        smartPath = LrPathUtils.child( smartPath, parents[i]:getName() )
    end
    return smartPath
end



--  Duplicate or synchronize a collection, dumb or smart.
--
--  @param      source      ( lr-collection or lr-publish-collection, required ) The source collection.
--  @param      dest        ( same type as source, or nil ) The destination collection to be created and/or synchronized.
--  @param      pubSrv      ( lr-publish-service, optional ) of passed, then destination will be created in a publish service.

function CollectionAgent:_dupOrSyncCollection( source, dest, pubSrv, newName )
    local smartPath = self:_getSmartPath( source, pubSrv )
    local sourceName
    local targetName
    local smart
    if source.getName then
        sourceName = source:getName()
        smart = source:isSmartCollection()
    else
        app:callingError( "no source name" )
    end
    if newName then
        targetName = newName
    else
        targetName = sourceName
    end    
    local longTargetName
    if dest == nil then -- dont think this happens any more.
        longTargetName = str:fmt( "'^1' in 'Root'", targetName )
    elseif dest.getName then
        longTargetName = str:fmt( "'^1' in '^2'", targetName, dest:getName() )
    else -- but this does.
        longTargetName = str:fmt( "'^1' in 'Catalog Root'", targetName )
        dest = nil
    end
    local undoTidbit
    local sync = self.syncNotDup
    if sync then
        undoTidbit = " or update" -- no way to tell which happened when can-return-prior is true (sync).
    else
        undoTidbit = ""
    end
    if smart then
        local rules
        if app:lrVersion() >= 5 then
            rules = source:getSearchDescription()
        else
            local smartDef = LrPathUtils.child( smartPath, str:fmt( "^1.lrsmcol", sourceName ) )
            if fso:existsAsFile( smartDef ) then
                local def = rawset( _G, 's', nil )
                pcall( dofile, smartDef )
                def = rawget( _G, 's' )
                if def then
                    rules = def.value
                    if rules then
                        app:logVerbose( "Got rules from exported collection." )
                    else
                        app:error( "Unable to get rules from collection export." )
                    end
                else
                    app:error( "Unable to load smart def at ^1", smartDef )
                end
            end
            if rules then
                app:logVerbose( "Got smart collection rules for ^1 at ^2", sourceName, smartDef )
            else
                app:error( "No smart collection rules for ^1 at ^2 - to remedy, export them there from source collection, or if you are using SQLiteroom, just restart Lightroom, then retry.", sourceName, smartDef )
            end
        end
        local s, m = cat:update( 20, str:fmt( "Creation^1 of smart collection named ^2", undoTidbit, longTargetName ), function( context, phase )
            local searchDesc
            if rules then
                searchDesc = rules
            else
                searchDesc = { -- this is essentially the default rule for a new smart collection.
                    {
    	                criteria = "rating",
    	                operation = ">=",
    	                value = 0,
                    },
                    combine = "intersect",
                }
            end
            local c
            if not pubSrv then
                c = catalog:createSmartCollection( targetName, searchDesc, dest, sync )
            else
                c = pubSrv:createPublishedSmartCollection( targetName, searchDesc, dest, sync )
            end
            if not c then
                if sync then
                    app:error( "Unable to create or update smart collection ^1", targetName )
                else
                    app:logWarning( "Unable to create smart collection ^1 - probably because it was already there.", targetName )
                end
            else
                if sync then
                    if rules then -- new search-def not applied if collection already existed.
                    
                        Debug.lognpp( rules )
                    
                        c:setSearchDescription( rules ) -- update explicitly 
                        
                        app:log( "Created or updated smart collection ^1", longTargetName )
                    -- else warning already logged
                    end
                else
                    if rules then
                        app:log( "Created smart collection ^1 - with proper rules.", longTargetName )
                    else
                        app:log( "*** Created smart collection ^1 *with improper rules* - remember to resync after exporting smart collection settings.", longTargetName )
                    end
                end
            end
        end )
        if not s then
            error( m )
        end
    else
        local c
        local s, m = cat:update( 20, str:fmt( "^1 of collection named ^2", undoTidbit, longTargetName ), function( context, phase )
            if phase == 1 then
                if not pubSrv then
                    c = catalog:createCollection( targetName, dest, sync )
                else
                    c = pubSrv:createPublishedCollection( targetName, dest, sync )
                end
                return false -- not done yet.
            else
                -- return nil after processing => done.
                -- Note: The API doc states it is not OK to add photos until the with-do returns.
                if c then
                    if sync then
                        app:log( "Created or updated collection ^1", longTargetName )
                        if self.photosToo then
                            local srcLookup = {}
                            local targLookup = {}
                            local remove = {}
                            local add = {}
                            for i, photo in ipairs( source:getPhotos() ) do
                                srcLookup[photo] = true
                            end
                            for i, photo in ipairs( c:getPhotos() ) do
                                if srcLookup[photo] == true then
                                    targLookup[photo] = true
                                else
                                    remove[#remove + 1] = photo
                                end
                            end
                            for i, photo in ipairs( source:getPhotos() ) do
                                if not targLookup[photo] then
                                    add[#add + 1] = photo
                                else
                                    -- dont
                                end
                            end
                            if #add > 0 then
                                c:addPhotos( add )
                            end
                            if #remove > 0 then
                                c:removePhotos( remove )
                            end
                            app:log( "Synchronized photos in collection too." )
                        else
                            app:log( "Not syncing photos in regular collections." )
                        end
                    else
                        app:log( "Created collection ^1", longTargetName )
                        if self.photosToo then
                            c:removeAllPhotos()
                            c:addPhotos( source:getPhotos() )
                            app:log( "Copied photos to collection too." )
                        else
                            app:log( "Not copying photos in regular collections." )
                        end
                    end
                else
                    app:error( "Unable to create collection ^1", longTargetName )
                end
            end
        end )
        if not s then
            error( m )
        end
    end
end



-- duplicate or synchronize collection sets. set self-sync-not-dup to true if its OK for it to pre-exist.
-- nothing returned => throws error if trouble.
function CollectionAgent:_dupOrSyncChildren( source, dest, pubSrv )

    local undoTidbit
    local sync = self.syncNotDup
    if sync then
        undoTidbit = " or update" -- no way to tell which happened when can-return-prior is true (sync).
    else
        undoTidbit = ""
    end
    
    for i, v in ipairs( source:getChildCollections() ) do
        self:_dupOrSyncCollection( v, dest, pubSrv )
    end
    for i, v in ipairs( source:getChildCollectionSets() ) do
        local collSetName = v:getName()
        local longTargetName
        local targetName
        if dest == nil then
            targetName = 'root'
        elseif dest.getName then
            targetName = dest:getName()
        else
            targetName = 'Catalog Root'
            dest = nil
        end
        longTargetName = str:fmt( "'^1' in '^2'", collSetName, targetName )
        local collSet
        local s, m = cat:update( 20, str:fmt( "Creation^1 of collection set ^2", undoTidbit, longTargetName ), function( context, phase )
            if not pubSrv then
                collSet = catalog:createCollectionSet( collSetName, dest, sync )
            else
                collSet = pubSrv:createPublishedCollectionSet( collSetName, dest, sync )
            end
            if not collSet then
                app:error( "Unable to create collection set ^1", longTargetName )
            else
                if sync then
                    app:log( "Created or updated collection set ^1", longTargetName )
                else
                    app:log( "Created collection set ^1", longTargetName )
                end
            end
        end )
        if s then
            self:_dupOrSyncChildren( v, collSet, pubSrv )
        else
            error( m )
        end
    end

end



function CollectionAgent:duplicate()
    app:call( Service:new{ name="Duplicate Collection Set (or Smart Collection)", async=true, guard=App.guardVocal, main=function( call )
    
        self:_init( call )
        
        local sourceSet
        local sourceColl
        local pubSrv
        local sources = {}
        
        for i, source in ipairs( catalog:getActiveSources() ) do
            local sourceType = cat:getSourceType( source )
            if sourceType == 'LrCollectionSet' then
                sources[#sources + 1] = source
                sourceSet = source
            elseif sourceType == 'LrPublishedCollectionSet' then
                sources[#sources + 1] = source
                sourceSet = source
                pubSrv = source:getService()
            elseif sourceType == 'LrCollection' then
                if source:isSmartCollection() then
                    sources[#sources + 1] = source
                    sourceColl = source
                end
            elseif sourceType == 'LrPublishedCollection' then
                if source:isSmartCollection() then
                    sources[#sources + 1] = source
                    sourceColl = source
                    pubSrv = source:getService()
                end
            else
                app:logWarning( "Ignoring selected source: ^1 - ^2", cat:getSourceName( source ), sourceType )
            end
        end
        
        if #sources == 0 then
            call:cancel()
            app:show{ warning="Select collection set or smart collection first." }
            return
        elseif #sources > 1 then
            call:cancel()
            app:show{ warning="Select just one collection set or smart collection." }
            return
        end
        
        local uiTidbit
        local source
        if sourceSet then
            source = sourceSet
            uiTidbit = "collection set"
        elseif sourceColl then
            source = sourceColl
            uiTidbit = "smart collection"
        else
            error( "oops" )
        end
        assert( source.getName ~= nil, "no name" )
        local sourceName = source:getName()
        local sourceParent = source:getParent()
        local sourceParentName
        if sourceParent == nil then
            if pubSrv then
                sourceParent = pubSrv
                sourceParentName = pubSrv:getName()
            else
                sourceParent = catalog
                sourceParentName = "Catalog Root"
            end
        end
        
        local props = LrBinding.makePropertyTable( call.context )
        props.regex = false
        props.search = sourceName
        props.replace = sourceName .. " " .. math.random( 1000000, 9999999 )
        props.photosToo = true
        local vi = {}
        vi[#vi + 1] =
            vf:row { 
                vf:static_text {
                    title = str:fmt( "Search for this in ^1 name:", uiTidbit ),
                    width = share 'label_width',
                },
                vf:edit_field {
                    bind_to_object = props,
                    value = bind 'search',
                    width_in_chars = 30,
                },
            }
        vi[#vi + 1] = vf:spacer{ height = 5 }
        vi[#vi + 1] =
            vf:row { 
                vf:static_text {
                    title = "And replace it with this:",
                    width = share 'label_width',
                },
                vf:edit_field {
                    bind_to_object = props,
                    value = bind 'replace',
                    width_in_chars = 30,
                },
            }
        vi[#vi + 1] = vf:spacer{ height = 5 }
        vi[#vi + 1] =
            vf:row { 
                vf:spacer {
                    width = share 'label_width',
                },
                vf:checkbox {
                    bind_to_object = props,
                    title = "Lua regular expression",
                    value = bind 'regex',
                    tooltip = "Leave this unchecked if you don't know what its for.",
                },
                vf:spacer {
                    width = 1,
                },
                vf:checkbox {
                    bind_to_object = props,
                    title = "Photos too",
                    value = bind 'photosToo',
                    tooltip = "Check to have photos transferred to duplicated collections, leave unchecked for skeletal (empty) collections in duplicated set.",
                },
            }
            
        local targetParent -- "collection set".
        local targetParentName
        local targetName
        repeat
            local answer = app:show{ confirm="Duplicate '^1' ^2? (and where in collections hierarchy?)",
                subs = { sourceName, uiTidbit },
                buttons = { dia:btn( "Same Level", 'ok' ), dia:btn( "Top Level", 'other') },
                viewItems = vi,
            }
            self.photosToo = props.photosToo
            local exit = false
            repeat
                if answer ~= 'cancel' then
                    if not str:is( props.search ) then
                        app:show{ warning="Enter search term" }
                        break
                    end
                    if not str:is( props.replace ) then
                        app:show{ warning="Enter replacement" }
                        break
                    end
                    if props.search == props.replace then
                        app:show{ warning="Replace with something other than search term" }
                        break
                    end
                    if props.regex then
                        targetName = sourceName:gsub( props.search, props.replace )
                    else
                        targetName = str:searchAndReplace( sourceName, props.search, props.replace )
                    end
                    if targetName == sourceName then
                        app:show{ warning="Search string not found." }
                        break
                    end
                    local a = app:show{ confirm="New name will be '^1' - proceed?",
                        subs = targetName,
                        buttons = { dia:btn( "Yes", 'ok' ), dia:btn( "No", 'cancel' ) },
                    }
                    if a == 'cancel' then
                        break
                    end
                else
                    call:cancel()
                    return
                end
                -- answer ok or other and inputs check out.
                if answer == 'ok' then
                    targetParent = sourceParent -- target parent is source parent
                    -- could probably use cat:getSourceName( sourceParent )
                    if sourceParent.getName then
                        --targetParentName = sourceParent.getName() -- bug discovered 14/Dec/2013 17:25 (how did this persist for so long?)
                        targetParentName = sourceParent:getName() -- bug fixed 14/Dec/2013 17:25
                    else
                        targetParentName = "Root" -- not sure if pub-srv or cat, but not critical so..
                    end
                    exit = true
                elseif answer == 'other' then
                    if pubSrv then
                        targetParent = pubSrv
                        targetParentName = pubSrv:getName()
                    else
                        targetParent = catalog
                        targetParentName = 'Catalog Root'
                    end
                    exit = true
                else
                    app:error( "bad answer" )
                end
            until true
            if exit then
                break
            end
        until false

        self:_createScope( str:fmt( "Duplicating ^1", uiTidbit ), "Please wait..." ) -- and assign to self.
        
        if sourceSet then
            local set
            local s, m = cat:update( 20, str:fmt( "Duplicating ^1", sourceName ), function( context, phase )
                if pubSrv then
                    set = pubSrv:createPublishedCollectionSet( targetName, targetParent, false )
                else
                    if targetParent == catalog then
                        set = catalog:createCollectionSet( targetName, nil, false )
                    else
                        set = catalog:createCollectionSet( targetName, targetParent, false )
                    end
                end
                if set then
                    app:log( "Created collection set '^1' in '^2'", targetName, targetParentName )
                else
                    app:error( "Unable to create collection set - check if a collection set named ^1 already exists - that would explain it ;-}", name )
                end
            end )
            if s then
                self.syncNotDup = false
                s, m = app:call( Call:new{ name="Create duplicate collection set tree", main=function( call )
                    self:_dupOrSyncChildren( sourceSet, set, pubSrv )
                end } )
            end
            if not s then
                if set then
                    local news, errm = cat:update( 20, str:fmt( "Deletion of collection set: ^1", set:getName() ), function( context, phase )
                        set:delete()
                    end )
                    if news then
                        app:logVerbose( "Cleaned up created set." )
                    else
                        app:error( errm )
                    end
                end
                error( m )
            end
        else -- smart-coll, for sure.
            self.syncNotDup = false
            local s, m = app:call( Call:new{ name="Create duplicate smart collection", main=function( call )
                self.syncNotDup = false
                self:_dupOrSyncCollection( sourceColl, targetParent, pubSrv, targetName )
            end } )
            if s then
                app:log( "Smart collection duplicated." )
            else
                error( m )
            end
        end
        
    end, finale=function( call, status, message )

        app:log( "\n\n" ) 
        if status then
            if not call:isCanceled() and not call:isAborted() then -- cancel, abort, or throw error if trouble duplicating collection set.
                app:log( "Smart collection or collection set duplicated." )
            else
                -- cancel or abort already logged            
            end
        else
            -- error already logged.
        end
        app:log( "\n\n" ) 
        
        self:_killScope() -- so its dead when the finale dbox comes on, if it does.
        --Debug.showLogFile()
    
    end } )
    
end



function CollectionAgent:setSyncSource()
    app:call( Call:new{ name="Set Sync Source", async=true, guard=App.guardVocal, main=function( call )
    
        self:_init( call )

        self.syncSource = nil
        local sources = {}        

        --Debug.clearLogFile()        
        for i, source in ipairs( catalog:getActiveSources() ) do
            local sourceType = cat:getSourceType( source )
            --Debug.lognpp( sourceType )
            if sourceType == 'LrCollectionSet' or sourceType == 'LrPublishedCollectionSet' then
                sources[#sources + 1] = source
            elseif sourceType == 'LrCollection' or sourceType == 'LrPublishedCollection' then
                sources[#sources + 1] = source -- collections are now directly settable as sync sources, like collectio sets.
            else
                app:logWarning( "Source ignored: ^1", cat:getSourceName( source ) )
            end
        end
        --Debug.showLogFile()        
        
        if #sources == 0 then
            call:cancel()
            app:show{ warning="Select smart collection or set first." }
            return
        elseif #sources > 1 then
            call:cancel()
            app:show{ warning="Select just one collection set." }
            return
        end
        
        self:_createScope( "Setting sync source", "..." ) -- and assign to self.
        self.syncSource = sources[1] -- there is not much to do really, but having a scope flash means one can dismiss the subsequent dialog box, but still see some feedback.
        self:_killScope() -- so its dead when the following dbox comes on, if it does.
        
        local sourceName
        if sources[1] == catalog then
            local ok = dia:isOk( "Are you sure you want to set the catalog root as sync source?" )
            if ok then
                sourceName = "Catalog Root"
            else
                self.syncSource = nil
                call:cancel()
                return                
            end
        else
            sourceName = sources[1]:getName()
        end

        app:show{ info="Sync source has been set to '^1'. Next step is to select sync target(s), then invoke 'Sync Selected Collections or Sets'.",
            subs = sourceName,
            actionPrefKey = "Collection sync source is set"
        }
        
    end } )
    
end



function CollectionAgent:setCopySources()
    app:call( Call:new{ name="Set Copy Source Collections and/or Sets", async=true, guard=App.guardVocal, main=function( call )
    
        self:_init( call )

        self.copySources = nil -- invoking this kills any prior sources, unless successful.
        local sources = {}        
        local colls = 0
        local collSets = 0
        local reglar
        local pub
        
        if sources then
            for i, source in ipairs( catalog:getActiveSources() ) do
                local sourceType = cat:getSourceType( source )
                if sourceType == 'LrCollectionSet' or sourceType == 'LrCollection' then
                    if pub then
                        app:show{ warning="Sources must be from publish collections or regular, not both." }
                        call:cancel()
                        return
                    else
                        sources[#sources + 1] = source
                        reglar = true
                        if sourceType == 'LrCollection' then
                            colls = colls + 1
                        else
                            collSets = collSets + 1
                        end
                    end
                elseif sourceType == 'LrPublishedCollectionSet' or sourceType == 'LrPublishedCollection' then
                    if reglar then
                        app:show{ warning="Sources must be from regular or publish collections, not both." }
                        call:cancel()
                        return
                    else
                        sources[#sources + 1] = source
                        pub = true
                        if sourceType == 'LrPublishedCollection' then
                            colls = colls + 1
                        else
                            collSets = collSets + 1
                        end
                    end
                else
                    app:logWarning( "Source ignored: ^1", cat:getSourceName( source ) )
                end
            end
        end
        
        if #sources == 0 then
            call:cancel()
            app:show{ warning="Select source collections and/or sets first." }
            return
        end
        
        -- Note: legal source count is defined by target operation.
        
        self:_createScope( "Setting copy sources", "..." ) -- and assign to self.
        self.copySources = sources -- there is not much to do really, but having a scope flash means one can dismiss the subsequent dialog box, but still see some feedback.
        self:_killScope() -- so its dead when the following dbox comes on, if it does.
        
        local publish = ""
        if pub then
            publish = "publish "
        end
        
        app:show{ info="^1 and ^2 ready to copy.",
            subs = { str:plural( collSets, str:fmt( "^1collection set", publish ), true ), str:plural( colls, str:fmt( "^1collection", publish ), true ) }, 
            actionPrefKey = "Copy sources are set"
        }
        
    end } )
    
end



function CollectionAgent:sync()
    app:call( Service:new{ name="Sync Collection Set or Smart Collection", async=true, guard=App.guardVocal, main=function( call )
    
        self:_init( call )
        
        local sourceSet
        local sourceColl
        local sourceSmartColl
        local lrCollSets = {} -- targets.
        local lrSmartColls = {}
        local lrColls = {}
        local syncType
        local activeSources = catalog:getActiveSources()
        
        if self.syncSource == nil then
            local ok = dia:isOk( "Redefine self from definitions on disk? Otherwise, use 'Set Sync Source (Collection Set)' first." )
            if ok then
                if #activeSources == 0 or #activeSources > 1 then
                    app:show{ warning="Select only one source." }
                    call:cancel()
                    return
                end
                self.syncSource = activeSources[1]
                if str:isEndingWith( cat:getSourceType( self.syncSource ), "Collection" ) then
                    if self.syncSource:isSmartCollection() then
                        -- fine
                    else
                        app:show{ warning="Set sync source first (can't sync a collection to itself)." }
                        call:cancel()
                        return
                    end
                else
                    -- anything?
                end
            else
                --app:show{ warning="Use 'Set Sync Source (Collection Set)' first." }
                call:cancel()
                return
            end
        end
        
        if self.syncSource.type then
            local typ = cat:getSourceType( self.syncSource )
            if str:isEndingWith( typ, "Collection" ) then
                local coll = self.syncSource
                if coll:isSmartCollection() then
                    sourceSmartColl = coll
                else
                    sourceColl = coll
                end
            else
                if typ:find( "CollectionSet" ) then
                    sourceSet = self.syncSource
                else
                    app:error( "Bad source type: ^1", typ )
                end
            end
        else
            assert( self.syncSource == catalog, "what sync source?" )
            sourceSet = self.syncSource -- its the catalog.
        end
        
        for i, target in ipairs( activeSources ) do
            local targetType = cat:getSourceType( target )
            local targetName = cat:getSourceName( target )
            if sourceSet then
                if targetType == 'LrCollectionSet' then
                    lrCollSets[#lrCollSets + 1] = target
                elseif targetType == 'LrPublishedCollectionSet' then
                    local p = target:getParent()
                    if p then
                        lrCollSets[#lrCollSets + 1] = p
                    else
                        lrCollSets[#lrCollSets + 1] = target:getService()
                    end
                else
                    app:logWarning( "Target ignored: ^1", targetName )
                end
            elseif sourceSmartColl then
                if targetType == 'LrCollection' or targetType == 'LrPublishedCollection' then
                    if target:isSmartCollection() then
                        lrSmartColls[#lrSmartColls + 1] = target
                    else
                        app:logWarning( "target not smart collection, like source." )
                    end
                else
                    app:logWarning( "Target ignored: ^1", targetName )
                end
            elseif sourceColl then
                if targetType == 'LrCollection' or targetType == 'LrPublishedCollection' then
                    if target:isSmartCollection() then
                        app:logWarning( "target not smart collection, like source." )
                    else
                        lrColls[#lrColls + 1] = target
                    end
                else
                    app:logWarning( "Target ignored: ^1", targetName )
                end
            else
                app:error( "No source" )
            end
        end

        -- Prompt user
        local answer
        if sourceSet then        
            if #lrCollSets == 0 then
                call:cancel()
                app:show{ warning="Select collection set target(s) first." }
                return
            end
            answer = app:show{ confirm="Synchronize ^1 with ^2 as source?",
                subs = { str:plural( #lrCollSets, "collection set", true ), sourceSet:getName() },
                buttons = { dia:btn( "Yes - Photos Too", 'ok' ), dia:btn( "Yes - Not Photos", 'other' ) },
                actionPrefKey = 'Sync collection sets prompt',
            }
            if answer == 'ok' then
                self.photosToo = true
            else
                self.photosToo = false
            end
        elseif sourceSmartColl then
            if #lrSmartColls == 0 then
                call:cancel()
                app:show{ warning="Select smart collection target(s) first." }
                return
            end
            answer = app:show{ confirm="Synchronize ^1 with ^2 as source?",
                subs = { str:plural( #lrSmartColls, "smart collection", true ), sourceSmartColl:getName() },
                buttons = { dia:btn( "OK", 'ok' ) },
                actionPrefKey = 'Sync smart collections prompt',
            }
            self.photosToo = nil -- Not Applicable.
        elseif sourceColl then
            if #lrColls == 0 then
                call:cancel()
                app:show{ warning="Select collection target(s) first." }
                return
            end
            answer = app:show{ confirm="Synchronize ^1 with ^2 as source?",
                subs = { str:plural( #lrColls, "collection", true ), sourceColl:getName() },
                buttons = { dia:btn( "Yes - Photos Too", 'ok' ), dia:btn( "Yes - No Photos", 'other' ) },
                actionPrefKey = 'Sync collections prompt',
            }
            if answer == 'ok' then
                self.photosToo = true
            else
                self.photosToo = false
            end
        else
            error( "Nothing set" )
        end
        
        if answer == 'cancel' then
            call:cancel()
            return
        end      

        local title
        if sourceSet then
            title = "Synchronizing collection sets"
        elseif sourceSmartColl then
            title = "Synchronizing smart collections"
        elseif sourceColl then
            title = "Synchronizing collections"
        else
            error( "no valid source" )
        end
        
        self:_createScope( title, "Please wait..." ) -- and assign to self.
        
        self.syncNotDup = true
        local s, m
        if sourceSet then
            s, m = app:call( Call:new{ name=title, main=function( call )
                for i, v in ipairs( lrCollSets ) do
                    local pubSrv
                    if v:type() == 'LrPublishService' then
                        pubSrv = v
                    elseif v:type():find( "LrPublished" ) then
                        pubSrv = v:getService()
                    end
                    --Debug.pause( pubSrv )
                    self:_dupOrSyncChildren( sourceSet, v, pubSrv )
                end
            end } )
        elseif sourceSmartColl then
            s, m = app:call( Call:new{ name=title, main=function( call )
                for i, v in ipairs( lrSmartColls ) do
                    local pubSrv
                    if v:type() == 'LrPublishedCollection' then
                        pubSrv = v:getService()
                    elseif v:type():find( "LrCollection" ) then
                        -- pubSrv = nil
                    end
                    --Debug.pause( pubSrv )
                    self:_dupOrSyncCollection( sourceSmartColl, v:getParent(), pubSrv, v:getName() )
                end
            end } )
        else
            s, m = app:call( Call:new{ name=title, main=function( call )
                for i, v in ipairs( lrColls ) do
                    local pubSrv
                    if v:type() == 'LrPublishedCollection' then
                        pubSrv = v:getService()
                    elseif v:type():find( "LrCollection" ) then
                        -- pubSrv = nil
                    end
                    --Debug.pause( pubSrv )
                    self:_dupOrSyncCollection( sourceColl, v:getParent(), pubSrv, v:getName() )
                end
            end } )
        end
        
        if not s then
            error( m )
        end
        
    end, finale=function( call, status, message )

        app:log( "\n\n" ) 
        if status and not call:isCanceled() and not call:isAborted() then -- cancel, abort, or throw error if trouble syncing collection sets.
            app:log( "Collection sets sync'd." )
            -- self.syncSource = nil - allow repeated synchronizations? ###2
        end
        app:log( "\n\n" ) 
        
        self:_killScope() -- so its dead when the finale dbox comes on, if it does.
        --Debug.showLogFile()
    
    end } )
    
end



function CollectionAgent:copy()
    app:call( Service:new{ name="Copy Collections or Sets", async=true, guard=App.guardVocal, main=function( call )
    
        self:_init( call )
        self.syncNotDup = false -- false means an error will be thrown upon duplicate collection. This is required for smart collections in this context,
            -- since otherwise a copy would alter settings of a supposedly newly created smart collection.
        
        if self.copySources == nil then
            app:show{ warning="Use 'Set Copy Source (Collections and/or Sets)' first." }
            call:cancel()
            return
        end
        
        local lrTargets = {}
        local lrTargetSet
        local lrTargetName
        local lrSourceName
        local pubSrv
        
        for i, target in ipairs( catalog:getActiveSources() ) do
            local targetType = cat:getSourceType( target )
            local targetName = cat:getSourceName( target )
            if targetType == 'LrCollectionSet' then
                lrTargets[#lrTargets + 1] = target
                lrTargetSet = target
                lrTargetName = targetName
            elseif targetType == 'LrPublishedCollectionSet' then
                lrTargets[#lrTargets + 1] = target
                lrTargetSet = target
                lrTargetName = targetName
                pubSrv = target:getService()
            elseif targetType == 'LrCollection' then
                local p = target:getParent()
                if p then
                    lrTargets[#lrTargets + 1] = p
                    lrTargetSet = p
                    lrTargetName = p:getName()
                else
                    lrTargets[#lrTargets + 1] = catalog
                    lrTargetSet = catalog
                    lrTargetName = "Catalog Root"
                end
            elseif targetType == 'LrPublishedCollection' then
                local p = target:getParent()
                if p then
                    lrTargets[#lrTargets + 1] = p
                    lrTargetSet = p
                    lrTargetName = p:getName()
                else
                    pubSrv = target:getService()
                    lrTargets[#lrTargets + 1] = pubSrv
                    lrTargetSet = pubSrv
                    lrTargetName = pubSrv:getName()
                end
            else
                app:logWarning( "Target ignored: ^1", targetName )
            end
        end
        
        if not lrTargetSet then
            app:show{ warning="Select target collection set (or child of target collection-set) first." }
            call:cancel()
            return
        end
        
        if #lrTargets > 1 then
            app:show{ warning="Select only one target collection set (or child of target collection-set)." }
            call:cancel()
            return
        end
        
        local answer = app:show{ info="Copy from ^1 to ^2?",
            subs = { str:plural( #self.copySources, "source", true ), lrTargetName },
            buttons = { dia:btn( "Yes - Photos Too", 'ok' ), dia:btn( "Yes - No Photos", 'other' ) },
            actionPrefKey = 'Copy confirm',
        }
        if answer == 'ok' then
            self.photosToo = true
        elseif answer == 'other' then
            self.photosToo = false
        elseif answer == 'cancel' then
            call:cancel()
            return
        else
            error( "bad answer" )
        end            
        
        self:_createScope( "Copying collections/sets", "Please wait..." ) -- and assign to self.
        
        for i, copySource in ipairs( self.copySources ) do -- clean
            repeat
                local sourceSet
                local sourceColl
                local lrSourceName
                if copySource.type and copySource.getName then
                    local typ = copySource:type()
                    if typ:find( "CollectionSet" ) then
                        sourceSet = copySource
                    else
                        sourceColl = copySource
                    end
                    lrSourceName = copySource:getName()
                elseif copySource == catalog then
                    sourceSet = copySource
                    lrSourceName = "Catalog Root"
                else
                    app:log( "Ignoring source: ^1", cat:getSourceName( copySource ) )
                    break
                end
                
                local set
                if sourceSet then
                    local s, m = cat:update( 20, str:fmt( "copy collection set: ^1", lrSourceName ), function( context, phase )
                        if not pubSrv then
                            set = catalog:createCollectionSet( lrSourceName, lrTargetSet, false )
                        else
                            set = pubSrv:createPublishedCollectionSet( lrSourceName, lrTargetSet, false )
                        end
                    end )
                    if s then
                        if set then
                            local s, m = app:call( Call:new{ name="Copy collection set trees", main=function( call )
                                self:_dupOrSyncChildren( sourceSet, set, pubSrv )
                            end } )
                            if not s then
                                error( m )
                            end
                        else
                            app:error( "Unable to create collection set - check if a collection set named ^1 already exists - that would explain it ;-}", lrSourceName )
                        end
                    else
                        app:logErr( "Unable to create top-level collection set - ^1", m )
                        return
                    end
                elseif sourceColl then
                    self:_dupOrSyncCollection( sourceColl, lrTargetSet, pubSrv )
                else
                    error( "no source" )
                end
            until true        
        end
        
    end, finale=function( call, status, message )

        app:log( "\n\n" ) 
        if status and not call:isCanceled() and not call:isAborted() then -- cancel, abort, or throw error if trouble syncing collection sets.
            app:log( "Collections or sets copied." )
            -- self.copySources = nil - allow repeated copies? ###2
        end
        app:log( "\n\n" ) 
        
        self:_killScope() -- so its dead when the finale dbox comes on, if it does.
        --Debug.showLogFile()
    
    end } )
    
end



function CollectionAgent:editAsCollection()
    app:call( Call:new{ name="Edit As Collection", async=true, main=function( call )
        local photos = catalog:getMultipleSelectedOrAllPhotos()
        if #photos == 0 then
            app:show{ warning="No photos." }
            return
        end
        local coll = cat:assurePluginCollection( "Edit Collection" )
        cat:setCollectionPhotos( coll, photos )
        catalog:setActiveSources{ coll }
    end } )
end



--- Import all smart collections only (LrFourB is handling regular collections).
--
function CollectionAgent:importAll()
    app:service{ name="Import Lr3 Smart Collections", async=true, main=function( call )
        local dir = dia:selectFolder{
            title = "Select Lr3 catalog folder (with previously saved stuff)",
        }
        if dir == nil then
            call:cancel()
            return
        end
        self.smartDir = LrPathUtils.child( dir, "Smart Collection Definitions" )
        self.pubSmartDir = LrPathUtils.child( dir, "Publish Collection Definitions" )
        local creator
        local importColl
        local importSet
        local importChildren
        local isPub
        local function writeRules( ent, name, parent )
            local smartDef = ent
            local rules -- note: import-all can not take advantage of Lr5's get-search-description, since source of import defs is lrsmcol's from (typically) another catalog.
            if fso:existsAsFile( smartDef ) then
                local def = rawset( _G, 's', nil )
                pcall( dofile, smartDef )
                def = rawget( _G, 's' )
                if def then
                    rules = def.value
                    if rules then
                        app:logVerbose( "Got rules from exported collection." )
                    else
                        app:logError( "Unable to get rules from collection export." )
                    end
                else
                    app:logError( "Unable to load smart def at ^1", smartDef )
                end
            end
            if rules then
                app:logVerbose( "Got smart collection rules for ^1 at ^2", name, smartDef )
            else
                app:logError( "No smart collection rules for ^1 at ^2 - to remedy, export them there from source collection, or if you are using SQLiteroom, just restart Lightroom, then retry.", name, smartDef )
                return
            end
            local s, m = cat:update( 20, str:fmt( "Creation or update of smart collection ^1", name ), function( context, phase )
                local searchDesc = rules
                local c
                if not isPub then
                    c = creator:createSmartCollection( name, searchDesc, parent, true )
                else
                    c = creator:createPublishedSmartCollection( name, searchDesc, parent, true )
                end
                if not c then
                    app:logError( "Unable to create or update smart collection ^1", name )
                else
                    Debug.lognpp( rules )
                    c:setSearchDescription( rules ) -- update explicitly 
                    app:log( "Created or updated smart collection ^1", name )
                end
            end )
            if s then
                app:log( "Wrote rules: " .. ent )
            else
                app:logError( m )
            end
        end
        function importColl( ent, parent )
            Debug.logn( "coll", ent )
            local filename = LrPathUtils.leafName( ent )
            local name = LrPathUtils.removeExtension( filename )
            writeRules( ent, name, parent )
        end    
        function importSet( ent, parent )
            Debug.logn( "set", ent )
            local name = LrPathUtils.leafName( ent )
            local set
            local s, m = cat:update( 20, "Creating or verifying collection set " .. name, function( context, phase )
                if isPub then
                    set = creator:createPublishedCollectionSet( name, parent, true )
                else
                    set = creator:createCollectionSet( name, parent, true )
                end
            end )
            if s and set then
                importChildren( ent, set )
            else
                app:logError( "No set - ^1", str:to( m ) )
            end
        end
        function importChildren( dir, parent )
            Debug.logn( "children", dir )
            for ent in LrFileUtils.directoryEntries( dir ) do
                if LrFileUtils.exists( ent ) == 'directory' then
                    importSet( ent, parent )
                end
            end
            for ent in LrFileUtils.directoryEntries( dir ) do
                if LrFileUtils.exists( ent ) == 'file' then
                    importColl( ent, parent )
                end
            end
        end
        creator = catalog
        isPub = false
        importChildren( self.smartDir, nil )
        -- pub-srv loop
        isPub = true
        local srvs = catalog:getPublishServices()
        for i, srv in ipairs( srvs ) do
            creator = srv
            local d = LrPathUtils.child( self.pubSmartDir, srv:getName() )
            --Debug.pause( d )
            importChildren( d, nil )
        end
        
--:_dupOrSyncCollection( source, dest, pubSrv, newName )        
--:_dupOrSyncChildren( source, dest, pubSrv )        
        
    end }
end



--- Assure smart collections have a dumb shadow collection, primarily for Lr mobile syncing.
function CollectionAgent:maintDumbSmarts( title )
    app:service{ name=title, async=true, guard=App.guardVocal, progress=true, function( call )
        local s, m = background:pause( 60 )
        if not s then
            app:show{ warning="Cant pause background task." }
            return
        end
        call:setCaption( "Scrutinizing selected sources" )
        local dumbColls = {}
        local sources = catalog:getActiveSources()
        local getDumbCollName = app:getPref{ name='getDumbCollName', default=function( params )
            local smartCollName = params.smartCollName or app:callingError( "no smart coll name" )
            return "_"..smartCollName
        end }
        if #sources == 0 then
            app:log( "No sources are selected." )
        elseif #sources == 1 then
            local typ = cat:getSourceType( sources[1] )
            if typ == 'special' then
                app:log( "The only source selected is one of Lr's special collections: ^1", ( cat:getSourceName( sources[1] ) ) )
                sources = {}
            elseif typ == 'LrCollection' and sources[1]:isSmartCollection() or typ == 'LrCollectionSet' then
                -- proceed            
            else
                app:logW( "Invalid source type: ^1", typ )
                return
            end
        -- else - multiple sources, proceed.
        end
        if #sources == 0 then
            call:setCaption( "Presenting dialog box" )
            if dia:isOk( "Consider all smart collections in catalog? (excluding those in publish services)" ) then
                sources = { catalog }
                app:log( "Considering all smart collections in catalog (excluding those in publish services)." )
            else
                return
            end
        else
            app:log( "Considering smart collections in ^1", str:oneOrMore( #sources, "active source", "active sources" ) )
        end
        local tidbit
        if #sources == 1 then
            local source = sources[1]
            local typ = cat:getSourceType( source )
            local name, id = cat:getSourceName( source )
            if source == catalog then
                tidbit = str:fmtx( " (corresponding to smart collections in whole catalog)" )
            elseif typ:sub( -3 ) == 'Set' then
                tidbit = str:fmtx( " (corresponding to smart collections in '^1')", ( cat:getSourceName( sources[1] ) ) )
            elseif typ:sub( -3 ) == 'ion' then -- collection (smart).
                tidbit = str:fmtx( " (corresponding to smart collection: '^1')", ( cat:getSourceName( sources[1] ) ) )
            else
                Debug.pause( "?", typ )
                tidbit = str:fmtx( " (corresponding to smart collections in '^1')", ( cat:getSourceName( sources[1] ) ) )
            end
        else
            tidbit = str:fmtx( " (corresponding to smart collections in ^1)", str:oneOrMore( #sources, "source", "sources" ) )
        end
        call:setCaption( "Assessing smart collections" )
        local collRecs = {} -- to create/update or remove.
        local function doSmartColl( smartColl, parent )
            app:assert( parent == smartColl:getParent(), "^1 | ^2", parent, smartColl:getParent() ) -- ###1 may not always be true in future.
            local scName = smartColl:getName()
            local dcName = getDumbCollName{ 
                smartCollName = scName,
            } or error( "no dumb coll name" )
            if #dcName > 0 then
                if str:isEqualIgnoringCase( scName, dcName ) then
                    app:logW( "Dumb collection name can not be same as smart collection name: ^1", scName )
                else
                    collRecs[#collRecs + 1] = { dumbCollName=dcName, parent=parent, smartColl=smartColl }
                end
            else
                app:log( "Dumb collection name is empty - taking a pass (smart coll name is '^1')", scName )
            end
        end
        local function doColl( coll, parent )
            if coll:isSmartCollection() then
                doSmartColl( coll, parent )
            else
                --doDumbColl( coll )
                app:logV( "Ignoring regular collection (in '^1'): ^2", parent and ( cat:getSourceName( parent ) ) or "catalog", coll:getName() )
            end
        end
        local function doCollSet( collSet )
            for i, coll in ipairs( collSet:getChildCollections() ) do
                Debug.pauseIf( collSet == catalog, "###1" )
                local parent = ( collSet ~= catalog ) and collSet or nil
                doColl( coll, parent )
            end
            for i, childSet in ipairs( collSet:getChildCollectionSets() ) do
                doCollSet( childSet )
            end
        end
        for i, src in ipairs( sources ) do
            local typ = cat:getSourceType( src )
            if typ == 'LrCollection' then
                doColl( src, src:getParent() ) -- ###1 will need to massage if alt-parent coll-set supported.
            elseif typ == 'LrCollectionSet' then
                doCollSet( src )
            elseif typ == 'LrCatalog' then -- "pseudo" type.
                assert( src==catalog, "?" )
                doCollSet( catalog )
            else
                app:logW( "Source type not supported: ^1 (if this limitation seems unnecessary, inform ^2).", typ, app:getInfo( 'author' ) )
            end
        end
        if #collRecs > 0 then
            -- main/mandatory prompt, to do it, or not.. - reminder: is within the cat-upd method, which is unconventional.
            call:setCaption( "Presenting dialog box" )
            app:initPref( 'updCre', true )
            app:initPref( 'autoUpd', true )
            local vi = {}
            vi[#vi + 1] = vf:row {
                vf:checkbox {
                    title = "Create/update",
                    value = app:getPrefBinding( 'updCre' ),
                    tooltip = "If checked, dumb collections will be created and/or updated; if unchecked, dumb collections will be removed.",
                },
                vf:spacer{ width=1 },
                vf:checkbox {
                    title = "Tag smart collections so dumb collections get auto-updated in the background.",
                    value = app:getPrefBinding( 'autoUpd' ),
                    enabled = app:getPrefBinding( 'updCre' ),
                    tooltip = "If checked, smart collection will be modified (in a way which does not affect functionality) so dumb collections will be updated automatically in the background (if auto-updating is enabled in plugin manager); if unchecked, you will need to update manually.",
                },
            }
            local answer = app:show{ confirm="Maintain ^1?^2",
                subs = { str:oneOrMore( #collRecs, "dumb collection", "dumb collections" ), tidbit },
                viewItems = vi,
            }
            if answer == 'ok' then
                -- proceed
            else
                call:cancel()
                return
            end
        else -- smart-coll-recs is zero, presumably because no smart colls found in selected sources.
            app:show{ warning="No smart collections found based on selected photo source(s)." }
            return
        end
        -- go: process..
        local updCre = app:getPref( 'updCre' )
        local autoUpd = app:getPref( 'autoUpd' )
        local collRecs2 = {}
        local nProcessed = 0
        local collInfo = {}
        local nDel = 0
        if updCre then
            call:setCaption( "Creating/updating dumb collections.." )
        else
            call:setCaption( "Removing dumb collections.." )
            local colls = cat:getCollsInCollSet( catalog, true ) -- smart colls too.
            for i, c in ipairs( colls ) do
                local cs = c:getParent()
                if not cs then
                    cs = catalog
                end
                local a = collInfo[cs]
                if a then
                    a[c:getName()] = c
                else
                    collInfo[cs] = { [c:getName()] = c }
                end
            end
        end
        local s, m = cat:update( 30, "Maintain smart/dumb collections", function( context, phase )
            if phase == 1 then -- assure/create dumb collections
                for i, rec in ipairs( collRecs ) do
                    local function assureTag( tagCount, dumbColl )
                        local sd = rec.smartColl:getSearchDescription()
                        local rmvI = {}
                        for i, rule in ipairs( sd ) do
                            if rule.value == "__CollectionAgent_AutoUpdateDumbColl__" then
                                rmvI[#rmvI + 1] = i
                            end
                        end
                        if #rmvI > tagCount then
                            for i = #rmvI, 1 + tagCount, -1 do
                                table.remove( sd, rmvI[i] )
                            end
                            rec.smartColl:setSearchDescription( sd )
                            app:log( "Removed auto-update tag from smart collection: ^1", collections:getFullCollPath( rec.smartColl ) )
                            local assured, dang = background:assureSync( rec.smartColl, tagCount > 0, dumbColl )
                            if not assured then
                                app:logW( dang )
                            end
                        elseif #rmvI < tagCount then
                            sd[#sd + 1] = {
                                operation = "noneOf", 
                                value2 = "", 
                                criteria = "keywords", 
                                value = "__CollectionAgent_AutoUpdateDumbColl__"
                            }
                            rec.smartColl:setSearchDescription( sd )
                            app:log( "Added auto-update tag to smart collection: ^1", collections:getFullCollPath( rec.smartColl ) )
                            local assured, dang = background:assureSync( rec.smartColl, tagCount > 0, dumbColl )
                            if not assured then
                                app:logW( dang )
                            end
                        else
                            app:logV( "Smart collection auto-update tags were not altered: ^1", collections:getFullCollPath( rec.smartColl ) )
                        end
                    end
                    if updCre then
                        app:assert( rec.parent == rec.smartColl:getParent(), "^1 | ^2", rec.parent or "??", rec.smartColl:getParent() or "???" )
                        local dumbColl = catalog:createCollection( rec.dumbCollName, rec.parent, true ) -- true => return if already existing.
                        if dumbColl then
                            if autoUpd then
                                assureTag( 1, dumbColl )
                            else
                                assureTag( 0, dumbColl )
                            end
                            collRecs2[#collRecs2 + 1] = { smartColl=rec.smartColl, dumbColl=dumbColl, parent=rec.parent }
                        else
                            app:logW( "Unable to create dumb collection corresponding to '^1' in '^2'", rec.smartColl:getName(), ( cat:getSourceName( rec.parent ) ) )
                        end
                    else -- remove smart coll marking and delete dumb coll.
                        assureTag( 0 ) -- no dumb-coll
                        local a = collInfo[rec.parent or catalog]
                        if a then
                            local c = a[rec.dumbCollName]
                            if c then
                                c:delete()
                                nDel = nDel + 1
                            else
                                app:logV( "No dumb coll for smart coll" )
                            end
                        else
                            app:logV( "No dumb colls for parent of smart coll" )
                        end                        
                    end
                end
                if #collRecs2 > 0 then
                    return false -- keep going via phase 2
                else
                    return true -- done
                end
            elseif phase == 2 then -- populate dumb collections
                for i, rec2 in ipairs( collRecs2 ) do
                    local photos, eh = sco:getPhotos( rec2.smartColl )
                    if photos then
                        local status, nAdded, nRemoved = LrTasks.pcall( cat.setCollectionPhotos, cat, rec2.dumbColl, photos, 30 ) -- tmo ignored, error if problem.
                        dumbColls[#dumbColls + 1] = rec2.dumbColl
                        if status then
                            assert( nAdded and nRemoved, "?" )
                            if nAdded > 0 or nRemoved > 0 then
                                nProcessed = nProcessed + 1
                            -- else no change
                            end
                        else
                            app:logE( nAdded ) -- errm.
                        end
                    else
                        app:logW( eh or "neh" )
                    end
                end
            end
        end )
        call:setCaption( "Presenting dialog box" )
        if s then
            if nDel > 0 then
                app:log( "^1 deleted.", str:oneOrMore( nDel, "dumb collection", "dumb collections" ) )
            end
            if #dumbColls > 0 then
                app:log( "Catalog updated if necessary." )
                local answer = app:show{ confirm="^1 - select now?",
                    subs = { str:oneOrMore( #dumbColls, "dumb collection", "dumb collections" ) },
                    buttons = dia:yesNo(), -- 'No' answer is also memorable, by default.
                    actionPrefKey = "Select dumb collections",
                }
                if answer=='ok' then
                    catalog:setActiveSources( dumbColls )
                elseif answer == 'cancel' then
                    app:logV( "Not going to dumb collections, as user dictated." )
                else
                    error( "bad answer" )
                end
            else
                app:logV( "No dumb collections to select." )
            end
        elseif not call:isCanceled() and m then -- call is still in play, but there was an error.
            app:logE( m )
            return
        -- else canceled - no errm.
        end
    end, finale=function( call )
        background:continue()
    end }
end


return CollectionAgent
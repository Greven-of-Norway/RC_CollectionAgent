--[[
        ExtendedManager.lua
--]]


local ExtendedManager, dbg, dbgf = Manager:newClass{ className='ExtendedManager' }



--[[
        Constructor for extending class.
--]]
function ExtendedManager:newClass( t )
    return Manager.newClass( self, t )
end



--[[
        Constructor for new instance object.
--]]
function ExtendedManager:new( t )
    return Manager.new( self, t )
end



--- Initialize global preferences.
--
function ExtendedManager:_initGlobalPrefs()
    -- Instructions: delete the following line (or set property to nil) if this isn't an export plugin.
    --fprops:setPropertyForPlugin( _PLUGIN, 'exportMgmtVer', "2" ) -- a little add-on here to support export management. '1' is legacy (rc-common-modules) mgmt.
    -- Instructions: uncomment to support these external apps in global prefs, otherwise delete:
    -- app:initGlobalPref( 'exifToolApp', "" )
    -- app:initGlobalPref( 'mogrifyApp', "" )
    -- app:initGlobalPref( 'sqliteApp', "" )
    -- app:registerPreset( "My Preset", 2 )
    local collExportPath = LrPathUtils.child( cat:getCatDir(), "Smart Collection Definitions" )
    if str:is( app:getPref( 'smartCollDefs' ) ) then -- not first run
        app:show{ warning="Location of smart collection definitions is now fixed at: ^1", collExportPath }
        app:setPref( 'smartCollDefs', "" )
    end
    -- Init base prefs:
    Manager._initGlobalPrefs( self )
end



--- Initialize local preferences for preset.
--
--  @usage **** Prefs defined here will overwrite like-named prefs if defined via system-settings.
--
function ExtendedManager:_initPrefs( presetName )
    -- Instructions: uncomment to support these external apps in local (preset) prefs, otherwise delete:
    -- app:initPref( 'imageMagickDir', "", presetName ) -- for Image Magick support.
    -- app:initPref( 'exifToolApp', "", presetName )
    -- app:initPref( 'mogrifyApp', "", presetName ) - deprecated.
    -- app:initPref( 'sqliteApp', "", presetName )
    -- *** Instructions: delete this line if no async init or continued background processing:
    app:initPref( 'background', true, presetName ) -- true to support on-going background processing, after async init (auto-update most-sel photo).
    app:initPref( 'backgroundPeriod', 1, presetName ) -- hard-wired to base background class.
    Manager._initPrefs( self, presetName )
end



--- Start of plugin manager dialog.
-- 
function ExtendedManager:startDialogMethod( props )
    Manager.startDialogMethod( self, props ) -- adds observer to all props.
end



--- Preference change handler.
--
--  @usage      Handles preference changes.
--              <br>Preferences not handled are forwarded to base class handler.
--  @usage      Handles changes that occur for any reason, one of which is user entered value when property bound to preference,
--              <br>another is preference set programmatically - recursion guarding is essential.
--
function ExtendedManager:prefChangeHandlerMethod( _id, _prefs, key, value )
    Manager.prefChangeHandlerMethod( self, _id, _prefs, key, value )
end



--- Property change handler.
--
--  @usage      Properties handled by this method, are either temporary, or
--              should be tied to named setting preferences.
--
function ExtendedManager:propChangeHandlerMethod( props, name, value, call )
    -- this logic implements the ad-hoc recursion protection, so no gating/guarding is required.
    if app.prefMgr and (app:getPref( name ) == value) then -- eliminate redundent calls.
        -- Note: in managed cased, raw-pref-key is always different than name.
        -- Note: if preferences are not managed, then depending on binding,
        -- app-get-pref may equal value immediately even before calling this method, in which case
        -- we must fall through to process changes.
        return
    end
    -- *** Instructions: strip this if not using background processing:
    if name == 'background' then
        app:setPref( 'background', value )
        if value then
            local started = background:start()
            if started then
                app:show( "Auto-update started." )
            else
                app:show( "Auto-update already started." )
            end
        elseif value ~= nil then
            app:call( Call:new{ name = 'Stop Background Task', async=true, guard=App.guardVocal, main=function( call )
                local stopped
                repeat
                    stopped = background:stop( 10 ) -- give it some seconds.
                    if stopped then
                        app:logVerbose( "Auto-update was stopped by user." )
                        app:show( "Auto-update is stopped." ) -- visible status wshould be sufficient.
                    else
                        if dialog:isOk( "Auto-update stoppage not confirmed - try again? (auto-update should have stopped - please report problem; if you cant get it to stop, try reloading plugin)" ) then
                            -- ok
                        else
                            break
                        end
                    end
                until stopped
            end } )
        end
    else
        -- Note: preference key is different than name.
        Manager.propChangeHandlerMethod( self, props, name, value, call )
        -- Note: properties are same for all plugin-manager presets, but the prefs where they get saved changes with the preset.
    end
end



--- Sections for bottom of plugin manager dialog.
-- 
function ExtendedManager:sectionsForBottomOfDialogMethod( vf, props)

    local appSection = {}
    if app.prefMgr then
        appSection.bind_to_object = props
    else
        appSection.bind_to_object = prefs
    end
    
	appSection.title = app:getAppName() .. " Settings"
	appSection.synopsis = bind{ key='presetName', object=prefs }

	appSection.spacing = vf:dialog_spacing()

    
    if app:lrVersion() >= 5 then
    	if gbl:getValue( 'background' ) then
            appSection[#appSection + 1] =
                vf:row {
                    bind_to_object = props,
                    vf:static_text {
                        title = "Auto-update control",
                        width = share 'label_width',
                    },
                    vf:checkbox {
                        title = "Automatically update tagged smart collections.",
                        value = bind( 'background' ),
        				tooltip = "To tag a smart collection for automatic updates, use 'Make Dumb Collection from Smart Collections' function.",
                        width = share 'data_width',
                    },
                }
            appSection[#appSection + 1] =
                vf:row {
                    vf:static_text {
                        title = "Auto-update status",
                        width = share 'label_width',
                    },
                    vf:static_text {
                        bind_to_object = prefs,
                        title = app:getGlobalPrefBinding( 'backgroundState' ),
                        width_in_chars = 70,--share 'data_width',
                        tooltip = 'auto-update status',
                    },
                }
            appSection[#appSection + 1] =
                vf:row {
                    vf:static_text {
                        title = "Auto-update interval",
                        width = share 'label_width',
                    },    
                    vf:edit_field {
                        value = bind 'backgroundPeriod',
                        width_in_digits = 5,
                        precision = 0,
                        min = 1,
                        max = 99999,
                        tooltip = "If updating too slowly, reduce this number; if background process is using too much CPU - increase it.\n \nThe default is one second, so dumb collection is updated almost immediately when smart collection changes, but if you don't need immediate responsiveness consider a setting much higher, like 60 to do once per minute, or 3600 to do once per hour..",
                    },
                    vf:static_text {
                        title = "Update dumb collections every this many seconds in the background."
                    },
                }
        end            
    
    else
        appSection[#appSection + 1] = 	
            vf:row { 
                vf:static_text {
                    title = str:fmt( "Smart Collection Definitions: ^1", LrPathUtils.child( cat:getCatDir(), "Smart Collection Definitions" ) ),
                    text_color = LrColor( 'blue' ),
                    mouse_down = function()
                        LrShell.revealInShell( LrPathUtils.child( cat:getCatDir(), "Smart Collection Definitions" ) )
                    end
                }
            }
        appSection[#appSection + 1] = 	
            vf:row { 
                vf:static_text {
                    title = str:fmt( "Publish Collection Definitions: ^1", LrPathUtils.child( cat:getCatDir(), "Publish Collection Definitions" ) ),
                    text_color = LrColor( 'blue' ),
                    mouse_down = function()
                        LrShell.revealInShell( LrPathUtils.child( cat:getCatDir(), "Publish Collection Definitions" ) )
                    end
                },
            }
    end
    
    appSection[#appSection + 1] = vf:spacer { height = 5 }
    appSection[#appSection + 1] = 	
        vf:row { 
            vf:push_button {
                title = 'Divide to Conquor',
                action = function( button )
                    app:call( Service:new{ name=button.title, async=true, main=function( call )
                        local targets = catalog:getMultipleSelectedOrAllPhotos()
                        local nPer = dia:getNumericInput{
                            title = app:getAppName() .. " - Divide to Conquor",
                            subtitle = str:fmt( "Enter number per collection\n(^1 total to divide up)", #targets ),
                        }
                        if not nPer then
                            call:cancel()
                            return
                        end
                        self.scope = LrProgressScope {
                            title = "Dividing to Conquor",
                            caption = "Filling first collection...",
                            functionContext = call.context,
                        }
                        local part = 1
                        local cnt = 0
                        local photos = {}
                        for i, photo in ipairs( targets ) do
                            if #photos < nPer then
                                photos[#photos + 1] = photo
                            else
                                local name = str:fmt( "Part ^1", part )
                                local coll = cat:assurePluginCollection( name )
                                local s, m = cat:update( 20, str:fmt( "Removing photos from ^1", name ), function( context, phase )
                                    if phase == 1 then
                                        coll:removeAllPhotos()
                                        return false
                                    elseif phase == 2 then
                                        coll:addPhotos( photos )
                                        return true
                                    else
                                        app:error( "Catalog update phase out of range: ^1", phase )
                                    end
                                end )
                                if not s then
                                    error( m )
                                end
                                self.scope:setCaption( str:fmt( "Filled collection ^1", name ) )
                                photos = {}
                                part = part + 1
                            end
                            if not self.scope:isCanceled() then
                                self.scope:setPortionComplete( i, #targets )
                            else
                                call:cancel()
                                return
                            end
                        end
                        if #photos > 0 then
                            local name = str:fmt( "Part ^1", part )
                            local coll = cat:assurePluginCollection( name )
                            local s, m = cat:update( 20, str:fmt( "Removing photos from ^1", name ), function( context, phase )
                                if phase == 1 then
                                    coll:removeAllPhotos()
                                    return false
                                elseif phase == 2 then
                                    coll:addPhotos( photos )
                                    return true
                                else
                                    app:error( "Catalog update phase out of range: ^1", phase )
                                end
                            end )
                            if not s then
                                error( m )
                            end
                            self.scope:setCaption( str:fmt( "Last collection ^1", name ) )
                            part = part + 1
                        end
                        local name = str:fmt( "Part ^1", part )
                        local coll = cat:assurePluginCollection( name )
                        local s, m = cat:update( 20, str:fmt( "Removing photos from ^1", name ), function( context, phase )
                            coll:removeAllPhotos()
                        end )
                        if not s then
                            error( m )
                        end
                        
                    end, finale=function( call, status, message )
                    
                        if status then
                            -- leave final collection message up.
                            --if not call:isCanceled() then
                            --    self.scope:done()
                            --else - no need
                                -- self.scope:cancel()
                            --end
                        else
                            self.scope:setCaption( message )
                        end
                    
                    end } )
                end    
            },              
            vf:static_text {
                title = "Divide selected photos into sets of equal number and put in collections.",
            }
        }



    if not app:isRelease() then
    	appSection[#appSection + 1] = vf:spacer{ height = 20 }
    	appSection[#appSection + 1] = vf:static_text{ title = 'For plugin author only below this line:' }
    	appSection[#appSection + 1] = vf:separator{ fill_horizontal = 1 }
    	appSection[#appSection + 1] = 
    		vf:row {
    			vf:edit_field {
    				value = bind( "testData" ),
    			},
    			vf:static_text {
    				title = str:format( "Test data" ),
    			},
    		}
    	appSection[#appSection + 1] = 
    		vf:row {
    			vf:push_button {
    				title = "Test",
    				action = function( button )
    				    app:call( Call:new{ name='Test', main = function( call )
                            app:show( { info="^1: ^2" }, str:to( app:getGlobalPref( 'presetName' ) or 'Default' ), app:getPref( 'testData' ) )
                        end } )
    				end
    			},
    			vf:static_text {
    				title = str:format( "Perform tests." ),
    			},
    		}
    end
		
    local sections = Manager.sectionsForBottomOfDialogMethod ( self, vf, props ) -- fetch base manager sections.
    if #appSection > 0 then
        tab:appendArray( sections, { appSection } ) -- put app-specific prefs after.
    end
    return sections
end



return ExtendedManager
-- the end.
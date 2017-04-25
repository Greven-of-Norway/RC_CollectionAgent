--[[
        Info.lua
--]]

return {
    appName = "Collection Agent",
    author = "Rob Cole",
    authorsWebsite = "www.robcole.com",
    donateUrl = "http://www.robcole.com/Rob/Donate",
    platforms = { 'Windows', 'Mac' },
    pluginId = "com.robcole.lightroom.CollectionAgent",
    xmlRpcUrl = "http://www.robcole.com/Rob/_common/cfpages/XmlRpc.cfm",
    LrPluginName = "rc Collection Agent",
    LrSdkMinimumVersion = 3.0,
    LrSdkVersion = 5.0,
    LrPluginInfoUrl = "http://www.robcole.com/Rob/ProductsAndServices/CollectionAgentLrPlugin",
    LrPluginInfoProvider = "ExtendedManager.lua",
    LrToolkitIdentifier = "com.robcole.lightroom.CollectionAgent",
    LrInitPlugin = "Init.lua",
    LrShutdownPlugin = "Shutdown.lua",
    LrExportMenuItems = {
        {
            title = "&Maintain Dumb Copies of Smart Collections",
            file = "mMaintDumbSmarts.lua",
        },
        {
            title = "&Duplicate (Collection or Set)",
            file = "mDuplicate.lua",
        },
        {
            title = "&Set Sync Source (Collection or Set)",
            file = "mSetSyncSource.lua",
        },
        {
            title = "&Sync (Selected Collections or Sets)",
            file = "mSync.lua",
        },
        {
            title = "&Set Copy Sources (Collections and/or Sets)",
            file = "mSetCopySources.lua",
        },
        {
            title = "&Copy (Collections and/or Sets)",
            file = "mCopy.lua",
        },
        {
            title = "&Import All (Smart Collections)",
            file = "mImportAll.lua",
        },
        {
            title = "&Edit (Selected Photos) As Collection",
            file = "mEdit.lua",
        },
    },
    VERSION = { display = "4.0.3    Build: 2015-01-23 02:54:15" },
}

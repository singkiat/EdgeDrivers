local log = require "log"
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"  
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local utils = require "st.utils"
local commands = require "commands"
local myutils = require "utils"

local tuyaEF00_defaults = require "tuyaEF00_defaults"
local tuyaEF00_model_defaults = require "tuyaEF00_model_defaults"

-- Route commands to model's datapoint processing
local function send_model_command(device, command)
  local driver = device:get_parent_device() and device:get_parent_device().driver or device.driver
  tuyaEF00_model_defaults.capability_handler(driver, device, command)
end

-- Log device configuration
local function log_moes_configuration(device)
  myutils.log(device, "info", "Moes Curtain configured")
end



-- Moes Curtain Sub-Driver: Hybrid DP routing (DP 1: windowShade, DP 9: setShadeLevel)
local template = {
  NAME = "MoesCurtain",
  
  -- Device identification - DISABLED: Let framework handle all devices naturally
  can_handle = function(opts, driver, device, ...)
    -- 🚫 SUB-DRIVER DISABLED: Framework now handles Moes devices directly via model configs
    -- No longer needed since we have:
    -- ✅ Universal transition logic in commands.lua  
    -- ✅ Correct model files (DP8→status, DP9→commands)
    -- ✅ Fixed profile preferences
    -- ✅ Unified windowShadeLevelStatus handler
    
    return false  -- Let framework handle everything
  end,
  
  supported_capabilities = {
    capabilities.windowShade,
    capabilities.windowShadeLevel, 
    capabilities.windowShadePreset,
    capabilities.refresh,
    capabilities["valleyboard16460.debug"],
  },
  
  -- 🎯 BREAKTHROUGH: Remove command handlers to allow direct framework handling
  -- Only keep refresh - let framework handle setShadeLevel/presetPosition via model config
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = function(driver, device, command)
        device:send(zcl_clusters.TuyaEF00.commands.DataQuery(device))
      end,
    },
  },
  
  -- Note: Zigbee handlers preserved for default signal strength and battery handling
  
  -- Lifecycle handlers
  lifecycle_handlers = {
    added = function(driver, device, event, ...)
      log_moes_configuration(device)
      
      -- ⭐ CRITICAL: Load framework model datapoints for DP routing
      myutils.log(device, "info", "🔧 Loading Moes Curtain through framework...")
      tuyaEF00_model_defaults.lifecycle_handlers.added(driver, device, event)
      
      -- Request initial status
      device.thread:call_with_delay(2, function()
        device:send(zcl_clusters.TuyaEF00.commands.DataQuery(device))
      end)
    end,
    
    init = function(driver, device, event, ...)
      myutils.log(device, "info", "🔧 Initializing existing Moes Curtain device...")
      -- Load framework model datapoints for existing devices
      tuyaEF00_model_defaults.lifecycle_handlers.added(driver, device, event)
    end,
    
    infoChanged = function(driver, device, event, args, ...)
      myutils.log(device, "info", "🔹 Moes Curtain Device Info Changed")
      
      -- Update profile if changed
      if args.old_st_store.preferences.profile ~= device.preferences.profile then
        myutils.update_profile(device, device.preferences.profile, args.old_st_store.preferences.profile)
      end
      
      -- Update datapoints if preferences changed
      if args.old_st_store.preferences.moesCurtainDatapoints ~= device.preferences.moesCurtainDatapoints then
        myutils.log(device, "info", "🔹 Moes Curtain datapoint preference updated")
        log_moes_configuration(device)
        -- ⭐ CRITICAL: Reload model datapoints when preferences change
        tuyaEF00_model_defaults.lifecycle_handlers.infoChanged(driver, device, event, args)
      end
    end,
  },
}

return template

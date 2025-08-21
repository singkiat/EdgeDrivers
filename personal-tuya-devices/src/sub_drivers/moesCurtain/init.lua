-- Check if device has normal_moes_smart_curtain_v1 profile
if myutils.is_profile(device, "normal_moes_smart_curtain_v1") thencl_global_commands = require "st.zigbee.zcl.global_commands"
local utils = require "st.utils"
local commands = require "commands"
local myutils = require "utils"

local tuyaEF00_defaults = require "tuyaEF00_defaults"

-- Moes Curtain Sub-Driver
-- Handles devices that require multiple capabilities to map to single datapoint 9
local template = {
  NAME = "MoesCurtain",
  
  -- Device identification - handles Moes curtain devices
  can_handle = function(opts, driver, device, ...)
    local manufacturer = device:get_manufacturer()
    local model = device:get_model()
    
    -- -- Add specific fingerprints for Moes curtain devices
    -- local moes_patterns = {
    --   "_TZE200_meos", "_TZE200_cowvfni3", "_TZE200_5zbp6j0u",  -- Common Moes curtain manufacturers
    --   "_TZE200_gubdgai2", "_TZE200_wmcdj3aq", "_TZE200_nogaemzt"
    -- }
    
    -- -- Check if it's a Moes curtain device
    -- for _, pattern in ipairs(moes_patterns) do
    --   if manufacturer == pattern then
    --     myutils.log(device, "info", "🔹 Moes Curtain sub-driver handling device:", manufacturer, model)
    --     return true
    --   end
    -- end
    
    -- Check if device has normal_moes_smart_curtain_v1 profile
    if myutils.is_profile(device, "normal_moes_smart_curtain_v1") then
      myutils.log(device, "info", "🔹 Moes Curtain sub-driver handling via profile:", manufacturer, model)
      return true
    end
    
    -- Check if user has set moesCurtainDatapoints preference
    if device.preferences.moesCurtainDatapoints then
      myutils.log(device, "info", "🔹 Moes Curtain sub-driver handling via preference:", manufacturer, model)
      return true
    end
    
    return false
  end,
  
  supported_capabilities = {
    capabilities.windowShade,
    capabilities.windowShadeLevel, 
    capabilities.windowShadePreset,
    capabilities.refresh,
    capabilities["valleyboard16460.debug"],
  },
  
  -- Override capability handlers to use multi-command system
  capability_handlers = {
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 Moes Curtain Open Command")
        local datapoints = get_moes_datapoints(device)
        tuyaEF00_defaults.capability_handler(datapoints)(driver, device, command)
      end,
      
      [capabilities.windowShade.commands.close.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 Moes Curtain Close Command")
        local datapoints = get_moes_datapoints(device)
        tuyaEF00_defaults.capability_handler(datapoints)(driver, device, command)
      end,
      
      [capabilities.windowShade.commands.pause.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 Moes Curtain Pause Command")
        local datapoints = get_moes_datapoints(device)
        tuyaEF00_defaults.capability_handler(datapoints)(driver, device, command)
      end,
    },
    
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setLevel.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 Moes Curtain SetLevel Command:", command.args.level)
        local datapoints = get_moes_datapoints(device)
        tuyaEF00_defaults.capability_handler(datapoints)(driver, device, command)
      end,
    },
    
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 Moes Curtain Preset Command")
        local datapoints = get_moes_datapoints(device)
        tuyaEF00_defaults.capability_handler(datapoints)(driver, device, command)
      end,
    },
    
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 Moes Curtain Refresh Command")
        -- Send DataQuery to get current state
        device:send(zcl_clusters.TuyaEF00.commands.DataQuery(device))
      end,
    },
  },
  
  -- Handle Tuya EF00 responses
  zigbee_handlers = {
    global = {
      [zcl_clusters.TuyaEF00.ID] = {
        [zcl_global_commands.WRITE_ATTRIBUTE_ID] = function(driver, device, zb_rx)
          myutils.log(device, "debug", "🔹 Moes Curtain Global Handler")
          local datapoints = get_moes_datapoints(device)
          tuyaEF00_defaults.command_response_handler(datapoints)(driver, device, zb_rx)
        end,
      },
    },
    cluster = {
      [zcl_clusters.TuyaEF00.ID] = {
        [zcl_clusters.TuyaEF00.commands.DataResponse.ID] = function(driver, device, zb_rx)
          myutils.log(device, "debug", "🔹 Moes Curtain DataResponse")
          local datapoints = get_moes_datapoints(device)
          tuyaEF00_defaults.command_response_handler(datapoints)(driver, device, zb_rx)
        end,
        
        [zcl_clusters.TuyaEF00.commands.DataReport.ID] = function(driver, device, zb_rx)
          myutils.log(device, "debug", "🔹 Moes Curtain DataReport")
          local datapoints = get_moes_datapoints(device)
          tuyaEF00_defaults.command_response_handler(datapoints)(driver, device, zb_rx)
        end,
        
        [zcl_clusters.TuyaEF00.commands.StatusReport.ID] = function(driver, device, zb_rx)
          myutils.log(device, "debug", "🔹 Moes Curtain StatusReport")
          local datapoints = get_moes_datapoints(device)
          tuyaEF00_defaults.command_response_handler(datapoints)(driver, device, zb_rx)
        end,
        
        [zcl_clusters.TuyaEF00.commands.McuSyncTime.ID] = tuyaEF00_defaults.command_synctime_handler,
        [zcl_clusters.TuyaEF00.commands.GatewayStatus.ID] = tuyaEF00_defaults.command_gatestatus_handler,
      },
    },
  },
  
  -- Lifecycle handlers
  lifecycle_handlers = {
    added = function(driver, device, event, ...)
      myutils.log(device, "info", "🔹 Moes Curtain Device Added")
      
      -- Set up initial datapoints
      local datapoints = get_moes_datapoints(device)
      device:set_field("moes_datapoints", datapoints, {persist = true})
      
      -- Request initial status
      device.thread:call_with_delay(2, function()
        device:send(zcl_clusters.TuyaEF00.commands.DataQuery(device))
      end)
      
      -- Send initial GatewayData  
      device.thread:call_with_delay(5, function()
        device:send(zcl_clusters.TuyaEF00.commands.GatewayData(device))
      end)
    end,
    
    infoChanged = function(driver, device, event, args, ...)
      myutils.log(device, "info", "🔹 Moes Curtain Device Info Changed")
      
      -- Update profile if changed
      if args.old_st_store.preferences.profile ~= device.preferences.profile then
        myutils.update_profile(device, device.preferences.profile, args.old_st_store.preferences.profile)
      end
      
      -- Update datapoints if preferences changed
      if args.old_st_store.preferences.moesCurtainDatapoints ~= device.preferences.moesCurtainDatapoints then
        local datapoints = get_moes_datapoints(device)
        device:set_field("moes_datapoints", datapoints, {persist = true})
      end
    end,
  },
}

-- Helper function to get Moes curtain datapoints configuration
function get_moes_datapoints(device)
  local datapoints = {}
  
  -- Check for cached datapoints first
  local cached = device:get_field("moes_datapoints")
  if cached then
    return cached
  end
  
  -- Get datapoint ID from preferences (default to 9)
  local dpid = 9
  if device.preferences.moesCurtainDatapoints then
    for dp_str in device.preferences.moesCurtainDatapoints:gmatch("[^,]+") do
      dpid = tonumber(dp_str, 10) or 9
      break -- Use first datapoint ID
    end
  end
  
  -- Create multi-command handler for the datapoint
  datapoints[dpid] = commands.moesCurtainMultiCommand({
    group = dpid,
    rate = 100,
  })
  
  myutils.log(device, "info", "🔹 Moes Curtain using DP", dpid, "with multi-command handler")
  
  return datapoints
end

return template

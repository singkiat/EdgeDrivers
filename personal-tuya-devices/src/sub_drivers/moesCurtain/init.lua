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
  
  -- Device identification - handles Moes curtain devices
  can_handle = function(opts, driver, device, ...)
    local manufacturer = device:get_manufacturer()
    local model = device:get_model()
    

    
    -- Check if device has normal_moes_smart_curtain_v1 profile
    if myutils.is_profile(device, "normal_moes_smart_curtain_v1") then
      myutils.log(device, "info", "Moes Curtain sub-driver handling:", manufacturer, model)
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
  
  -- Hybrid approach: DP 1 handles windowShade via model, DP 9 handles setShadeLevel via override
  capability_handlers = {
    
    -- setShadeLevel override: Route to DP 9 via moesCurtainMultiCommand
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = function(driver, device, command)
        local level = command.args.shadeLevel or 50
        -- Get model configuration and find the moesCurtainMultiCommand datapoint
        local utils = require("utils")
        local model = utils.load_model_from_json(device:get_model(), device:get_manufacturer())
        
        if not model or not model.datapoints then
          myutils.log(device, "error", "No model datapoints found")
          return
        end
        
        -- Find the moesCurtainMultiCommand datapoint for windowShadeLevel
        local target_dpid = nil
        local target_group = 1
        for dp_id, dp_handler in pairs(model.datapoints) do
          if dp_handler and dp_handler.multi_command_mapping then
            for _, capability in ipairs(dp_handler.multi_command_mapping) do
              if capability == "windowShadeLevel" then
                target_dpid = dp_id
                target_group = dp_handler.group or 1
                break
              end
            end
            if target_dpid then break end
          end
        end
        
        if not target_dpid then
          myutils.log(device, "error", "windowShadeLevel datapoint not found in model")
          return
        end
        
        -- Send setShadeLevel command to the correct DP
        local commands = require("commands")
        local handler = commands.moesCurtainMultiCommand({group = target_group})
        
        local value = handler:command_to_value(command, device)
        if value then
          local zigbee_value = handler:to_zigbee(value, device)
          if zigbee_value then
            local clusters = require("st.zigbee.zcl.clusters")
            device:send(clusters.TuyaEF00.commands.DataRequest(device, {{target_dpid, zigbee_value}}))
          end
        end
      end,
    },
    
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = function(driver, device, command)
        send_model_command(device, command)
      end,
    },
    
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
      
      -- Request initial status
      device.thread:call_with_delay(2, function()
        device:send(zcl_clusters.TuyaEF00.commands.DataQuery(device))
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
        myutils.log(device, "info", "🔹 Moes Curtain datapoint preference updated")
        log_moes_configuration(device)
        -- No datapoint override - let model handle configuration
      end
    end,
  },
}

return template

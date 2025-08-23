local log = require "log"
local capabilities = require "st.capabilities"
local zcl_clusters = require "st.zigbee.zcl.clusters"  
local zcl_global_commands = require "st.zigbee.zcl.global_commands"
local utils = require "st.utils"
local commands = require "commands"
local myutils = require "utils"

local tuyaEF00_defaults = require "tuyaEF00_defaults"
local tuyaEF00_model_defaults = require "tuyaEF00_model_defaults"

-- Helper function to get model datapoints and send command  
local function send_model_command(device, command)
  myutils.log(device, "info", "🔹 STEP 1: Routing command to model datapoint handler")
  myutils.log(device, "info", "🔹 STEP 2: Device Model:", device:get_model(), "Manufacturer:", device:get_manufacturer())
  myutils.log(device, "info", "🔹 STEP 3: Command:", command.capability, command.command, "Component:", command.component)
  
  -- Get the driver instance from the device
  local driver = device:get_parent_device() and device:get_parent_device().driver or device.driver
  myutils.log(device, "info", "🔹 STEP 4: Got driver:", driver and "SUCCESS" or "FAILED")
  
  -- Try-catch the model handler call to see what's failing
  local success, error_msg = pcall(function()
    myutils.log(device, "info", "🔹 STEP 5: About to call tuyaEF00_model_defaults.capability_handler")
    tuyaEF00_model_defaults.capability_handler(driver, device, command)
    myutils.log(device, "info", "🔹 STEP 6: Model handler call completed")
  end)
  
  if not success then
    myutils.log(device, "error", "🔹 ERROR: Model handler failed:", error_msg)
  else
    myutils.log(device, "info", "🔹 STEP 7: Command sent to model - should see DataRequest if successful")
  end
end

-- Helper function for logging only - simplified to avoid any metatable issues
local function log_moes_configuration(device)
  myutils.log(device, "info", "🔹 Moes Curtain configured - using model datapoints")
end

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
  
  -- EXPERIMENT: DP 1 for windowShade commands works! Keep DP 1 for open/close/pause
  -- Restore setShadeLevel override for DP 9
  capability_handlers = {
    --[[ COMMENTED OUT: DP 1 experiment success - let model handle windowShade via DP 1
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 CAPABILITY HANDLER: Moes Curtain Open Command - routing to model DP 9")
        myutils.log(device, "info", "🔹 CAPABILITY HANDLER: About to call send_model_command for open")
        
        local success, error_msg = pcall(function()
          send_model_command(device, command)
        end)
        
        if not success then
          myutils.log(device, "error", "🔹 CAPABILITY HANDLER ERROR: send_model_command failed for open:", error_msg)
        else
          myutils.log(device, "info", "🔹 CAPABILITY HANDLER: send_model_command completed successfully for open")
        end
      end,
      [capabilities.windowShade.commands.close.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 CAPABILITY HANDLER: Moes Curtain Close Command - routing to model DP 9")
        myutils.log(device, "info", "🔹 CAPABILITY HANDLER: About to call send_model_command for close")
        
        local success, error_msg = pcall(function()
          send_model_command(device, command)
        end)
        
        if not success then
          myutils.log(device, "error", "🔹 CAPABILITY HANDLER ERROR: send_model_command failed for close:", error_msg)
        else
          myutils.log(device, "info", "🔹 CAPABILITY HANDLER: send_model_command completed successfully for close")
        end
      end,
      [capabilities.windowShade.commands.pause.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 Moes Curtain Pause Command - routing to model DP 9")
        -- Route command to model's datapoint processing with proper context
        send_model_command(device, command)
      end,
    },
    --]] -- End of windowShade comment block
    
    -- RESTORE: setShadeLevel override for DP 9 (DP 1 experiment successful for windowShade)
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = function(driver, device, command)
        local level = command.args.shadeLevel or 50
        myutils.log(device, "info", "🔹 DIRECT OVERRIDE: Moes SetLevel Command:", level, "% - sending to DP 9")
        
        -- Get model configuration to find the moesCurtainMultiCommand datapoint
        local utils = require("utils")
        local model = utils.load_model_from_json(device:get_model(), device:get_manufacturer())
        
        -- DEBUG: Log model loading result IMMEDIATELY
        myutils.log(device, "info", "🔹 DEBUG: Model load result:", model and "SUCCESS" or "FAILED")
        if model then
          myutils.log(device, "info", "🔹 DEBUG: Model has datapoints:", model.datapoints and "YES" or "NO")
          if model.datapoints then
            myutils.log(device, "info", "🔹 DEBUG: Datapoints type:", type(model.datapoints))
            myutils.log(device, "info", "🔹 DEBUG: Datapoints count:", #model.datapoints)
          end
        end
        
        if not model or not model.datapoints then
          myutils.log(device, "error", "🔹 DIRECT OVERRIDE: No model datapoints found")
          return
        end
        
        -- DEBUG: Log what's actually in the model (datapoints is a HASH TABLE by DP ID!)
        myutils.log(device, "info", "🔹 DEBUG: Model loaded successfully")
        local dp_count = 0
        for dp_id, dp_handler in pairs(model.datapoints) do
          dp_count = dp_count + 1
          myutils.log(device, "info", "🔹 DEBUG: DP", dp_id, "- handler type:", type(dp_handler))
        end
        myutils.log(device, "info", "🔹 DEBUG: Model datapoints count (pairs):", dp_count)
        
        -- Find the moesCurtainMultiCommand datapoint (datapoints is a HASH TABLE by DP ID!)
        local target_dpid = nil
        local target_group = 1
        for dp_id, dp_handler in pairs(model.datapoints) do
          -- Check if this handler has multi_command_mapping that includes windowShadeLevel
          if dp_handler and dp_handler.multi_command_mapping then
            for _, capability in ipairs(dp_handler.multi_command_mapping) do
              if capability == "windowShadeLevel" then
                target_dpid = dp_id
                target_group = dp_handler.group or 1
                myutils.log(device, "info", "🔹 DIRECT OVERRIDE: Found windowShadeLevel handler at DP", target_dpid, "group", target_group)
                break
              end
            end
            if target_dpid then break end
          end
        end
        
        if not target_dpid then
          myutils.log(device, "error", "🔹 DIRECT OVERRIDE: moesCurtainMultiCommand datapoint not found in model")
          return
        end
        
        -- Get the moesCurtainMultiCommand handler with correct group
        local commands = require("commands")
        local handler = commands.moesCurtainMultiCommand({group = target_group})
        
        -- Force the command to use the correct DP by calling to_zigbee directly
        local value = handler:command_to_value(command, device)
        if value then
          myutils.log(device, "info", "🔹 DIRECT OVERRIDE: Generated value for DP", target_dpid, ":", value)
          local zigbee_value = handler:to_zigbee(value, device)
          if zigbee_value then
            myutils.log(device, "info", "🔹 DIRECT OVERRIDE: Sending setShadeLevel to DP", target_dpid, "with zigbee value:", zigbee_value)
            local clusters = require("st.zigbee.zcl.clusters")
            device:send(clusters.TuyaEF00.commands.DataRequest(device, {{target_dpid, zigbee_value}}))
          else
            myutils.log(device, "error", "🔹 DIRECT OVERRIDE: Failed to convert value to zigbee format")
          end
        else
          myutils.log(device, "error", "🔹 DIRECT OVERRIDE: Failed to generate setShadeLevel value")
        end
      end,
    },
    
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔹 CAPABILITY HANDLER: Moes Curtain Preset Command - routing to model DP 9")
        myutils.log(device, "info", "🔹 CAPABILITY HANDLER: About to call send_model_command")
        
        -- Try-catch the function call to see what's failing
        local success, error_msg = pcall(function()
          send_model_command(device, command)
        end)
        
        if not success then
          myutils.log(device, "error", "🔹 CAPABILITY HANDLER ERROR: send_model_command failed:", error_msg)
        else
          myutils.log(device, "info", "🔹 CAPABILITY HANDLER: send_model_command completed successfully")
        end
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
  
  -- Note: Zigbee handlers are intentionally NOT overridden here to preserve
  -- default signal strength, battery, and other basic handlers.
  -- TuyaEF00 message handling is done by the genericEF00 sub-driver that follows.
  
  -- Lifecycle handlers
  lifecycle_handlers = {
    added = function(driver, device, event, ...)
      myutils.log(device, "info", "🔹 Moes Curtain Device Added")
      log_moes_configuration(device)
      
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
        myutils.log(device, "info", "🔹 Moes Curtain datapoint preference updated")
        log_moes_configuration(device)
        -- No datapoint override - let model handle configuration
      end
    end,
  },
}

return template

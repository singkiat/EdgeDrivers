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
    
    -- Check if device has normal-moes-smart-curtain-v1 profile
    if myutils.is_profile(device, "normal-moes-smart-curtain-v1") then
      myutils.log(device, "info", "Moes Curtain sub-driver handling:", manufacturer, model)
      return true
    end
    
    -- Check if user has set moesCurtainDatapoints preference
    if device.preferences.moesCurtainDatapoints then
      myutils.log(device, "info", "Moes Curtain sub-driver handling via preference:", manufacturer, model)
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
    
    -- windowShade commands: open/close/pause - send directly to DP 1
    [capabilities.windowShade.ID] = {
      [capabilities.windowShade.commands.open.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔄 Moes windowShade.open command received - sending to DP1")
        
        -- Send directly to DP 1 using windowShade handler
        local commands = require("commands")
        local handler = commands.windowShade({group = 1})
        
        local dp_data = handler:command_handler(1, command, device)
        if dp_data and dp_data[1] and dp_data[2] then
          local clusters = require("st.zigbee.zcl.clusters")
          device:send(clusters.TuyaEF00.commands.DataRequest(device, {{dp_data[1], dp_data[2]}}))
          myutils.log(device, "info", "✅ windowShade.open → DP1 sent successfully")
        else
          myutils.log(device, "error", "❌ Failed to process windowShade.open command")
        end
      end,
      [capabilities.windowShade.commands.close.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🔄 Moes windowShade.close command received - sending to DP1")
        
        -- Send directly to DP 1 using windowShade handler  
        local commands = require("commands")
        local handler = commands.windowShade({group = 1})
        
        local dp_data = handler:command_handler(1, command, device)
        if dp_data and dp_data[1] and dp_data[2] then
          local clusters = require("st.zigbee.zcl.clusters")
          device:send(clusters.TuyaEF00.commands.DataRequest(device, {{dp_data[1], dp_data[2]}}))
          myutils.log(device, "info", "✅ windowShade.close → DP1 sent successfully")
        else
          myutils.log(device, "error", "❌ Failed to process windowShade.close command")
        end
      end,
      [capabilities.windowShade.commands.pause.NAME] = function(driver, device, command)
        myutils.log(device, "info", "⏸️ Moes windowShade.pause command received - stopping timer and setting immediate state")
        
        -- Cancel any existing pause timer immediately
        local existing_timer = device:get_field("state_clearing_timer")
        if existing_timer then
          device.thread:cancel_timer(existing_timer)
          device:set_field("state_clearing_timer", nil)
          myutils.log(device, "info", "⏸️ Pause timer canceled")
        end
        
        -- Clear movement state
        device:set_field("movement_state", nil)
        
        -- -- Get current actual position and set final state immediately
        -- local current_level = device:get_latest_state("main", "windowShadeLevel", "shadeLevel")
        -- if current_level ~= nil then
        --   -- Get reverse preference to determine correct final state
        --   local pref = device.preferences
        --   local final_state
          
        --   if current_level == 0 then
        --     final_state = pref.reverse and "open" or "closed"
        --   elseif current_level == 100 then
        --     final_state = pref.reverse and "closed" or "open"
        --   else
        --     final_state = "partially open"
        --   end
          
        --   myutils.log(device, "info", "⏸️ Pause - immediate final state: " .. current_level .. "% = " .. final_state)
        --   device:emit_event(capabilities.windowShade.windowShade(final_state))
        -- end
        
        -- Send pause command to device
        local commands = require("commands")
        local handler = commands.windowShade({group = 1})
        
        local dp_data = handler:command_handler(1, command, device)
        if dp_data and dp_data[1] and dp_data[2] then
          local clusters = require("st.zigbee.zcl.clusters")
          device:send(clusters.TuyaEF00.commands.DataRequest(device, {{dp_data[1], dp_data[2]}}))
          myutils.log(device, "info", "✅ windowShade.pause → DP1 sent successfully")
        else
          myutils.log(device, "error", "❌ Failed to process windowShade.pause command")
        end
      end,
    },
    
    [capabilities.windowShadeLevel.ID] = {
      [capabilities.windowShadeLevel.commands.setShadeLevel.NAME] = function(driver, device, command)
        local target_level = command.args.shadeLevel or 50
        myutils.log(device, "info", "📏 Moes setShadeLevel command received - target: " .. target_level .. "%")
        
        -- Get current shade level and emit transitional state
        local current_level = device:get_latest_state("main", "windowShadeLevel", "shadeLevel") or 0
        local pref = device.preferences
        
        -- Account for reverse preference when determining opening/closing direction
        local is_opening, is_closing
        if pref.reverse then
          -- When reverse=true: 0%=open, 100%=closed
          -- So lower target = opening, higher target = closing
          is_opening = target_level < current_level
          is_closing = target_level > current_level
        else
          -- When reverse=false: 0%=closed, 100%=open  
          -- So higher target = opening, lower target = closing
          is_opening = target_level > current_level
          is_closing = target_level < current_level
        end
        
        if is_opening then
          myutils.log(device, "info", "📈 SetLevel moving from " .. current_level .. "% to " .. target_level .. "% - emitting 'opening' (reverse=" .. tostring(pref.reverse) .. ")")
          device:emit_event(capabilities.windowShade.windowShade("opening"))
          device:set_field("movement_state", "opening")
        elseif is_closing then
          myutils.log(device, "info", "📉 SetLevel moving from " .. current_level .. "% to " .. target_level .. "% - emitting 'closing' (reverse=" .. tostring(pref.reverse) .. ")")
          device:emit_event(capabilities.windowShade.windowShade("closing"))
          device:set_field("movement_state", "closing")
        else
          myutils.log(device, "info", "⏸️ SetLevel at same position " .. target_level .. "% - no movement needed")
        end
        
        -- Start 30-second timer like open/close commands
        if is_opening or is_closing then
          local commands = require("commands")
          local windowShade_handler = commands.windowShade({group = 1})
          windowShade_handler:schedule_windowshade_pause(device, 30)
        end
        
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
            myutils.log(device, "info", "✅ setShadeLevel → DP" .. target_dpid .. " sent successfully")
          end
        end
      end,
    },
    
    [capabilities.windowShadePreset.ID] = {
      [capabilities.windowShadePreset.commands.presetPosition.NAME] = function(driver, device, command)
        myutils.log(device, "info", "🎯 Moes windowShadePreset.presetPosition command received")
        
        -- Get current shade level and target preset position
        local current_level = device:get_latest_state("main", "windowShadeLevel", "shadeLevel") or 0
        local target_position = command.args.presetPosition or 50
        local pref = device.preferences
        
        -- Account for reverse preference when determining opening/closing direction
        local is_opening, is_closing
        if pref.reverse then
          -- When reverse=true: 0%=open, 100%=closed
          -- So lower target = opening, higher target = closing
          is_opening = target_position < current_level
          is_closing = target_position > current_level
        else
          -- When reverse=false: 0%=closed, 100%=open  
          -- So higher target = opening, lower target = closing
          is_opening = target_position > current_level
          is_closing = target_position < current_level
        end
        
        -- Emit transitional state based on direction of movement AND set movement_state
        if is_opening then
          myutils.log(device, "info", "📈 Preset moving from " .. current_level .. "% to " .. target_position .. "% - emitting 'opening' (reverse=" .. tostring(pref.reverse) .. ")")
          device:emit_event(capabilities.windowShade.windowShade("opening"))
          device:set_field("movement_state", "opening")
        elseif is_closing then
          myutils.log(device, "info", "📉 Preset moving from " .. current_level .. "% to " .. target_position .. "% - emitting 'closing' (reverse=" .. tostring(pref.reverse) .. ")")
          device:emit_event(capabilities.windowShade.windowShade("closing"))
          device:set_field("movement_state", "closing")
        else
          myutils.log(device, "info", "⏸️ Preset at same position " .. target_position .. "% - no movement needed")
        end
        
        -- Start 30-second timer like open/close commands
        if is_opening or is_closing then
          local commands = require("commands")
          local windowShade_handler = commands.windowShade({group = 1})
          windowShade_handler:schedule_windowshade_pause(device, 30)
        end
        
        -- Send the preset command - let DP 8 position reports handle final state
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
      
      -- ⭐ CRITICAL: Load model datapoints to enable proper DP 8 processing
      myutils.log(device, "info", "🔧 Loading Moes Curtain model datapoints...")
      tuyaEF00_model_defaults.lifecycle_handlers.added(driver, device, event)
      
      -- Request initial status
      device.thread:call_with_delay(2, function()
        device:send(zcl_clusters.TuyaEF00.commands.DataQuery(device))
      end)
    end,
    
    init = function(driver, device, event, ...)
      myutils.log(device, "info", "🔧 Initializing existing Moes Curtain device with model datapoints...")
      -- Load model datapoints for existing devices
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

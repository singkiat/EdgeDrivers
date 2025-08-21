# Moes Smart Curtain Multi-Command Setup Guide

This guide shows how to configure your Moes curtain to use the new multi-command mapping system where multiple SmartThings capabilities map to a single Tuya datapoint (DP 9).

## What Was Changed

### 1. Enhanced Command Matching (`tuyaEF00_defaults.lua`)
- Added `command_matches_datapoint()` function
- Supports `multi_command_mapping` property
- Multiple capabilities can now target the same datapoint

### 2. New Multi-Command Handler (`commands.lua`)
- Created `moesCurtainMultiCommand` handler
- Maps multiple capabilities to single DP 9:
  - **windowShade** → open (0%), close (100%), pause (current%)
  - **windowShadeLevel** → setLevel (custom%)
  - **windowShadePreset** → presetPosition (preset%)

## How to Use

### Option 1: Device Model Configuration

Create a model file for your Moes curtain:

```lua
-- personal-tuya-devices/models/TS0601/_TZE200_moesSCurtain.lua
return {
  datapoints = {
    {
      id = 9,
      command = "moesCurtainMultiCommand",
      base = {
        group = 9
      }
    }
  },
  profiles = {
    "normal_moes_smart_curtain_v1"
  }
}
```

### Option 2: Device Preferences Configuration

Add to your device preferences:
- **windowShadeDatapoints**: `9`
- **windowShadeLevDatapoints**: `9` 
- **windowShadePreDatapoints**: `9`

But use the multi-command handler:
```lua
local datapoints = {
  [9] = commands.moesCurtainMultiCommand({group = 9})
}
```

### Option 3: Profile Configuration

Create a profile with multi-command support:

```yaml
# personal-tuya-devices/profiles/normal-moes-smart-curtain-v2.yaml
name: "normal-moes-smart-curtain-v2"
components:
- id: main
  capabilities:
  - id: windowShade
    version: 1
  - id: windowShadeLevel
    version: 1
  - id: windowShadePreset
    version: 1
  - id: refresh
    version: 1
categories:
- name: Window Shade
preferences:
- name: "windowShadeDatapoints"
  title: "Window Shade Datapoints"
  description: "Comma-separated datapoint IDs for window shade control"
  required: false
  preferenceType: string
  definition:
    stringType: text
    default: "9"
```

## Command Flow Examples

### SmartThings App Commands → DP 9 Values:

| SmartThings Command | Capability | Value Sent to DP 9 | Description |
|-------------------|------------|-------------------|-------------|
| **Open** | windowShade | `0` | Fully open curtain |
| **Close** | windowShade | `100` | Fully close curtain |
| **Pause/Stop** | windowShade | Current position | Stop at current position |
| **Set Level 75%** | windowShadeLevel | `75` | Set to 75% closed |
| **Preset Position** | windowShadePreset | Preset value | Go to saved preset |

### Device Response → SmartThings Events:

When DP 9 sends back a value (e.g., `42`):
1. **windowShadeLevel** event: `shadeLevel: 42`
2. **windowShade** event: `windowShade: "partially open"`

## Key Features

### ✅ **Multiple Commands, Single Datapoint**
- All curtain commands map to DP 9
- Different values sent based on command type
- Eliminates need for multiple datapoint handlers

### ✅ **Smart State Management**
- Automatically emits both `windowShade` and `windowShadeLevel` events
- Determines shade state based on level value:
  - `0%` = "open"
  - `100%` = "closed"
  - `1-99%` = "partially open"

### ✅ **Pause/Stop Intelligence** 
- Pause command gets current position from device state
- Sends current position to stop movement
- Falls back to 50% if no current state available

### ✅ **Preset Support**
- Uses device preferences for preset position
- Configurable via device settings
- Default 50% if not configured

## Device Configuration Example

```lua
-- In your device's datapoint configuration:
local datapoints = {
  [9] = commands.moesCurtainMultiCommand({
    group = 9,
    rate = 100, -- Optional: scaling factor
  })
}

-- Register capabilities that this datapoint handles:
local supported_capabilities = {
  capabilities.windowShade,
  capabilities.windowShadeLevel,
  capabilities.windowShadePreset,
  capabilities.refresh,
}
```

## Troubleshooting

### Debug Logs
The handler provides detailed logging:
```
🔹 Moes Open Command - sending 0% to DP 9
🔹 Moes Close Command - sending 100% to DP 9
🔹 Moes SetLevel Command - sending 75% to DP 9
🔹 Moes Preset Command - sending 50% to DP 9
```

### Common Issues

1. **Multiple Events**: If you see duplicate events, make sure you're not also using the standard `windowShade` and `windowShadeLevel` handlers for the same datapoint.

2. **No Response**: Ensure your Moes curtain actually uses DP 9. Check device logs or use the debug capability to see incoming datapoints.

3. **Wrong Direction**: Some curtains have reversed logic. The handler doesn't currently support reverse logic - this would need to be added if needed.

## Extending for Other Multi-Command Devices

This pattern can be used for any device that requires multiple capabilities to map to a single datapoint:

```lua
defaults.yourMultiCommandDevice = {
  capability = "primaryCapability",
  multi_command_mapping = {
    "capability1",
    "capability2", 
    "capability3"
  },
  command_handler = function (self, dpid, command, device, datapoints)
    if command.capability == "capability1" then
      -- Handle capability1 commands
    elseif command.capability == "capability2" then
      -- Handle capability2 commands  
    end
    -- Return { dpid, tuya_value }
  end,
  create_event = function (self, value, device, force_child, datapoints)
    -- Emit appropriate events based on incoming value
  end,
}
```

The multi-command mapping system is now ready to handle complex devices like the Moes curtain that require multiple SmartThings capabilities to control a single Tuya datapoint!

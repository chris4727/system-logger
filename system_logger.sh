#/bin/bash
# ====================================================
# Author: AntoninPvr
# Date: 2024-12-04
# License: GPLv3
# Purpose: This script was originally designed to log battery information for a Razer Blade 15 Advanced (2020).
# It supports flexible logging with an optional terminal interface showing the current log size and latest data.
# chris4727 added ability to log CPU load

# Default values
INTERVAL=60
BATTERY_PATH=$(find /sys/class/power_supply/ -name "BAT*" | head -n 1)
MAX_TIME=0  # 0 indicates indefinite runtime
DISPLAY_INTERFACE=1  # 1 to display interface, 0 to disable

# Initialize variables

# To store the current interface output and update it at each iteration
interface_output=""

# Function to display help
show_help() {
    echo "Usage: $0 [-o OUTPUT_FILE] [-i INTERVAL] [-b BATTERY_PATH] [-t MAX_TIME] [--no-interface]"
    echo
    echo "  -i, --interval     Specify the logging interval in seconds (default: 60)"
    echo "  -o, --output       Specify the output file for logging (default: disabled)"
    echo "  -b, --battery      Specify the battery path (default: autodetected)"
    echo "  -t, --time         Specify the maximum runtime in seconds (default: indefinite)"
    echo "      --no-interface Disable the terminal interface (default: enabled)"
    echo "  -h, --help         Display this help message"
    exit 0
}

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            LOG_FILE="$2"
            shift 2
            ;;
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -b|--battery)
            BATTERY_PATH="$2"
            shift 2
            ;;
        -t|--time)
            MAX_TIME="$2"
            shift 2
            ;;
        --no-interface)
            DISPLAY_INTERFACE=0
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            ;;
    esac
done

# Ensure the battery path is valid
if [ ! -d "$BATTERY_PATH" ]; then
    echo "Error: Battery path '$BATTERY_PATH' not found!"
    exit 1
fi

# Skip reporting if LOG_FILE is empty or unset
if [ -z "$LOG_FILE" ]; then
    REPORT_ENABLED=0
else
    REPORT_ENABLED=1
    # Ensure the log file exists and has a header if reporting is enabled
    if [ ! -f "$LOG_FILE" ]; then
        echo "Timestamp,Current (µA),Voltage (µV),Capacity (%),Charge (µAh),Temperature (°C),Charging" > "$LOG_FILE"
    fi
fi

# Function to fetch values and append to log file
log_battery_status() {
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    CURRENT=$(cat "$BATTERY_PATH/current_now" 2>/dev/null || echo "N/A")
    VOLTAGE=$(cat "$BATTERY_PATH/voltage_now" 2>/dev/null || echo "N/A")
    CAPACITY=$(cat "$BATTERY_PATH/capacity" 2>/dev/null || echo "N/A")
    CHARGE=$(cat "$BATTERY_PATH/charge_now" 2>/dev/null || echo "N/A")
    STATUS=$(cat "$BATTERY_PATH/status" 2>/dev/null || echo "Unknown")

    # Fetch temperature using acpi -t
    if command -v acpi &>/dev/null; then
        TEMPERATURE=$(acpi -t | awk '{print $4}')
    else
        TEMPERATURE="N/A"
    fi

    # Determine charging status
    CHARGING=0
    if [ "$STATUS" == "Charging" ]; then
        CHARGING=1
    elif [ "$STATUS" == "Discharging" ]; then
        CHARGING=-1
    fi

    # Append data to log file if reporting is enabled
    if (( REPORT_ENABLED )); then
        echo "$TIMESTAMP,$CURRENT,$VOLTAGE,$CAPACITY,$CHARGE,$TEMPERATURE,$CHARGING" >> "$LOG_FILE"
    fi
}

show_terminal_interface() {
    # Accumulate all interface information into a variable
    interface_output="====================== BATTERY LOGGER =====================\n"
    interface_output+="Interval: $INTERVAL seconds\n"
    interface_output+="Battery Path: $BATTERY_PATH\n"
    interface_output+="Start Time: $(date -d @$START_TIME)\n"

    # Only include log file size if REPORT_ENABLED is 1 and LOG_FILE exists
    if [ "$REPORT_ENABLED" -eq 1 ] && [ -f "$LOG_FILE" ]; then
        interface_output+="===========================================================\n"
        interface_output+="Log File: $LOG_FILE\n"
        interface_output+="Current Log File Size: $(du -h "$LOG_FILE" | cut -f1)\n"
    fi

    interface_output+="\n"
    interface_output+="=================== Current Battery Data ==================\n"

    # Define column widths for the table
    metric_width=14
    value_width=18
    raw_value_width=18

    # Header row
    interface_output+="| $(printf "%-${metric_width}s" "Metric") | $(printf "%-${value_width}s" "Value (converted)") | $(printf "%-${raw_value_width}s" "Raw Value")|\n"
    interface_output+="|----------------|--------------------|-------------------|\n"

    # Add rows for current, charge, and voltage with proper padding
    interface_output+="| $(printf "%-${metric_width}s" "current_now") | $(printf "%-${value_width}s" "$(echo "scale=3; $CURRENT / 1000" | bc) mA") | $(printf "%-${raw_value_width}s" "$CURRENT")|\n"
    interface_output+="| $(printf "%-${metric_width}s" "charge_now") | $(printf "%-${value_width}s" "$(echo "scale=3; $CHARGE / 1000" | bc) mAh") | $(printf "%-${raw_value_width}s" "$CHARGE")|\n"
    interface_output+="| $(printf "%-${metric_width}s" "voltage_now") | $(printf "%-${value_width}s" "$(echo "scale=3; $VOLTAGE / 1000000" | bc) V") | $(printf "%-${raw_value_width}s" "$VOLTAGE")|\n"
    interface_output+="| $(printf "%-${metric_width}s" "capacity") | $(printf "%-${value_width}s" "$CAPACITY %")                     |\n"

    interface_output+="===========================================================\n"
    interface_output+="temperature      : $TEMPERATURE °C\n"
    interface_output+="charging status  : $STATUS\n"
    interface_output+="===========================================================\n"
}





# Function to show progress bar for max time
show_progress_bar() {
    local elapsed=$1
    local max_time=$2
    local remaining=$((max_time - elapsed))
    local remaining_hours=$((remaining / 3600))
    local remaining_minutes=$(( (remaining % 3600) / 60 ))
    local remaining_seconds=$((remaining % 60))
    local bar_length=33
    local filled_length=$(( (elapsed * bar_length) / max_time ))
    local empty_length=$(( bar_length - filled_length ))

    # Generate progress bar
    bar=$(printf "%${filled_length}s" | tr ' ' '#')
    empty=$(printf "%${empty_length}s")

    interface_output+="\rProgress: |${bar}${empty}| ETA: $(printf "%02d:%02d:%02d" "$remaining_hours" "$remaining_minutes" "$remaining_seconds")"
}

# Track runtime
START_TIME=$(date +%s)

# Periodic logging
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

    # Exit if the maximum runtime is reached (if MAX_TIME > 0)
    if (( MAX_TIME > 0 && ELAPSED_TIME >= MAX_TIME)); then
        if (( DISPLAY_INTERFACE )); then
            echo "Reached maximum runtime of $MAX_TIME seconds. Exiting."
        fi
        break
    fi

    # show battery status
    log_battery_status

    # Display the terminal interface if enabled
    if (( DISPLAY_INTERFACE )); then
        clear  # Only clear once per iteration
        show_terminal_interface

        # Show progress bar if max time is specified
        if (( MAX_TIME > 0 )); then
            show_progress_bar "$ELAPSED_TIME" "$MAX_TIME"
        else
            # Show message if no time limit is set
            interface_output+="\rRunning indefinitely... Press CTRL+C to stop.\n"
        fi
        echo -e "$interface_output"
    fi

    # Sleep for the specified interval
    sleep "$INTERVAL"
done

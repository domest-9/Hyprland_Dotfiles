#!/bin/bash

# WiFi Manager Script for Hyprland with Rofi
# Dependencies: rofi, networkmanager, notify-send

# Function to send notifications
notify() {
    notify-send "WiFi Manager" "$1" -t 3000
}

# Function to get WiFi status
get_wifi_status() {
    if nmcli radio wifi | grep -q "enabled"; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

# Function to toggle WiFi
toggle_wifi() {
    if [ "$(get_wifi_status)" = "enabled" ]; then
        nmcli radio wifi off
        notify "WiFi disabled"
    else
        nmcli radio wifi on
        notify "WiFi enabled"
    fi
}

# Function to scan and list available networks
list_networks() {
    nmcli device wifi rescan 2>/dev/null
    sleep 2
    nmcli -f SSID,SECURITY,SIGNAL device wifi list | tail -n +2 | \
    awk '{
        ssid = $1
        security = $2
        signal = $NF
        if (ssid != "--") {
            # Add icons and format nicely
            if (security == "--") {
                icon = "🔓"
                sec_text = "Open"
            } else {
                icon = "🔒"
                sec_text = security
            }
            
            # Signal strength icons
            if (signal >= 75) signal_icon = "▰▰▰▰"
            else if (signal >= 50) signal_icon = "▰▰▰▱"
            else if (signal >= 25) signal_icon = "▰▰▱▱"
            else signal_icon = "▰▱▱▱"
            
            printf "%s %s  %s  %s %s%%\n", icon, ssid, signal_icon, sec_text, signal
        }
    }' | sort -k6 -nr
}

# Function to get saved connections
get_saved_connections() {
    nmcli -f NAME,TYPE connection show | grep wifi | awk '{print $1}'
}

# Function to connect to a network
connect_network() {
    local ssid="$1"
    local security="$2"
    
    # Check if it's a saved connection
    if nmcli connection show "$ssid" &>/dev/null; then
        if nmcli connection up "$ssid" &>/dev/null; then
            notify "Connected to $ssid"
        else
            notify "Failed to connect to $ssid"
        fi
        return
    fi
    
    # New network - check if it needs password
    if [[ "$security" == *"WPA"* ]] || [[ "$security" == *"WEP"* ]]; then
        password=$(echo "" | rofi -dmenu -p "🔑 Password for $ssid" -password -theme ~/.config/rofi/Wifi-menu/wifi.rasi)
        if [ -n "$password" ]; then
            if nmcli device wifi connect "$ssid" password "$password" &>/dev/null; then
                notify "Connected to $ssid"
            else
                notify "Failed to connect to $ssid"
            fi
        else
            notify "Connection cancelled"
        fi
    else
        # Open network
        if nmcli device wifi connect "$ssid" &>/dev/null; then
            notify "Connected to $ssid"
        else
            notify "Failed to connect to $ssid"
        fi
    fi
}

# Function to forget a network
forget_network() {
    local connections=$(get_saved_connections)
    if [ -z "$connections" ]; then
        notify "No saved connections found"
        return
    fi
    
    local selected=$(echo "$connections" | rofi -dmenu -p "🗑️ Forget Connection" -theme ~/.config/rofi/Wifi-menu/wifi.rasi)
    if [ -n "$selected" ]; then
        if nmcli connection delete "$selected" &>/dev/null; then
            notify "Forgot connection: $selected"
        else
            notify "Failed to forget connection: $selected"
        fi
    fi
}

# Function to show current connection info
show_connection_info() {
    local current=$(nmcli -t -f NAME connection show --active | grep -v lo | head -1)
    if [ -n "$current" ]; then
        local info=$(nmcli connection show "$current" | grep -E "connection.id|802-11-wireless.ssid|IP4.ADDRESS|IP4.GATEWAY")
        echo "$info" | rofi -dmenu -p "ℹ️ Connection Info" -theme ~/.config/rofi/Wifi-menu/wifi.rasi -no-custom
    else
        notify "No active connection"
    fi
}

# Main menu function
show_main_menu() {
    local wifi_status=$(get_wifi_status)
    local current_conn=$(nmcli -t -f NAME connection show --active 2>/dev/null | grep -v lo | head -1)
    
    local status_icon="📶"
    local status_text="enabled"
    if [ "$wifi_status" = "disabled" ]; then
        status_icon="📵"
        status_text="disabled"
    fi
    
    local menu_items="🔄 Refresh & Scan Networks
📶 Available Networks
💾 Saved Connections
🗑️ Forget Network
ℹ️ Connection Info
$status_icon Toggle WiFi ($status_text)"
    
    if [ -n "$current_conn" ]; then
        menu_items="🔗 Connected: $current_conn
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$menu_items"
    else
        menu_items="📵 Not Connected
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$menu_items"
    fi
    
    echo "$menu_items"
}

# Main script logic
main() {
    # Check if NetworkManager is running
    if ! systemctl is-active --quiet NetworkManager; then
        notify "NetworkManager is not running"
        exit 1
    fi
    
    while true; do
        choice=$(show_main_menu | rofi -dmenu -p "📶 WiFi Manager" -theme ~/.config/rofi/Wifi-menu/wifi.rasi -i)
        
        case "$choice" in
            *"Refresh"*|*"Available Networks")
                if [ "$(get_wifi_status)" = "disabled" ]; then
                    notify "WiFi is disabled. Enable it first."
                    continue
                fi
                
                notify "Scanning for networks..."
                networks=$(list_networks)
                if [ -n "$networks" ]; then
                    selected=$(echo "$networks" | rofi -dmenu -p "📡 Select Network" -theme ~/.config/rofi/Wifi-menu/wifi.rasi)
                    if [ -n "$selected" ]; then
                        # Extract SSID (remove icon and format)
                        ssid=$(echo "$selected" | awk '{print $2}')
                        security=$(echo "$selected" | awk '{print $4}')
                        connect_network "$ssid" "$security"
                    fi
                else
                    notify "No networks found"
                fi
                ;;
            *"Saved Connections")
                connections=$(get_saved_connections)
                if [ -n "$connections" ]; then
                    selected=$(echo "$connections" | rofi -dmenu -p "💾 Saved Networks" -theme ~/.config/rofi/Wifi-menu/wifi.rasi)
                    if [ -n "$selected" ]; then
                        connect_network "$selected" ""
                    fi
                else
                    notify "No saved connections"
                fi
                ;;
            *"Forget Network")
                forget_network
                ;;
            *"Connection Info")
                show_connection_info
                ;;
            *"Toggle WiFi"*)
                toggle_wifi
                ;;
            *"Connected:"*|*"Not Connected"*|"━"*)
                # Do nothing for status lines
                ;;
            "")
                # User pressed escape or cancelled
                break
                ;;
            *)
                break
                ;;
        esac
    done
}

# Run the main function
main
            notify "Failed to connect to $ssid"
        fi
    fi
}

# Function to forget a network
forget_network() {
    local connections=$(get_saved_connections)
    if [ -z "$connections" ]; then
        notify "No saved connections found"
        return
    fi
    
    local selected=$(echo "$connections" | rofi -dmenu -p "🗑️ Forget Connection" -theme-str "$ROFI_CONFIG")
    if [ -n "$selected" ]; then
        if nmcli connection delete "$selected" &>/dev/null; then
            notify "Forgot connection: $selected"
        else
            notify "Failed to forget connection: $selected"
        fi
    fi
}

# Function to show current connection info
show_connection_info() {
    local current=$(nmcli -t -f NAME connection show --active | grep -v lo | head -1)
    if [ -n "$current" ]; then
        local info=$(nmcli connection show "$current" | grep -E "connection.id|802-11-wireless.ssid|IP4.ADDRESS|IP4.GATEWAY")
        echo "$info" | rofi -dmenu -p "ℹ️ Connection Info" -theme-str "$ROFI_CONFIG" -no-custom
    else
        notify "No active connection"
    fi
}

# Main menu function
show_main_menu() {
    local wifi_status=$(get_wifi_status)
    local current_conn=$(nmcli -t -f NAME connection show --active 2>/dev/null | grep -v lo | head -1)
    
    local status_icon="📶"
    local status_text="enabled"
    if [ "$wifi_status" = "disabled" ]; then
        status_icon="📵"
        status_text="disabled"
    fi
    
    local menu_items="🔄 Refresh & Scan Networks
📶 Available Networks
💾 Saved Connections
🗑️ Forget Network
ℹ️ Connection Info
$status_icon Toggle WiFi ($status_text)"
    
    if [ -n "$current_conn" ]; then
        menu_items="🔗 Connected: $current_conn
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$menu_items"
    else
        menu_items="📵 Not Connected
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$menu_items"
    fi
    
    echo "$menu_items"
}

# Main script logic
main() {
    # Check if NetworkManager is running
    if ! systemctl is-active --quiet NetworkManager; then
        notify "NetworkManager is not running"
        exit 1
    fi
    
    while true; do
        choice=$(show_main_menu | rofi -dmenu -p "📶 WiFi Manager" -theme-str "$ROFI_CONFIG" -i)
        
        case "$choice" in
            *"Refresh"*|*"Available Networks")
                if [ "$(get_wifi_status)" = "disabled" ]; then
                    notify "WiFi is disabled. Enable it first."
                    continue
                fi
                
                notify "Scanning for networks..."
                networks=$(list_networks)
                if [ -n "$networks" ]; then
                    selected=$(echo "$networks" | rofi -dmenu -p "📡 Select Network" -theme-str "$ROFI_CONFIG")
                    if [ -n "$selected" ]; then
                        # Extract SSID (remove icon and format)
                        ssid=$(echo "$selected" | awk '{print $2}')
                        security=$(echo "$selected" | awk '{print $4}')
                        connect_network "$ssid" "$security"
                    fi
                else
                    notify "No networks found"
                fi
                ;;
            *"Saved Connections")
                connections=$(get_saved_connections)
                if [ -n "$connections" ]; then
                    selected=$(echo "$connections" | rofi -dmenu -p "💾 Saved Networks" -theme-str "$ROFI_CONFIG")
                    if [ -n "$selected" ]; then
                        connect_network "$selected" ""
                    fi
                else
                    notify "No saved connections"
                fi
                ;;
            *"Forget Network")
                forget_network
                ;;
            *"Connection Info")
                show_connection_info
                ;;
            *"Toggle WiFi"*)
                toggle_wifi
                ;;
            *"Connected:"*|*"Not Connected"*|"━"*)
                # Do nothing for status lines
                ;;
            "")
                # User pressed escape or cancelled
                break
                ;;
            *)
                break
                ;;
        esac
    done
}

# Run the main function
main

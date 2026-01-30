#!/bin/bash
# Debug script for session restore logic
# Usage: ./scripts/debug-sessions.sh [create|restore|status|full-test]

SERVER="user@203.0.113.10"
SWIFTDATA_DB="$HOME/Library/Application Support/default.store"
APP_NAME="SuperDuper Terminal"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

header() { echo -e "\n${CYAN}=== $1 ===${NC}"; }
ok() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
fail() { echo -e "${RED}✗ $1${NC}"; }

# Show server tmux state
show_server() {
    header "SERVER TMUX SESSIONS"
    local output
    output=$(ssh "$SERVER" "tmux list-sessions 2>/dev/null" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$output" ]; then
        echo "$output" | while IFS= read -r line; do
            name=$(echo "$line" | cut -d: -f1)
            if [[ "$name" == st-* ]]; then
                ok "$line"
            else
                echo "  $line"
            fi
        done
        echo ""
        echo -e "  st-* count: $(echo "$output" | grep -c '^st-')"
    else
        warn "No tmux sessions on server"
    fi
}

# Show SwiftData persisted sessions
show_swiftdata() {
    header "SWIFTDATA (LOCAL CACHE)"
    if [ ! -f "$SWIFTDATA_DB" ]; then
        warn "SwiftData DB not found at: $SWIFTDATA_DB"
        return
    fi

    local rows
    rows=$(sqlite3 "$SWIFTDATA_DB" "SELECT ZTMUXNAME, ZINDEX, datetime(ZCREATEDAT + 978307200, 'unixepoch', 'localtime') as created FROM ZPERSISTEDSESSION ORDER BY ZINDEX;" 2>/dev/null)
    if [ -n "$rows" ]; then
        echo "  tmux_name | index | created"
        echo "  ----------|-------|--------"
        echo "$rows" | while IFS='|' read -r name idx created; do
            echo "  $name     | $idx    | $created"
        done
        echo ""
        echo -e "  Persisted count: $(echo "$rows" | wc -l | tr -d ' ')"
    else
        warn "No persisted sessions in SwiftData"
    fi
}

# Compare server vs local
compare() {
    header "COMPARISON (server vs local)"

    local server_names
    server_names=$(ssh "$SERVER" "tmux list-sessions -F '#{session_name}' 2>/dev/null" 2>/dev/null | grep '^st-' | sort)

    local local_names
    local_names=$(sqlite3 "$SWIFTDATA_DB" "SELECT ZTMUXNAME FROM ZPERSISTEDSESSION ORDER BY ZTMUXNAME;" 2>/dev/null)

    echo "  Server: $(echo "$server_names" | tr '\n' ' ')"
    echo "  Local:  $(echo "$local_names" | tr '\n' ' ')"
    echo ""

    # Find mismatches
    local only_server only_local
    only_server=$(comm -23 <(echo "$server_names") <(echo "$local_names") 2>/dev/null)
    only_local=$(comm -13 <(echo "$server_names") <(echo "$local_names") 2>/dev/null)

    if [ -n "$only_server" ]; then
        warn "Only on server (will be adopted): $only_server"
    fi
    if [ -n "$only_local" ]; then
        warn "Only in local cache (orphaned): $only_local"
    fi
    if [ -z "$only_server" ] && [ -z "$only_local" ]; then
        ok "Server and local are in sync"
    fi
}

# Check if app is running
app_status() {
    header "APP STATUS"
    if pgrep -f "$APP_NAME" > /dev/null 2>&1; then
        ok "App is running (PID: $(pgrep -f "$APP_NAME" | head -1))"
    else
        warn "App is not running"
    fi
}

# Create test tmux sessions on server
create_test() {
    header "CREATING TEST SESSIONS ON SERVER"
    local count=${1:-3}
    for i in $(seq 0 $((count - 1))); do
        local name="st-$i"
        local exists
        exists=$(ssh "$SERVER" "tmux has-session -t '$name' 2>/dev/null && echo yes || echo no" 2>/dev/null)
        if [ "$exists" = "yes" ]; then
            warn "$name already exists, skipping"
        else
            ssh "$SERVER" "tmux new-session -d -s '$name' 2>/dev/null"
            if [ $? -eq 0 ]; then
                ok "Created $name"
            else
                fail "Failed to create $name"
            fi
        fi
    done
    echo ""
    show_server
}

# Kill all st-* tmux sessions on server
kill_server_sessions() {
    header "KILLING ALL st-* SESSIONS ON SERVER"
    local names
    names=$(ssh "$SERVER" "tmux list-sessions -F '#{session_name}' 2>/dev/null" 2>/dev/null | grep '^st-')
    if [ -z "$names" ]; then
        warn "No st-* sessions to kill"
        return
    fi
    echo "$names" | while read -r name; do
        ssh "$SERVER" "tmux kill-session -t '$name' 2>/dev/null"
        ok "Killed $name"
    done
}

# Clear SwiftData
clear_local() {
    header "CLEARING SWIFTDATA"
    if [ -f "$SWIFTDATA_DB" ]; then
        sqlite3 "$SWIFTDATA_DB" "DELETE FROM ZPERSISTEDSESSION;" 2>/dev/null
        ok "Cleared all persisted sessions"
    else
        warn "No DB to clear"
    fi
}

# Full test: create sessions, restart app, verify restore
full_test() {
    header "FULL RESTORE TEST"

    echo -e "\n${YELLOW}Step 1: Kill app${NC}"
    pkill -f "$APP_NAME" 2>/dev/null
    sleep 1

    echo -e "\n${YELLOW}Step 2: Clean server — kill old st-* sessions${NC}"
    kill_server_sessions

    echo -e "\n${YELLOW}Step 3: Create 3 test sessions on server${NC}"
    create_test 3

    # Run unique commands in each session to verify state is preserved
    ssh "$SERVER" "tmux send-keys -t st-0 'echo MARKER_ST0_HELLO && watch -n2 date' Enter" 2>/dev/null
    ok "st-0: watch date (persistent, shows MARKER_ST0_HELLO)"
    ssh "$SERVER" "tmux send-keys -t st-1 'echo MARKER_ST1_WORLD && top -d 5' Enter" 2>/dev/null
    ok "st-1: top (persistent, shows MARKER_ST1_WORLD)"
    ssh "$SERVER" "tmux send-keys -t st-2 'echo MARKER_ST2_HTOP && htop 2>/dev/null || top' Enter" 2>/dev/null
    ok "st-2: htop/top (persistent, shows MARKER_ST2_HTOP)"
    sleep 2

    echo -e "\n${YELLOW}Step 4: Seed SwiftData with all 3 sessions${NC}"
    # Get server UUID from SwiftData (reuse existing one)
    local server_id
    server_id=$(sqlite3 "$SWIFTDATA_DB" "SELECT hex(ZSERVERID) FROM ZPERSISTEDSESSION LIMIT 1;" 2>/dev/null)
    if [ -z "$server_id" ]; then
        warn "No server ID found in SwiftData — launch app once first to populate"
        return 1
    fi

    # Get raw binary server ID
    local server_id_blob
    server_id_blob=$(sqlite3 "$SWIFTDATA_DB" "SELECT quote(ZSERVERID) FROM ZPERSISTEDSESSION LIMIT 1;" 2>/dev/null)

    echo "  Using server ID: $server_id_blob"

    # Clear and re-insert
    sqlite3 "$SWIFTDATA_DB" "DELETE FROM ZPERSISTEDSESSION;" 2>/dev/null

    local now
    now=$(python3 -c "import time; print(time.time() - 978307200)")

    for i in 0 1 2; do
        sqlite3 "$SWIFTDATA_DB" "INSERT INTO ZPERSISTEDSESSION (Z_PK, Z_ENT, Z_OPT, ZINDEX, ZCREATEDAT, ZTMUXNAME, ZSERVERID) VALUES ($((100 + i)), 1, 1, $i, $now, 'st-$i', $server_id_blob);" 2>/dev/null
        ok "Inserted st-$i into SwiftData"
    done

    show_swiftdata
    compare

    echo -e "\n${YELLOW}Step 5: Launch app and wait for restore${NC}"
    echo "  Opening app..."
    open -a "$APP_NAME" 2>/dev/null || (
        # Build and run if not installed
        cd /Users/alina/projects/swift-terminal
        xcodebuild -project SwiftTerminal.xcodeproj -scheme SwiftTerminalMac -configuration Debug build 2>/dev/null
        open "$(find ~/Library/Developer/Xcode/DerivedData -name "SuperDuper Terminal.app" -path "*/Debug/*" | head -1)" 2>/dev/null
    )

    echo "  Waiting 10s for app to restore..."
    sleep 10

    echo -e "\n${YELLOW}Step 6: Verify restore${NC}"
    show_swiftdata
    compare
    app_status

    echo -e "\n${YELLOW}Step 7: Verify session content preserved${NC}"
    for i in 0 1 2; do
        local content
        content=$(ssh "$SERVER" "tmux capture-pane -t st-$i -p 2>/dev/null" 2>/dev/null)
        local marker="MARKER_ST${i}_"
        if echo "$content" | grep -q "$marker"; then
            ok "st-$i: Content preserved (found $marker)"
        else
            fail "st-$i: Content NOT found (missing $marker)"
        fi
        # Show last 3 lines of pane
        echo "  $(echo "$content" | grep -v '^$' | tail -3 | head -3 | sed 's/^/  /')"
    done

    echo -e "\n${CYAN}Check the app — you should see 3 tabs: st-0, st-1, st-2${NC}"
    echo -e "${CYAN}Each tab should show the running command (watch/top/htop)${NC}"
}

# Verify content of current sessions without restart
verify_content() {
    header "VERIFY SESSION CONTENT"
    local names
    names=$(ssh "$SERVER" "tmux list-sessions -F '#{session_name}' 2>/dev/null" 2>/dev/null | grep '^st-' | sort)
    if [ -z "$names" ]; then
        warn "No st-* sessions on server"
        return
    fi
    echo "$names" | while read -r name; do
        local content
        content=$(ssh "$SERVER" "tmux capture-pane -t '$name' -p 2>/dev/null" 2>/dev/null)
        local running
        running=$(ssh "$SERVER" "tmux list-panes -t '$name' -F '#{pane_current_command}' 2>/dev/null" 2>/dev/null)
        ok "$name — running: $running"
        echo "  Last output:"
        echo "$content" | grep -v '^$' | tail -5 | sed 's/^/    /'
        echo ""
    done
}

# Main
case "${1:-status}" in
    status)
        app_status
        show_server
        show_swiftdata
        compare
        ;;
    server)
        show_server
        ;;
    local)
        show_swiftdata
        ;;
    create)
        create_test "${2:-3}"
        ;;
    kill)
        kill_server_sessions
        ;;
    clear)
        clear_local
        ;;
    compare)
        compare
        ;;
    test|full-test)
        full_test
        ;;
    verify)
        verify_content
        ;;
    *)
        echo "Usage: $0 [status|server|local|create N|kill|clear|compare|test|verify]"
        echo ""
        echo "  status     - Show everything (default)"
        echo "  server     - Show server tmux sessions"
        echo "  local      - Show SwiftData persisted sessions"
        echo "  create N   - Create N test tmux sessions on server"
        echo "  kill       - Kill all st-* sessions on server"
        echo "  clear      - Clear SwiftData persisted sessions"
        echo "  compare    - Compare server vs local"
        echo "  test       - Full test: clean → create → seed → launch → verify"
        echo "  verify     - Check running commands in each session"
        ;;
esac

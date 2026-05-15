#!/bin/bash

# ==========================================================
# SCRIPT: monitor_update_log.sh
# ==========================================================
#
# Purpose:
# --------
# Monitor the daily update_all.sh execution log in real-time
# and display execution status, errors, and summary.
#
# Usage:
# ------
# ./monitor_update_log.sh [--follow]
#
# Options:
# --------
# --follow    Follow log in real-time (tail -f mode)
# (default)   Show last 50 lines and exit
#
# Examples:
# ---------
# ./monitor_update_log.sh
#   → Shows last 50 lines of log and exits
#
# ./monitor_update_log.sh --follow
#   → Follows log in real-time (Ctrl+C to stop)
#
# Log location:
# -------------
# /var/log/update_all.log
#
# What to look for:
# -----------------
# ✅ = Success message (database updated, stack restarted)
# ❌ = Error message (failed operation)
# ERROR: = Critical error (stops execution)
#
# ==========================================================

LOG_FILE="/var/log/update_all.log"
FOLLOW_MODE="false"

# Parse arguments
if [[ "$1" == "--follow" || "$1" == "-f" ]]; then
    FOLLOW_MODE="true"
fi

# Check if log file exists
if [[ ! -f "$LOG_FILE" ]]; then
    echo "❌ Log file not found: $LOG_FILE"
    echo ""
    echo "The log will be created when update_all.sh runs for the first time."
    echo "Scheduled time: 19:00 UTC (1:00 AM BDT)"
    exit 1
fi

echo "📊 Monitoring Odoo update log..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Display file info
echo "📁 Log file: $LOG_FILE"
ls -lh "$LOG_FILE" | awk '{print "   Size: " $5 ", Updated: " $6 " " $7 " " $8}'
echo ""

if [[ "$FOLLOW_MODE" == "true" ]]; then
    echo "🔴 Following log in real-time (press Ctrl+C to stop)..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    tail -f "$LOG_FILE"
else
    echo "📋 Last 50 lines of log:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    tail -50 "$LOG_FILE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Show summary
    echo ""
    echo "📊 Execution Summary:"
    echo "   Updated databases: $(grep -c '✅ Updated' "$LOG_FILE" || echo 0)"
    echo "   Failed operations: $(grep -c '❌\|ERROR:' "$LOG_FILE" || echo 0)"
    echo "   Restarted stacks:  $(grep -c '✅ Stack restarted' "$LOG_FILE" || echo 0)"
    
    # Show last execution time
    LAST_RUN=$(stat "$LOG_FILE" | grep Modify | awk '{print $2 " " $3}')
    echo "   Last execution:    $LAST_RUN"
    
    echo ""
    echo "💡 Tip: Use './monitor_update_log.sh --follow' to watch in real-time"
fi

#!/usr/bin/env bash
# notify.sh - Monitor tmux pane and send notification when task completes
# Usage: notify <refocus> <telegram>
#   refocus: "true" to switch to pane when complete, "false" otherwise
#   telegram: "true" to send telegram notification, "false" otherwise

# Setup script directory and dependencies
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"
source "${CURRENT_DIR}/variables.sh"

# ============================================================================
# Functions
# ============================================================================

# Handle cleanup when monitoring is cancelled
on_cancel() {
  # Wait a bit for all pane monitors to complete
  sleep "$monitor_sleep_duration_value"

  # Perform cleanup operation if monitoring was canceled
  if [[ -f "$PID_FILE_PATH" ]]; then
    kill "$PID"
    rm "${PID_DIR}/${PANE_ID}.pid"
  fi
  exit 0
}
trap 'on_cancel' TERM

# ============================================================================
# Helper Functions
# ============================================================================

# Refocus to monitored pane if requested
refocus_pane() {
  local should_refocus="$1"
  if [[ "$should_refocus" == "true" ]]; then
    tmux switch -t \$"$SESSION_ID"
    tmux select-window -t @"$WINDOW_ID"
    tmux select-pane -t %"$PANE_ID"
  fi
}

# Send notification and perform post-completion tasks
complete_monitoring() {
  local should_refocus="$1"
  local telegram_enabled="$2"

  refocus_pane "$should_refocus"
  notify "$complete_message" "$complete_title" "$telegram_enabled"
}

# Check if Claude Code is currently running
is_claude_code_running() {
  local pane_output="$1"
  echo "$pane_output" | grep -q "esc to interrupt"
}

# Check if shell prompt is present (task completed)
has_shell_prompt() {
  local pane_output="$1"
  echo "$pane_output" | sed '/^[[:space:]]*$/d' | tail -n1 | grep -qE "$prompt_suffixes"
}

# ============================================================================
# Main Script
# ============================================================================

# Toggle monitoring
if [[ ! -f "$PID_FILE_PATH" ]]; then
  # Create PID file to track this monitoring instance
  echo "$$" >"$PID_FILE_PATH"
  tmux display-message "MONITOR ENABLED: #S #W:#P"

  # Determine initial monitoring mode (Claude Code vs regular shell)
  initial_output=$(tmux capture-pane -pt %"$PANE_ID")
  monitoring_mode="shell"
  if is_claude_code_running "$initial_output"; then
    monitoring_mode="claude"
  fi

  # Setup completion message based on verbose mode
  if verbose_enabled; then
    complete_message=$(tmux display-message -p "[#S #W:#P] $monitoring_mode done")
    verbose_msg_title="$(get_tmux_option "$verbose_title_option" "$verbose_title_default")"
    complete_title=$(tmux display-message -p "$verbose_msg_title")
  else
    complete_message="Tmux pane task completed!"
  fi

  # Setup shell prompt pattern for completion detection
  # Convert comma-separated list to regex pattern: "$,#,%" -> "\($|#|%\)$"
  prompt_suffixes="$(get_tmux_option "$prompt_suffixes" "$prompt_suffixes_default")"
  prompt_suffixes=${prompt_suffixes// /}                  # Remove whitespace
  prompt_suffixes=${prompt_suffixes//,/|}                 # Replace comma with OR operator
  prompt_suffixes=$(escape_glob_chars "$prompt_suffixes") # Escape special chars
  prompt_suffixes="${prompt_suffixes}$"                   # Create regex pattern

  # Monitor loop - check for task completion
  monitor_sleep_duration_value=$(get_tmux_option "$monitor_sleep_duration" "$monitor_sleep_duration_default")

  while true; do
    output=$(tmux capture-pane -pt %"$PANE_ID")
    task_completed=false

    # Check completion based on monitoring mode
    if [[ "$monitoring_mode" == "claude" ]]; then
      # Claude Code mode: task is complete when "esc to interrupt" disappears
      if ! is_claude_code_running "$output"; then
        task_completed=true
      fi
    else
      # Shell mode: task is complete when prompt appears
      if has_shell_prompt "$output"; then
        task_completed=true
      fi
    fi

    # Handle task completion
    if [[ "$task_completed" == "true" ]]; then
      complete_monitoring "$1" "$2"
      break
    fi

    sleep "$monitor_sleep_duration_value"
  done

  # Cleanup: remove PID file
  [[ -f "$PID_FILE_PATH" ]] && rm "$PID_FILE_PATH"

  # Execute custom command if configured
  custom_command="$(get_tmux_option "$custom_notify_command" "$custom_notify_command_default")"
  [[ -n "$custom_command" ]] && eval "${custom_command}"
  exit 0
else
  PID=$(cat "$PID_FILE_PATH")
  kill "$PID"
  rm "${PID_DIR}/${PANE_ID}.pid"
  tmux display-message "MONITOR CANCELED: #S #W:#P"
  exit 0
fi

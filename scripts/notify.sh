#!/usr/bin/env bash

# Setup script directory and dependencies
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${CURRENT_DIR}/helpers.sh"
source "${CURRENT_DIR}/variables.sh"

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

# Toggle monitoring
if [[ ! -f "$PID_FILE_PATH" ]]; then
  # Create PID file to track this monitoring instance
  echo "$$" >"$PID_FILE_PATH"
  tmux display "MONITOR ENABLED: #W"

  # Setup completion message based on verbose mode
  if verbose_enabled; then
    output=$(tmux capture-pane -pt %"$PANE_ID")
    complete_message="$(get_last_command "$output")"
    verbose_msg_title="$(get_tmux_option "$verbose_title_option" "$verbose_title_default")"
    complete_subtitle="$(tmux display -p '#W')"
    complete_title=$(tmux display -p "$verbose_msg_title")
  else
    complete_message="Tmux pane task completed!"
  fi

  # Setup shell prompt pattern for completion detection
  # Convert comma-separated list to regex pattern: "$,#,%" -> "\($|#|%\)$"
  prompt_suffixes="$(get_tmux_option "$prompt_suffixes" "$prompt_suffixes_default")"
  prompt_suffixes=${prompt_suffixes// /}                  # Remove whitespace
  prompt_suffixes=${prompt_suffixes//,/|}                 # Replace comma with OR operator
  prompt_suffixes=$(escape_glob_chars "$prompt_suffixes") # Escape special chars

  # Monitor loop - check for task completion
  monitor_sleep_duration_value=$(get_tmux_option "$monitor_sleep_duration" "$monitor_sleep_duration_default")

  while true; do
    output=$(tmux capture-pane -pt %"$PANE_ID")

    if has_shell_prompt "$output"; then
      notify "$complete_title" "$complete_subtitle" "$complete_message"
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
  tmux display "MONITOR CANCELED: #W"
  exit 0
fi

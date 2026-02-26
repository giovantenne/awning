#!/bin/bash
# Setup flow orchestration helpers.

setup_run_wizard_flow() {
  local ignore_disk_space="${1:-0}"

  step_prerequisites "$ignore_disk_space"
  step_node_config
  step_scb_config
  step_rtl_config
  step_generate_configs
  if ! step_build_and_start; then
    return 1
  fi
  if ! step_initialize_wallet; then
    return 1
  fi

  setup_print_completion
}

setup_print_completion() {
  echo ""
  echo -e "  ${ICON_BOLT} ${BOLD}Setup complete!${NC} Bitcoin sync will take several days."
  echo -e "  Run ${CYAN}./awning.sh${NC} again to access the management menu."
  echo ""
}

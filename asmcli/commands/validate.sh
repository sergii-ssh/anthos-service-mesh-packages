validate_subcommand() {
  ### Preparation ###
  context_set-option "ONLY_VALIDATE" 1
  parse_args "${@}"
  validate_args
  prepare_environment

  ### Validate ###
  validate
}

validate() {
  local ONLY_VALIDATE; ONLY_VALIDATE="$(context_get-option "ONLY_VALIDATE")"

  validate_hub
  validate_dependencies
  validate_control_plane

  if [[ "${ONLY_VALIDATE}" -ne 0 ]]; then
    local VALIDATION_ERROR; VALIDATION_ERROR="$(context_get-option "VALIDATION_ERROR")"
    if [[ "${VALIDATION_ERROR}" -eq 0 ]]; then
      info "Successfully validated all requirements to install ASM."
      exit 0
    else
      warn "Please see the errors above."
      exit 2
    fi
  fi

  if only_enable; then
    info "Successfully performed specified --enable actions."
    exit 0
  fi
}

validate_dependencies() {
  local USE_HUB_WIP; USE_HUB_WIP="$(context_get-option "USE_HUB_WIP")"
  local USE_VM; USE_VM="$(context_get-option "USE_VM")"
  local FLEET_ID; FLEET_ID="$(context_get-option "FLEET_ID")"

  if can_modify_gcp_apis; then
    enable_gcloud_apis
  elif should_validate; then
    exit_if_apis_not_enabled
  fi

  if is_gcp; then
    if can_modify_gcp_components; then
      enable_workload_identity
      if ! is_stackdriver_enabled; then
        enable_stackdriver_kubernetes
      fi
      if needs_service_mesh_feature; then
        enable_service_mesh_feature
      fi
    else
      exit_if_no_workload_identity
      exit_if_stackdriver_not_enabled
      if needs_service_mesh_feature; then
        exit_if_service_mesh_feature_not_enabled
      fi
    fi
  fi

  if can_register_cluster; then
    register_cluster
  elif should_validate && [[ "${USE_HUB_WIP}" -eq 1 || "${USE_VM}" -eq 1 ]]; then
    exit_if_cluster_unregistered
  fi

  get_project_number "${FLEET_ID}"

  if can_modify_cluster_labels; then
    add_cluster_labels
  elif should_validate; then
    exit_if_cluster_unlabeled
  fi

  if can_modify_cluster_roles; then
    bind_user_to_cluster_admin
  elif should_validate; then
    exit_if_not_cluster_admin
  fi

  if can_create_namespace; then
    create_istio_namespace
  elif should_validate; then
    exit_if_istio_namespace_not_exists
  fi
}

validate_control_plane() {
  if is_autopilot; then
    validate_autopilot
  elif is_managed; then
    if is_legacy; then
      # Managed legacy must be able to set IAM permissions on a generated user, so the flow
      # is a bit different
      validate_managed_control_plane_legacy
    fi
  else
    validate_in_cluster_control_plane
  fi
}

validate_autopilot() {
  if ! is_managed; then
    fatal "Autopilot clusters are only supported with managed control plane."
  fi
  if is_legacy; then
    fatal "Autopilot clusters are not supported with legacy managed control plane."
  fi
  # Autopilot requires managed CNI
  local USE_MANAGED_CNI; USE_MANAGED_CNI="$(context_get-option "USE_MANAGED_CNI")"
  if [[ "${USE_MANAGED_CNI}" -eq 0 ]]; then
    warn "Managed CNI is required to continue installing managed ASM on GKE Autopilot."
    warn "Confirm or pass --use-managed-cni flag to asmcli."
    if ! prompt_default_no "Continue?"; then fatal "Stopping installation at user request."; fi
  fi
  context_set-option "USE_MANAGED_CNI" 1
}

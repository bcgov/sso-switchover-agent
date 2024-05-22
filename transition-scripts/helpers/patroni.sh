#!/bin/bash

# see https://patroni.readthedocs.io/en/latest/rest_api.html#patroni-rest-api
# `GET /health`: returns HTTP status code 200 only when PostgreSQL is up and running.
check_patroni_health() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 http://localhost:8008/health)

  patroni_status=$(echo "$data" | jq -r '.state')
  if [ "$status_code" -ne "200" ] || [ "$patroni_status" != "running" ]; then
    echo "down"
    return
  fi

  echo "up"
}

wait_for_patroni_healthy() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  count=0
  wait_patroni_up() {
    patroni_health=$(check_patroni_health "$namespace")
    info "checking patroni health - $patroni_health"

    if [ "$patroni_health" == "up" ]; then return 1; fi

    if [[ "$count" -gt 50 ]]; then
      warn "patroni pods are not healthy"
      exit 1
    fi

    count=$((count + 1))
  }

  while wait_patroni_up; do sleep 5; done
}

check_patroni_cluster_mode() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 http://localhost:8008/config)
  if [ "$status_code" -ne "200" ]; then
    echo "inactive"
    return
  fi

  standby_cluster_config=$(echo "$data" | jq -r '.standby_cluster')
  if [ "$standby_cluster_config" == null ]; then
    echo "active"
  else
    echo "standby"
  fi
}

set_patroni_cluster_active() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  patroni_mode=$(check_patroni_cluster_mode "$namespace")
  if [ "$patroni_mode" == "active" ]; then
    echo "success"
    return
  fi

  read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 -XPATCH -d '{"standby_cluster":null}' http://localhost:8008/config)
  if [ "$status_code" -ne "200" ]; then
    echo "failure"
    return
  fi

  standby_cluster_config=$(echo "$data" | jq -r '.standby_cluster')
  if [ "$standby_cluster_config" != null ]; then
    echo "failure"
    return
  fi

  # let's wait for some time to restart patroni pods
  sleep 30
  echo "success"
}

set_patroni_cluster_standby() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  patroni_mode=$(check_patroni_cluster_mode "$namespace")
  if [ "$patroni_mode" == "standby" ]; then
    echo "success"
    return
  fi

  target_host=$(get_tsc_target_host "$namespace" "sso-patroni")
  target_port=$(get_tsc_target_port "$namespace" "sso-patroni")
  if [ -z "$target_port" ]; then exit 1; fi

  read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 -XPATCH -d '{"standby_cluster":{"create_replica_methods":["basebackup_fast_xlog"],"host":'\""$target_host\""',"port":'"$target_port"'}}' http://localhost:8008/config)
  if [ "$status_code" -ne "200" ]; then
    echo "failure"
    return
  fi

  standby_cluster_config=$(echo "$data" | jq -r '.standby_cluster')
  if [ "$standby_cluster_config" == null ]; then
    echo "failure"
    return
  fi

  # let's wait for some time to restart patroni pods
  sleep 30
  echo "success"
}

count_ready_patroni_pods() {
  if [ "$#" -lt 1 ]; then exit 1; fi
  namespace="$1"

  count_ready_pods "$namespace" -l app.kubernetes.io/name=sso-patroni
}

wait_for_patroni_all_ready() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  replicas=$(kubectl get statefulset sso-patroni -n "$namespace" -o jsonpath='{.spec.replicas}')

  count=0
  wait_ready() {
    ready_count=$(count_ready_patroni_pods "$namespace")
    info "patroni ready $ready_count/$replicas"

    if [ "$ready_count" == "$replicas" ]; then return 1; fi

    # wait for 10mins
    if [[ "$count" -gt 120 ]]; then
      warn "patroni replicas is not ready"
      exit 1
    fi

    count=$((count + 1))
  }

  while wait_ready; do sleep 5; done
}

get_patroni_xlog() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"
  patroni_mode=$(check_patroni_cluster_mode "$namespace")
  if [ "$patroni_mode" == "active" ]; then
    leader=$(kubectl -n "$namespace" exec sso-patroni-0 -- patronictl list -f json | jq -r '.[] | select(.Role == "Leader") | .Member')

    # get the leader pod's lasted xlog location in the active patroni cluster.
    read -r status_code data < <(kube_curl "$namespace" "$leader" http://localhost:8008/patroni)
    if [ "$status_code" -ne "200" ]; then exit 1; fi
    xlog=$(echo "$data" | jq -r '.xlog.location')
  else
    # get any of the replicas' xlog received location in the standby patroni cluster.
    read -r status_code data < <(kube_curl "$namespace" sso-patroni-0 http://localhost:8008/patroni)
    if [ "$status_code" -ne "200" ]; then exit 1; fi
    xlog=$(echo "$data" | jq -r '.xlog.received_location')
  fi

  echo "$xlog"
}

compare_patroni_xlog() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  current=$(get_current_cluster)
  target=$(get_target_cluster)

  xlog1=$(get_patroni_xlog "$namespace")

  switch_kube_context "$target" "$namespace" &>/dev/null

  xlog2=$(get_patroni_xlog "$namespace")

  switch_kube_context "$current" "$namespace" &>/dev/null

  if [ "$xlog1" -eq "$xlog2" ]; then
    echo "synced"
  else
    echo "not synced"
  fi
}

wait_for_patroni_xlog_synced() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  count=0
  wait_ready() {
    sync_status=$(compare_patroni_xlog "$namespace")
    info "patroni xlog is $sync_status"

    if [ "$sync_status" == "synced" ]; then return 1; fi

    # wait for 5mins
    if [[ "$count" -gt 60 ]]; then
      warn "patroni xlog failed to be synced"
      exit 1
    fi

    count=$((count + 1))
  }

  while wait_ready; do sleep 5; done
}

patroni_xlog_diffrence() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  current=$(get_current_cluster)
  target=$(get_target_cluster)

  xlog1=$(get_patroni_xlog "$namespace")

  switch_kube_context "$target" "$namespace" &>/dev/null

  xlog2=$(get_patroni_xlog "$namespace")

  switch_kube_context "$current" "$namespace" &>/dev/null

  if [ "$xlog1" -eq "$xlog2" ]; then
    echo "synced"
  else
    difference=$((xlog1-xlog2))
    absdiff=$(abs "$difference")
    echo "$absdiff"
  fi
}

wait_for_patroni_xlog_close() {
  if [ "$#" -lt 1 ]; then exit 1; fi

  namespace="$1"

  count=0
  wait_ready() {
    synch_status=$(patroni_xlog_diffrence "$namespace")
    max_xlog_lag=150000

    if [ "$synch_status" == "synced" ]; then
      info "patroni xlog in $namespace is $synch_status"
      return 1;
    fi

    info "patroni xlogs in $namespace lag by: $synch_status"
    if ((synch_status < max_xlog_lag)); then
      info "The xlogs in $namespace were withing $max_xlog_lag"
      return 1
    fi

    # Retry for 100 seconds before failing
    if [[ "$count" -gt 20 ]]; then
      warn "patroni xlog in $namespace failed to be synced"
      # trigger the alert
      exit 1
    fi

    count=$((count + 1))
  }

  while wait_ready; do sleep 5; done
}

abs() {
    [[ $(( $@ )) -lt 0 ]] && echo "$(( ($@) * -1 ))" || echo "$(( $@ ))"
}

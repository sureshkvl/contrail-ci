#!/usr/bin/env bash

set -e

source ../../common/common.sh
source ../../common/runner.sh

check_binary terraform

declare -g capture_ids
declare -g itf_names

task_default() {
    runner_sequence setup capture can_ping_google
    result=${?}
    runner_sequence teardown
    return $result
}

task_setup() {
    retry 3 terraform apply || return 1
}

task_destroy() {
    retry 3 terraform destroy -force || return 1
}

task_teardown() {
    runner_parallel delete_capture destroy
}

task_capture() {
    local -r port_ids=$(fuzzy_resource_ids "openstack_networking_port_v2.snat_client_port") || return 1
    for port_id in $port_ids
    do
        local itf_name="tap${port_id:0:11}"
        local capture_id=$(capture "G.V().Has('Name', '${itf_name}')" "SNAT test") || return 1
        capture_ids="${capture_ids} ${capture_id}"
        itf_names="${itf_names} ${itf_name}"
    done
}

task_can_ping_google() {
    for itf_name in $itf_names
    do
        local flow=$(wait_flow 20 "G.V().Has('Name', '${itf_name}').Flows().Has('Application', 'ICMPv4')")
        local -i flowAB=$(echo $flow | jq -r '.[].Metric.ABPackets')
        local -i flowBA=$(echo $flow | jq -r '.[].Metric.BAPackets')
        runner_log_notice "Flow has $flowAB ABPackets and $flowBA BAPackets"
        if [[ $flowAB -gt 0 ]] && [[ $flowBA -gt 0 ]]; then
            runner_log_success "Reply to ping found"
        else
            runner_log_error "No reply to ping found"
            return 1
        fi
    done
}

task_delete_capture() {
    for capture_id in $capture_ids
    do
        delete_capture $capture_id
    done
}
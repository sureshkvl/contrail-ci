#!/usr/bin/env bash

set -e

source ../../common/common.sh
source ../../common/runner.sh

task_default() {
    runner_sequence setup capture should_see_ping_on_both_ends remove_sg_rule should_not_see_ping_on_both_ends
    result=${?}
    runner_sequence teardown
    return $result
}

task_setup() {
    terrapply || return 1
}

task_destroy() {
    terradestroy || return 1
    clean_vars
}

task_teardown() {
    runner_parallel delete_capture destroy
}

task_capture() {
    itf_name=$(port_interface_name "sg_vm1_port") || return 1
    capture_id=$(capture "G.V().Has('Name', '${itf_name}')" "SG test") || return 1
    save_vars itf_name capture_id
}

task_delete_capture() {
    `get_vars`
    delete_capture $capture_id
}

task_should_see_ping_on_both_ends() {
    `get_vars`
    flow=$(wait_flow 20 "G.V().Has('Name', '$itf_name').Flows().Has('Application', 'ICMPv4').Has('Metric.ABPackets', GT(0)).Has('Metric.BAPackets', GT(0))") || return 1
    tracking_id=$(echo "$flow" | jq -r '.[].TrackingID')
    runner_log_success "Found expected flow with TrackingID ${tracking_id}"
    save_vars tracking_id
}

task_remove_sg_rule() {
    terrapply -target=openstack_compute_secgroup_v2.sg_secgroup remove-sg-rule || return 1
    # wait a bit for the sg to be propagated
    sleep 3
}

task_should_not_see_ping_on_both_ends() {
    `get_vars`
    flow1=$(gremlin "G.V().Has('Name', '$itf_name').Flows().Has('TrackingID', '${tracking_id}')") || return 1
    local -i flow1AB=$(echo $flow1 | jq -r '.[].Metric.ABPackets')
    local -i flow1BA=$(echo $flow1 | jq -r '.[].Metric.BAPackets')
    runner_log_notice "Flow has $flow1AB ABPackets and $flow1BA BAPackets"
    sleep 3
    flow2=$(gremlin "G.V().Has('Name', '$itf_name').Flows().Has('TrackingID', '${tracking_id}')") || return 1
    local -i flow2AB=$(echo $flow2 | jq -r '.[].Metric.ABPackets')
    local -i flow2BA=$(echo $flow2 | jq -r '.[].Metric.BAPackets')
    runner_log_notice "Flow has now $flow2AB ABPackets and $flow2BA BAPackets"

    if [[ $flow2AB -gt $flow1AB ]] && [[ $flow2BA -eq $flow1BA ]]; then
        runner_log_success "No reply to ping found"
    elif [[ $flow2AB -eq $flow1AB ]] && [[ $flow2BA -gt $flow1BA ]]; then
        runner_log_success "No reply to ping found"
    else
        runner_log_error "Ping shouldn't work between VMs"
        return 1
    fi
}

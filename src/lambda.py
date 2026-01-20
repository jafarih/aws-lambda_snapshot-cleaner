import os
from datetime import datetime, timedelta, timezone
import boto3
from botocore.exceptions import ClientError

# helper functions


def log_msg(input_msg):
    """prefix timestamp to a string and print it. good for logging"""
    timestamp = datetime.now(timezone.utc).strftime(
        "%Y-%m-%d %H:%M:%S")  # utc timezone for consistency with cloudwatch
    print(f"[{timestamp}] {input_msg}")


log_msg("Loading ")


def lambda_handler(event, context):
    # prep work
    # vars and guard rails:

    # aws_region is reserved and gets injected by lambda service
    region = os.environ.get("AWS_REGION")
    service_name = os.environ.get("SERVICE_NAME")

    # banner
    log_msg(f"######### Starting: {service_name} #########")
    # note: retention time comes from Makefile and should be changed there
    retention_hours_rawval = os.environ.get("RETENTION_HOURS")

    # guard rail for retention time: if missing exit immediately with no action
    if retention_hours_rawval is None or str(retention_hours_rawval).strip() == "":
        log_msg("ERROR guardrail: RETENTION_HOURS is not set. exiting.")
        return {"reached_end_of_list": False, "error": "RETENTION_HOURS is not set"}

    # guard rail: avoid fat fingering retention value.
    try:
        retention_hours = float(retention_hours_rawval)
    except ValueError:
        log_msg(
            f"ERROR guardrail: RETENTION_HOURS is not a number: {retention_hours_rawval}. exiting.")
        return {"reached_end_of_list": False, "error": "RETENTION_HOURS is invalid"}

    # guard rail for retention time: if it is less than 1hr exit without deleting to avoid a bad day
    if retention_hours < 1:
        log_msg(
            f"ERROR guardrail: RETENTION_HOURS={retention_hours} is < 1 hour. this is likely not the desired value. check the Makefile exiting.")
        return {"reached_end_of_list": False, "error": "RETENTION_HOURS is too small"}

    # calculate the age cut off to use. using utc tz for consistency and logging for compliance
    cutoff = datetime.now(timezone.utc) - timedelta(hours=retention_hours)
    log_msg(
        f"start region={region} retention_hours={retention_hours} cutoff_age_in_utc={cutoff.isoformat()}")

    # main section
    # initialize counters
    snapshots_checked = 0
    snapshots_deleted = 0
    errors_encountered = 0

    # connect to ec2 service
    ec2 = boto3.client("ec2", region_name=region)

    # get a list of all ec2 snapshots owned by current user
    # handle multi page results via paginator
    paginator = ec2.get_paginator("describe_snapshots")

    # go through each page of snapshot lists and process each snapshot
    for page in paginator.paginate(OwnerIds=["self"]):
        for snap in page.get("Snapshots", []):
            snapshots_checked += 1
            snapshot_id = snap.get("SnapshotId")

            start_time = snap.get("StartTime")
            # guard rail: if for some reason, StartTime is missing then error and move to next snapshot
            # This shouldn't really happen. if it did something is likely wrong with accessing that value. skip and move on.
            if not start_time:
                errors_encountered += 1
                log_msg(
                    f"ERROR this snapshot is missing StartTime. snapshot_id={snapshot_id}. this should not happen, and is likely a sign of access issues. skipping this snapshot.")
                continue
            # only move on with the this snapshot if it is equal or older than the retention period (set in Makefile)
            if start_time >= cutoff:
                continue

            # log deletion attempt and do some basic error handling
            log_msg(
                f"Deleting snapshot: {snapshot_id} start={start_time.isoformat()}")

            # ============ try deleting the snapshot ===============#
            try:
                ec2.delete_snapshot(SnapshotId=snapshot_id)
                snapshots_deleted += 1
            # if deletion fails then throw an exception and raise the underlying response code and message
            except ClientError as e:
                errors_encountered += 1
                # try to read aws error code, and fallback to unknown
                code = e.response.get("Error", {}).get("Code", "Unknown")
                msg = e.response.get("Error", {}).get("Message", str(e))
                log_msg(f"ERROR deleting {snapshot_id}: {code} - {msg}")
    # emit final results to logs and show if list was processed
    log_msg(
        f"done snapshots_checked={snapshots_checked} snapshots_deleted={snapshots_deleted} errors_encountered={errors_encountered}")
    return {"reached_end_of_list": True, "snapshots_checked": snapshots_checked, "snapshots_deleted": snapshots_deleted, "errors_encountered": errors_encountered}

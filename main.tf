###############################################################################
# log360-gcp — provisions the log pipeline Log360 Cloud reads from.
#
# Creates, in this order (Terraform infers it from the references):
#   1. Pub/Sub topic            the sink needs a destination that exists
#   2. Log sink                 org, folder or project scope
#   3. Publisher grant          to the sink's writer identity, on the topic
#   4. Pull subscription        ours alone, never one you already have
#   5. Subscriber grant         to the Log360 collector, on the subscription
#
# Every IAM resource here is *_iam_member, which appends. The _iam_binding and
# _iam_policy resources are authoritative: they replace the whole policy on the
# topic or subscription and would silently strip the publisher grants your
# other sinks depend on.
###############################################################################

terraform {
  required_version = ">= 1.3"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

locals {
  # One clause per log stream. %2F is percent-encoded on purpose — decoding it
  # to "/" for readability matches zero entries and reports no error.
  #
  # Load balancer is the documented resource.type exception: its log ID is the
  # bare word "requests", which collides across products.
  clauses = {
    audit_activity     = "logName:\"cloudaudit.googleapis.com%2Factivity\""
    audit_data_access  = "logName:\"cloudaudit.googleapis.com%2Fdata_access\""
    audit_system_event = "logName:\"cloudaudit.googleapis.com%2Fsystem_event\""
    audit_policy       = "logName:\"cloudaudit.googleapis.com%2Fpolicy\""
    firewall           = "logName:\"compute.googleapis.com%2Ffirewall\""
    nat                = "logName:\"compute.googleapis.com%2Fnat\""
    dns                = "logName:\"dns.googleapis.com%2Fdns_queries\""
    load_balancer      = "resource.type=(\"http_load_balancer\" OR \"internal_http_lb_rule\")"
    load_balancer_regional = "logName:\"loadbalancing.googleapis.com%2Fexternal_regional_requests\""

    # Findings reach Cloud Logging only when "Log findings to Logging" is on in
    # Continuous Exports, and then only Event Threat Detection and Container
    # Threat Detection findings. Everything else needs the notification path.
    scc_threat_findings = "resource.type=\"threat_detector\""
  }

  # Each clause is parenthesised and any scoping ANDs inside its own group.
  # A flat join produces "A OR B AND label=x", where AND binds tighter and the
  # label restricts B alone.
  selected = [
    for s in var.sources : (
      lookup(var.resource_scoping, s, null) == null
      ? "(${local.clauses[s]})"
      : "(${local.clauses[s]} AND ${var.resource_scoping[s].label} = (${
        join(" OR ", [for v in var.resource_scoping[s].values : "\"${v}\""])
      }))"
    )
  ]

  sink_filter = join("\n  OR ", local.selected)

  topic_name = coalesce(var.topic_name, "${var.prefix}-topic")
  sub_name   = coalesce(var.subscription_name, "${var.prefix}-sub")
  sink_name  = coalesce(var.sink_name, "${var.prefix}-sink")

  is_org     = var.scope == "organization"
  is_folder  = var.scope == "folder"
  is_project = var.scope == "project"

  writer_identity = local.is_org ? google_logging_organization_sink.log360[0].writer_identity : (
    local.is_folder ? google_logging_folder_sink.log360[0].writer_identity
    : google_logging_project_sink.log360[0].writer_identity
  )
}

###############################################################################
# 1 · Destination topic
###############################################################################

resource "google_pubsub_topic" "log360" {
  name    = local.topic_name
  project = var.project_id

  labels = {
    managed-by = "log360-cloud"
  }
}

###############################################################################
# 2 · Log sink
#
# Organization or folder scope with include_children is the only configuration
# that does not go stale: projects created later are covered with no
# re-onboarding, and nothing reports a project sink having gone out of date.
###############################################################################

resource "google_logging_organization_sink" "log360" {
  count = local.is_org ? 1 : 0

  name             = local.sink_name
  org_id           = var.scope_id
  include_children = true
  destination      = "pubsub.googleapis.com/${google_pubsub_topic.log360.id}"
  filter           = local.sink_filter
}

resource "google_logging_folder_sink" "log360" {
  count = local.is_folder ? 1 : 0

  name             = local.sink_name
  folder           = var.scope_id
  include_children = true
  destination      = "pubsub.googleapis.com/${google_pubsub_topic.log360.id}"
  filter           = local.sink_filter
}

resource "google_logging_project_sink" "log360" {
  count = local.is_project ? 1 : 0

  name        = local.sink_name
  project     = var.scope_id
  destination = "pubsub.googleapis.com/${google_pubsub_topic.log360.id}"
  filter      = local.sink_filter

  # Without this the sink shares a generic writer identity with every other
  # sink in the project, and the grant below would be far wider than intended.
  unique_writer_identity = true
}

###############################################################################
# 3 · Publisher grant
#
# GCP creates the sink's writer identity with no permissions at all. Omitting
# this grant is the most common reason a correctly configured pipeline delivers
# nothing — there is no error anywhere in GCP when it is missing.
###############################################################################

resource "google_pubsub_topic_iam_member" "sink_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.log360.name
  role    = "roles/pubsub.publisher"
  member  = local.writer_identity
}

###############################################################################
# 4 · Pull subscription
#
# Always created, never shared. Pub/Sub delivers each message to exactly one
# client on a subscription, so pointing Log360 at a subscription something else
# already reads would split the stream — both sides would have gaps.
###############################################################################

resource "google_pubsub_subscription" "log360" {
  name    = local.sub_name
  project = var.project_id
  topic   = google_pubsub_topic.log360.id

  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = var.message_retention

  # Never expire. The default deletes a subscription after 31 days without
  # activity, which would silently end collection on a quiet estate.
  expiration_policy {
    ttl = ""
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  labels = {
    managed-by = "log360-cloud"
  }
}

###############################################################################
# 5 · Subscriber grant
#
# The single permission Log360 holds in steady state. Nothing on the topic,
# nothing on the sink, nothing at organization level.
###############################################################################

resource "google_pubsub_subscription_iam_member" "collector" {
  project      = var.project_id
  subscription = google_pubsub_subscription.log360.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.collector_service_account}"
}

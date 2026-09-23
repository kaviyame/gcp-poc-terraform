###############################################################################
# log360-gcp — provisions the log pipeline Log360 Cloud reads from.
#
# Scope is inferred from what you set, and you set exactly one:
#
#   project_id = "acme-prod"      project scope
#                                 sink, topic and subscription all live there
#
#   org_id     = "123456789012"   organization scope
#                                 creates a central logging project, puts the
#                                 topic and subscription in it, and creates an
#                                 aggregated sink at the organization
#
# The aggregated sink is non-intercepting: every project's own _Default sink
# keeps working exactly as before, and its logs stay searchable in that project.
# We add a route, we do not divert one.
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

locals {
  is_org     = var.org_id != null
  is_project = var.project_id != null

  # Where the topic and subscription end up. For org scope that is the project
  # created below; for project scope it is the one you named.
  target_project = local.is_org ? google_project.central[0].project_id : var.project_id

  # One clause per log stream. %2F is percent-encoded on purpose — decoding it
  # to "/" for readability matches zero entries and reports no error.
  #
  # Load balancer is the documented resource.type exception: its log ID is the
  # bare word "requests", which collides across products.
  clauses = {
    audit_activity         = "logName:\"cloudaudit.googleapis.com%2Factivity\""
    audit_data_access      = "logName:\"cloudaudit.googleapis.com%2Fdata_access\""
    audit_system_event     = "logName:\"cloudaudit.googleapis.com%2Fsystem_event\""
    audit_policy           = "logName:\"cloudaudit.googleapis.com%2Fpolicy\""
    firewall               = "logName:\"compute.googleapis.com%2Ffirewall\""
    nat                    = "logName:\"compute.googleapis.com%2Fnat\""
    dns                    = "logName:\"dns.googleapis.com%2Fdns_queries\""
    load_balancer          = "resource.type=(\"http_load_balancer\" OR \"internal_http_lb_rule\")"
    load_balancer_regional = "logName:\"loadbalancing.googleapis.com%2Fexternal_regional_requests\""

    # Findings reach Cloud Logging only when "Log findings to Logging" is on in
    # Continuous Exports, and then only Event Threat Detection and Container
    # Threat Detection findings. Everything else needs the notification path.
    scc_threat_findings = "resource.type=\"threat_detector\""
  }

  # Each clause is parenthesised and any scoping ANDs inside its own group.
  # A flat join would produce "A OR B AND label=x", where AND binds tighter and
  # the label restricts B alone.
  sink_filter = join("\n  OR ", [
    for s in var.sources : (
      lookup(var.resource_scoping, s, null) == null
      ? "(${local.clauses[s]})"
      : "(${local.clauses[s]} AND ${var.resource_scoping[s].label} = (${
        join(" OR ", [for v in var.resource_scoping[s].values : "\"${v}\""])
      }))"
    )
  ])

  topic_name = coalesce(var.topic_name, "${var.prefix}-topic")
  sub_name   = coalesce(var.subscription_name, "${var.prefix}-sub")
  sink_name  = coalesce(var.sink_name, "${var.prefix}-sink")

  writer_identity = (local.is_org
    ? google_logging_organization_sink.log360[0].writer_identity
  : google_logging_project_sink.log360[0].writer_identity)

  # Terraform has no cross-variable validation, so this fails the plan with a
  # readable message rather than a confusing error deeper in.
  scope_check = (local.is_org == local.is_project
    ? tobool("Set exactly one of project_id or org_id — not both, not neither.")
  : true)
}

###############################################################################
# 0 · Central logging project — organization scope only
#
# Needs resourcemanager.projectCreator on the organization AND a billing
# account you can attach. That is a considerably larger permission than
# everything else in this module combined. If it is not available, create the
# project yourself and set project_id instead.
###############################################################################

resource "random_id" "suffix" {
  count       = local.is_org && var.central_project_id == null ? 1 : 0
  byte_length = 3
}

resource "google_project" "central" {
  count = local.is_org ? 1 : 0

  # Project IDs are globally unique across all of GCP, so a plain name is
  # usually taken. The suffix avoids a collision with someone else's project.
  project_id      = coalesce(var.central_project_id, "log360-logs-${random_id.suffix[0].hex}")
  name            = var.central_project_name
  org_id          = var.org_id
  billing_account = var.billing_account

  # No default VPC. Nothing here needs one, and it would be an unused network
  # carrying its own firewall rules and quota.
  auto_create_network = false

  labels = {
    managed-by = "log360-cloud"
  }
}

resource "google_project_service" "central" {
  for_each = local.is_org ? toset(["pubsub.googleapis.com", "logging.googleapis.com"]) : toset([])

  project = google_project.central[0].project_id
  service = each.value

  # Leave the APIs on when destroying. Disabling them could break anything else
  # the customer has since put in this project.
  disable_on_destroy = false
}

###############################################################################
# 1 · Destination topic
###############################################################################

resource "google_pubsub_topic" "log360" {
  name    = local.topic_name
  project = local.target_project

  labels = {
    managed-by = "log360-cloud"
  }

  depends_on = [google_project_service.central]
}

###############################################################################
# 2 · Log sink
###############################################################################

resource "google_logging_organization_sink" "log360" {
  count = local.is_org ? 1 : 0

  name   = local.sink_name
  org_id = var.org_id

  # Covers every project beneath, including ones created later — the only
  # configuration that does not silently go stale.
  include_children = true

  # intercept_children is deliberately left unset. Intercepting would stop
  # matching entries reaching each project's own _Default sink, so they would
  # disappear from that project's Logs Explorer.
  destination = "pubsub.googleapis.com/${google_pubsub_topic.log360.id}"
  filter      = local.sink_filter
}

resource "google_logging_project_sink" "log360" {
  count = local.is_project ? 1 : 0

  name        = local.sink_name
  project     = var.project_id
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
  project = local.target_project
  topic   = google_pubsub_topic.log360.name
  role    = "roles/pubsub.publisher"
  member  = local.writer_identity
}

###############################################################################
# 4 · Pull subscription
#
# Always created, never shared. Pub/Sub delivers each message to exactly one
# client on a subscription, so pointing Log360 at one something else already
# reads would split the stream and leave both sides with gaps.
###############################################################################

resource "google_pubsub_subscription" "log360" {
  name    = local.sub_name
  project = local.target_project
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
# 5 · Subscriber grant — only if a collector account was given
#
# The single permission Log360 holds in steady state. Nothing on the topic,
# nothing on the sink, nothing at organization level.
###############################################################################

# Skipped when collector_service_account is not set. Nothing is created on
# your behalf — grant it later, or let Log360 tell you the command to run.
resource "google_pubsub_subscription_iam_member" "collector" {
  count = var.collector_service_account == null ? 0 : 1

  project      = local.target_project
  subscription = google_pubsub_subscription.log360.name
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.collector_service_account}"
}

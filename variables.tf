###############################################################################
# Set exactly one of project_id or org_id. That choice is the scope.
###############################################################################

variable "project_id" {
  description = <<-EOT
    Project scope. The sink, topic and subscription are all created here, and
    the sink covers this project only.

    Projects created later are NOT covered, and nothing reports that it has gone
    stale. Use org_id instead when you have organization access.
  EOT
  type        = string
  default     = null
}

variable "org_id" {
  description = <<-EOT
    Organization scope, as a 12-digit ID. Creates a central logging project,
    puts the topic and subscription in it, and creates an aggregated sink at the
    organization covering every project beneath — including ones created later.

    The sink is non-intercepting, so each project's own _Default sink keeps
    working and its logs stay searchable in that project.

    Requires resourcemanager.projectCreator on the organization and a billing
    account, because a project is created. If that is unavailable, create the
    project yourself and use project_id.
  EOT
  type        = string
  default     = null
}

variable "billing_account" {
  description = "Billing account ID to attach to the created project, e.g. 01ABCD-2345EF-6789GH. Required with org_id; ignored with project_id."
  type        = string
  default     = null
}

variable "central_project_id" {
  description = "ID for the created logging project. Leave null for log360-logs-<random>. Project IDs are globally unique across all of GCP, so a plain name is usually taken."
  type        = string
  default     = null
}

variable "central_project_name" {
  description = "Display name for the created logging project."
  type        = string
  default     = "Log360 Cloud logging"
}

###############################################################################
# Collection
###############################################################################

variable "collector_service_account" {
  description = <<-EOT
    Service account Log360 reads with, as a bare email. It is granted
    roles/pubsub.subscriber on the created subscription and nothing else.

    Leave it unset and no grant is made — the pipeline is built, and you add the
    grant later. Nothing is created on your behalf either way.
  EOT
  type        = string
  default     = null

  validation {
    condition = var.collector_service_account == null || can(regex(
      "^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.collector_service_account))
    error_message = "Give the bare service account email, with no serviceAccount: prefix."
  }
}

variable "sources" {
  description = <<-EOT
    Log streams to route. Each becomes one clause in the sink filter, so
    removing one stops that data at the source rather than dropping it after you
    have paid to move it.

    Valid: audit_activity, audit_data_access, audit_system_event, audit_policy,
           firewall, nat, dns, load_balancer, load_balancer_regional,
           scc_threat_findings

    audit_data_access is excluded by default and is frequently larger than every
    other source combined.

    Three sources are opt-in inside GCP and a sink cannot enable them. If DNS
    query logging is off, a NAT gateway is set to ERRORS_ONLY, or firewall rules
    have logging disabled, the pipeline provisions cleanly and stays empty.
  EOT
  type        = list(string)
  default     = ["audit_activity", "audit_system_event", "audit_policy"]

  validation {
    condition = alltrue([
      for s in var.sources : contains([
        "audit_activity", "audit_data_access", "audit_system_event", "audit_policy",
        "firewall", "nat", "dns", "load_balancer", "load_balancer_regional",
        "scc_threat_findings",
      ], s)
    ])
    error_message = "One or more entries in sources is not a known log stream."
  }

  validation {
    condition     = length(var.sources) > 0
    error_message = "Select at least one source, or the sink would route everything."
  }
}

variable "resource_scoping" {
  description = <<-EOT
    Optional per-source narrowing, ANDed inside that source's own clause.

    Take the values from your GCP inventory rather than typing them — a name
    that does not exist matches zero entries and reports no error.

      resource_scoping = {
        nat = {
          label  = "resource.labels.gateway_name"
          values = ["nat-gw-use1", "nat-gw-euw1"]
        }
      }

    Known labels: nat -> resource.labels.gateway_name,
                  load_balancer -> resource.labels.forwarding_rule_name.
  EOT
  type = map(object({
    label  = string
    values = list(string)
  }))
  default = {}
}

###############################################################################
# Naming and tuning — defaults are fine
###############################################################################

variable "prefix" {
  description = "Name prefix for the created resources."
  type        = string
  default     = "log360-gcp"
}

variable "topic_name" {
  description = "Override the generated topic name."
  type        = string
  default     = null
}

variable "subscription_name" {
  description = "Override the generated subscription name."
  type        = string
  default     = null
}

variable "sink_name" {
  description = "Override the generated sink name."
  type        = string
  default     = null
}

variable "ack_deadline_seconds" {
  description = "How long the collector has to acknowledge a message before Pub/Sub redelivers it. The collector extends it while working."
  type        = number
  default     = 60
}

variable "message_retention" {
  description = "How long unacknowledged messages are kept. Seven days is the maximum, and is the buffer you get if collection stops. Unacknowledged messages older than a day incur storage charges."
  type        = string
  default     = "604800s"
}

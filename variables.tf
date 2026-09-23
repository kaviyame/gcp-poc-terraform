variable "project_id" {
  description = "Project that holds the topic and subscription. For a centralised setup this is your logging project, not necessarily the one the sink is scoped to."
  type        = string
}

variable "scope" {
  description = "Where the sink sits. An organization or folder sink with include_children covers projects created later; a project sink does not, and nothing reports that it has gone stale."
  type        = string
  default     = "organization"

  validation {
    condition     = contains(["organization", "folder", "project"], var.scope)
    error_message = "scope must be organization, folder or project."
  }
}

variable "scope_id" {
  description = "Organization ID (12 digits), folder ID, or project ID — matching var.scope. Not the display name."
  type        = string
}

variable "collector_service_account" {
  description = "Service account Log360 reads with, as a bare email. It is granted roles/pubsub.subscriber on the created subscription and nothing else."
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.iam\\.gserviceaccount\\.com$", var.collector_service_account))
    error_message = "Give the bare service account email, with no serviceAccount: prefix."
  }
}

variable "sources" {
  description = <<-EOT
    Log streams to route. Each becomes one clause in the sink filter, so removing
    one stops that data at the source rather than dropping it after you have paid
    to move it.

    Valid: audit_activity, audit_data_access, audit_system_event, audit_policy,
           firewall, nat, dns, load_balancer, load_balancer_regional,
           scc_threat_findings

    audit_data_access is excluded by default. It is frequently larger than every
    other source combined.

    Three sources are opt-in inside GCP and a sink cannot enable them — if DNS
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
  description = "How long the collector has to acknowledge a message before Pub/Sub redelivers it. Raise it if downstream processing is slow; the collector extends it while working."
  type        = number
  default     = 60
}

variable "message_retention" {
  description = "How long unacknowledged messages are kept. Seven days is the maximum, and the buffer you get if collection stops. Unacknowledged messages older than a day incur storage charges."
  type        = string
  default     = "604800s"
}

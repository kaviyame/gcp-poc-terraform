output "subscription" {
  description = "Full resource name of the subscription. This is what you paste into Log360 Cloud — subscription IDs are unique only within a project, so the full path is what identifies it."
  value       = google_pubsub_subscription.log360.id
}

output "logging_project" {
  description = "Project holding the topic and subscription. For organization scope this is the project this module created."
  value       = local.target_project
}

output "topic" {
  description = "Full resource name of the created topic."
  value       = google_pubsub_topic.log360.id
}

output "sink_name" {
  description = "Sink name. Sink IDs are unique only within their parent, so keep the scope alongside it."
  value       = local.sink_name
}

output "sink_scope" {
  description = "Where the sink was created."
  value       = local.is_org ? "organizations/${var.org_id} (aggregated, include_children, non-intercepting)" : "projects/${var.project_id}"
}

output "sink_writer_identity" {
  description = "Service account GCP created with the sink, granted publisher on the topic. If the pipeline delivers nothing, check this grant first."
  value       = local.writer_identity
}

output "sink_filter" {
  description = "The generated filter. Paste it into Logs Explorer to confirm it returns entries before expecting data in Log360."
  value       = local.sink_filter
}

output "verify" {
  description = "Command to confirm entries are arriving."
  value       = "gcloud pubsub subscriptions pull ${local.sub_name} --project=${local.target_project} --auto-ack --limit=5"
}

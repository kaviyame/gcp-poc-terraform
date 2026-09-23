# Replace everything below with the block Log360 gave you.
# Save with Ctrl+S, then return to the tutorial.

project_id                = "REPLACE-ME"
scope                     = "organization"
scope_id                  = "REPLACE-ME"
collector_service_account = "REPLACE-ME@REPLACE-ME.iam.gserviceaccount.com"

sources = [
  "audit_activity",
  "audit_system_event",
  "audit_policy",
]

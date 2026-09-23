# Set exactly one: project_id or org_id.

project_id = "REPLACE-ME"

# org_id          = "123456789012"
# billing_account = "01ABCD-2345EF-6789GH"

collector_service_account = "REPLACE-ME@REPLACE-ME.iam.gserviceaccount.com"

sources = [
  "audit_activity",
  "audit_system_event",
  "audit_policy",
]

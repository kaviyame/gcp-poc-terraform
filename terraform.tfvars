# Replace everything below with the block Log360 gave you.
# Save with Ctrl+S, then return to the tutorial.
#
# Set EXACTLY ONE of project_id or org_id. That choice is the scope.

# --- Project scope: sink, topic and subscription all in this project ---------
project_id = "REPLACE-ME"

# --- Organization scope: creates a logging project, aggregated sink at org ---
# Comment out project_id above and uncomment these instead.
#
# org_id          = "123456789012"
# billing_account = "01ABCD-2345EF-6789GH"

collector_service_account = "REPLACE-ME@REPLACE-ME.iam.gserviceaccount.com"

sources = [
  "audit_activity",
  "audit_system_event",
  "audit_policy",
]

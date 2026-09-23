# Set up GCP log collection for Log360 Cloud

<walkthrough-tutorial-duration duration="8"></walkthrough-tutorial-duration>

This creates the pipeline Log360 reads from: a log sink, a Pub/Sub topic, a pull
subscription, and the two IAM grants that connect them.

You run every command here, with your own credentials. Log360 is not given write
access to your Google Cloud at any point. When this finishes, the only
permission Log360 holds is the ability to read one Pub/Sub subscription.

Click **Next** to begin.

## Choose your scope

There are two ways to run this, and the choice decides everything else. Read
both before picking.

**Organization scope** — recommended if you have the access for it.

One aggregated sink at the organization covers every project beneath it,
including projects created after today. This module creates a small central
logging project to hold the topic and subscription.

It is the only configuration that does not go stale. A project sink covers one
project forever; when someone adds a new project next quarter, its logs are
simply absent and nothing reports it.

The sink is **non-intercepting**. Every project's own `_Default` sink keeps
working exactly as before, and its logs stay searchable in that project's Logs
Explorer. This adds a route; it does not divert one.

**Project scope** — one project only.

The sink, topic and subscription are all created in a project you name. Nothing
is created outside it, and no organization-level permission is needed.

Choose this when organization access is unavailable, or for a trial. Accept that
projects created later will need onboarding again.

## Check you have the right roles

The apply fails at the end if these are missing, so check now.

First, confirm which account this session is using:

```bash
gcloud auth list
```

**Both scopes need:**

* `roles/pubsub.admin` on the project that will hold the topic

**Project scope also needs:**

* `roles/logging.configWriter` on that project

**Organization scope also needs:**

* `roles/logging.configWriter` on the organization
* `roles/resourcemanager.projectCreator` on the organization
* `roles/billing.user` on a billing account you can attach

Those last two are what allow a project to be created, and they are a
considerably larger permission than everything else combined. If you cannot get
them, create the logging project yourself first and use project scope pointed at
it.

Find your organization ID and billing account:

```bash
gcloud organizations list
gcloud billing accounts list
```

Click **Next** when you have what you need.

## Set your values

Open the variables file:

```bash
cloudshell edit terraform.tfvars
```

Replace the contents with the block Log360 gave you, or edit it by hand.

**For organization scope**, set `org_id` and `billing_account`, and leave
`project_id` commented out:

```
org_id                    = "123456789012"
billing_account           = "01ABCD-2345EF-6789GH"
collector_service_account = "log360-collector@your-project.iam.gserviceaccount.com"

sources = [
  "audit_activity",
  "audit_system_event",
  "audit_policy",
]
```

**For project scope**, set `project_id` and leave the organization lines
commented out:

```
project_id                = "your-project-id"
collector_service_account = "log360-collector@your-project.iam.gserviceaccount.com"

sources = [
  "audit_activity",
  "audit_system_event",
  "audit_policy",
]
```

Set exactly one of `project_id` and `org_id`. Setting both, or neither, stops
the plan with a message saying so.

Save with `Ctrl+S`, then click **Next**.

## About the sources you selected

Each entry in `sources` becomes one clause in the sink filter. Removing one
later and re-applying rewrites that filter, so the data stops at the source
rather than being dropped after you have paid to move it.

**`audit_data_access` is excluded by default** and is frequently larger than
every other source combined. Add it only if you need read-level auditing.

**Three sources are opt-in inside Google Cloud, and a sink cannot enable them.**
If you selected any of these, check them now or the pipeline will provision
cleanly and stay empty:

* **Cloud DNS** — query logging is enabled per VPC network, and is off by
  default
* **Cloud NAT** — logging is set per gateway, and a gateway on `ERRORS_ONLY`
  delivers almost nothing
* **Firewall** — logging is opted into per rule

**`scc_threat_findings`** needs *Log findings to Logging* enabled in Security
Command Center's Continuous Exports. Even then only Event Threat Detection and
Container Threat Detection findings reach Cloud Logging — Security Health
Analytics, posture and toxic-combination findings do not.

## Review the plan

```bash
terraform init
terraform plan
```

**Project scope** should show **five resources to add**:

1. `google_pubsub_topic` — created first, because the sink needs a destination
   that already exists
2. `google_logging_project_sink` — returns a writer identity, which step 3 needs
3. `google_pubsub_topic_iam_member` — publisher, granted to that writer identity
4. `google_pubsub_subscription` — read only by Log360
5. `google_pubsub_subscription_iam_member` — subscriber, granted to the Log360
   collector

**Organization scope** shows those five plus:

* `random_id` — a suffix for the project ID, because project IDs are globally
  unique across all of Google Cloud and a plain name is usually taken
* `google_project` — the central logging project
* `google_project_service` — Pub/Sub and Logging APIs enabled on it
* and `google_logging_organization_sink` in place of the project sink

**Nothing should be marked for change or destruction.** If anything is, stop and
contact Log360 support — this module only ever adds.

Every IAM change uses the additive `*_iam_member` resource. Nothing replaces an
existing policy, so the publisher grants your other sinks depend on are left
exactly as they are.

## Apply

```bash
terraform apply
```

Type `yes` when prompted. Project scope takes under a minute; organization scope
takes two or three, because creating a project and enabling APIs is slower.

**If it fails on the sink**, you are missing `logging.configWriter` at that
scope.

**If it fails on the project**, you are missing
`resourcemanager.projectCreator` on the organization, or the billing account ID
is wrong or not one you can attach.

**If it fails on a grant**, you have `pubsub.admin` missing, or a custom role
without `setIamPolicy`. This one matters: the topic and sink would exist and the
publisher grant would not, which looks correct and delivers nothing.

## Check that logs are arriving

See which filter Terraform used, and where things ended up:

```bash
terraform output sink_filter
terraform output logging_project
terraform output sink_scope
```

Paste the filter into Logs Explorer to confirm it returns entries. If it returns
nothing there, it will return nothing here.

Then pull a few messages:

```bash
eval $(terraform output -raw verify)
```

Messages coming back means the pipeline works end to end: the filter matches,
the sink routes, the publisher grant is in place, and the subscription is
readable.

**Nothing came back?** Give it a minute — audit logs can lag. If it stays empty,
the cause is almost always one of the opt-in sources from earlier, or a missing
publisher grant:

```bash
terraform output sink_writer_identity
gcloud pubsub topics get-iam-policy $(terraform output -raw topic)
```

That identity should appear under `roles/pubsub.publisher`.

## Finish in Log360

```bash
terraform output subscription
```

Copy that full path and paste it into the **Subscription** field in Log360, then
click **Add**.

Log360 verifies it can read the subscription before saving, so you will know
immediately if something is wrong.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Collection starts within a minute. Each source shows when it last delivered and
alerts you if it stops — worth knowing, because Google Cloud raises no error if
a sink is deleted or a binding is revoked. A gap in arrivals is the only signal.

**To remove everything later:**

```bash
terraform destroy
```

Removing the account in Log360 stops collection but does not delete these
resources — they stay in your project and keep costing you until you destroy
them.

On organization scope, `destroy` also **deletes the logging project it
created**. If you have since put anything else in that project, remove it from
Terraform state first rather than destroying it.

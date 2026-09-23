# log360-gcp

Terraform module that provisions the Pub/Sub pipeline Log360 Cloud reads from.

You apply it with your own credentials. **Log360 is never given write access on
this path**, and the only permission it holds afterwards is
`roles/pubsub.subscriber` on the one subscription this module creates.

## Use

Set **exactly one** of `project_id` or `org_id`. That choice is the scope.

### Project scope

```hcl
project_id                = "acme-prod"
collector_service_account = "log360-collector@acme-prod.iam.gserviceaccount.com"
sources                   = ["audit_activity", "audit_system_event", "firewall"]
```

Sink, topic and subscription are all created in that project, and the sink
covers that project only. Projects created later are not included, and nothing
reports that it has gone stale.

### Organization scope

```hcl
org_id                    = "123456789012"
billing_account           = "01ABCD-2345EF-6789GH"
collector_service_account = "log360-collector@acme-prod.iam.gserviceaccount.com"
sources                   = ["audit_activity", "audit_system_event", "firewall"]
```

Creates a central logging project, puts the topic and subscription in it, and
creates an aggregated sink at the organization covering every project beneath —
including ones created later.

The sink is **non-intercepting**: each project's own `_Default` sink keeps
working and its logs stay searchable in that project. We add a route, we do not
divert one.

This path creates a project, so it additionally needs
`resourcemanager.projectCreator` on the organization and a billing account you
can attach. That is a considerably larger permission than everything else here.
If it is not available, create the project yourself and use `project_id`.

### Running it

```
cd gcp-poc-terraform
# edit terraform.tfvars
terraform init
terraform plan      # matches the plan shown in Log360 exactly
terraform apply
```

Then paste the `subscription` output into Log360 Cloud.

The provider block goes in your root module, not here:

```hcl
provider "google" {
  # Credentials come from your own session:
  #   gcloud auth application-default login
}
```

## What it creates

| # | Resource | Why it is in this order |
|---|---|---|
| 1 | Pub/Sub topic | the sink needs a destination that already exists |
| 2 | Log sink | returns a writer identity, which step 3 needs |
| 3 | Publisher grant on the topic | to the sink's writer identity |
| 4 | Pull subscription | ours alone |
| 5 | Subscriber grant on the subscription | the one permission Log360 keeps |

Step 3 is the one people miss when doing this by hand. GCP creates the sink's
writer identity with **no permissions at all**, so without that grant the
pipeline is configured correctly, looks right in the console, and delivers
nothing — with no error anywhere.

## Permissions needed to apply

| Role | On |
|---|---|
| `roles/logging.configWriter` | the organization or project you are covering |
| `roles/pubsub.admin` | `project_id` |

`pubsub.admin` is broader than needed. A custom role with
`pubsub.topics.create`, `pubsub.subscriptions.create`,
`pubsub.topics.setIamPolicy` and `pubsub.subscriptions.setIamPolicy` is
sufficient. The `setIamPolicy` permissions are the ones usually forgotten, and
without them the topic and sink are created and the publisher grant fails.

## Sink scope

An organization or folder sink with `include_children` is the only
configuration that does not go stale — projects created later are covered with
no re-onboarding, and nothing reports a project sink having gone out of date.

Use `scope = "project"` when organization access is unavailable, and accept
that new projects need onboarding again.

## Sources that can deliver nothing

Three are opt-in inside GCP, and a sink cannot enable them:

| Source | Prerequisite |
|---|---|
| `dns` | query logging enabled per VPC network |
| `nat` | per-gateway logging set to `ALL` or `TRANSLATIONS_ONLY`, not `ERRORS_ONLY` |
| `firewall` | per-rule logging opt-in |

Before expecting data, run the `sink_filter` output in Logs Explorer. If it
returns nothing there, it will return nothing here.

`scc_threat_findings` needs *Log findings to Logging* enabled in Continuous
Exports, and even then only Event Threat Detection and Container Threat
Detection findings reach Cloud Logging. Security Health Analytics, posture and
toxic-combination findings need the SCC notification path, which this module
does not cover.

## Cost

`audit_data_access` is excluded by default and is frequently larger than every
other source combined. Charges land on your account, not Log360's: ingestion,
Pub/Sub delivery and storage, plus egress when the collector pulls from outside
Google Cloud.

Removing a source from `sources` and re-applying rewrites the sink filter, so
the data stops at the source rather than being dropped after you have paid to
move it.

## Changing sources later

Edit `sources` and re-apply. Expect a short window where some entries arrive
twice — the new filter takes effect before the old sink stops. Duplicates are
removed on ingestion using `insertId`, timestamp and log name. Sequencing it the
other way would lose entries instead, which cannot be recovered.

## IAM safety

Every IAM resource here is `*_iam_member`, which appends. `_iam_binding` and
`_iam_policy` are authoritative: they replace the entire policy on the topic or
subscription and would silently strip the publisher grants your other sinks
depend on.

The same distinction applies on the command line — `add-iam-policy-binding`,
never `set-iam-policy`.

## Uninstall

```
terraform destroy
```

Removing the account in Log360 stops collection but does **not** remove these
resources. They stay in your project and keep costing you until you destroy
them.

## Existing pipelines

If a sink already routes these logs to Pub/Sub, running this module creates a
second one. GCP places no constraint on overlap: two sinks matching one entry
into one topic publish it **twice**, as separate messages with different
`messageId`s, billed twice, and nothing warns you.

Check first:

```
gcloud logging sinks list
gcloud logging sinks list --organization=YOUR_ORG_ID
```

Aggregated sinks are invisible from a project's own Log Router page, so the
second command matters even if the first looks empty.

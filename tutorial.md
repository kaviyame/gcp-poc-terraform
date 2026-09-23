# Set up GCP log collection for Log360 Cloud

<walkthrough-tutorial-duration duration="8"></walkthrough-tutorial-duration>

This creates a log sink, a Pub/Sub topic and a pull subscription in your Google
Cloud.

You run every command, with your own credentials. Log360 is never given write
access. When this finishes, the only thing it can do is read one subscription.

## Choose your scope

**Organization** — one aggregated sink covers every project beneath it,
including ones created after today. A small logging project is created to hold
the topic and subscription. The sink is non-intercepting, so each project's own
`_Default` sink keeps working and its logs stay searchable where they are.

Needs, on the organization: Logs Configuration Writer, Project Creator, and a
billing account you can attach.

**Project** — sink, topic and subscription all in one project you name. No
organization permission needed. Projects created later are not covered, and
nothing reports that it has gone stale.

Needs, on that project: Logs Configuration Writer and Pub/Sub Admin.

Find your IDs:

```bash
gcloud organizations list && gcloud billing accounts list
```

## Prepare the session

Cloud Shell no longer ships with Terraform:

```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list && sudo apt update && sudo apt install -y terraform
```

Then point the session at a project you own, which is how the provider
authenticates:

```bash
gcloud config set project YOUR_PROJECT_ID
```

## Set your values

```bash
cloudshell edit terraform.tfvars
```

Paste the block Log360 gave you, or edit it in place. Set **exactly one** of
`project_id` and `org_id` — both, or neither, stops the plan with a message
saying so.

`collector_service_account` is optional. Leave it out and the pipeline is still
built; you add the grant afterwards using the command in the output.

Two things about `sources`, each of which becomes one clause in the sink filter:

* `audit_data_access` is off by default and is often larger than everything else
  combined.
* `dns`, `nat` and `firewall` are opt-in inside Google Cloud and a sink cannot
  enable them. If query logging is off, a NAT gateway is on `ERRORS_ONLY`, or
  firewall rules have logging disabled, this provisions cleanly and stays empty.

Save with `Ctrl+S`.

## What each source routes

The name you put in `sources` becomes one clause in the sink filter. Paste any
of these into Logs Explorer to see exactly what it will match.

* `audit_activity` — `logName:"cloudaudit.googleapis.com%2Factivity"`
* `audit_data_access` — `logName:"cloudaudit.googleapis.com%2Fdata_access"`
* `audit_system_event` — `logName:"cloudaudit.googleapis.com%2Fsystem_event"`
* `audit_policy` — `logName:"cloudaudit.googleapis.com%2Fpolicy"`
* `firewall` — `logName:"compute.googleapis.com%2Ffirewall"`
* `nat` — `logName:"compute.googleapis.com%2Fnat"`
* `dns` — `logName:"dns.googleapis.com%2Fdns_queries"`
* `load_balancer` — `resource.type=("http_load_balancer" OR "internal_http_lb_rule")`
* `load_balancer_regional` — `logName:"loadbalancing.googleapis.com%2Fexternal_regional_requests"`
* `scc_threat_findings` — `resource.type="threat_detector"`

The four audit streams are separate on purpose. The broader
`logName:"cloudaudit.googleapis.com"` would match all of them, including Data
Access, which is often larger than everything else combined and cannot then be
turned off without rewriting the filter.

Load balancer is the one source keyed on `resource.type` rather than `logName`.
Its log ID is the bare word `requests`, which collides across products.

Security Command Center is keyed on `resource.type` too. Findings are not in
Cloud Logging by default — they arrive only when *Log findings to Logging* is
enabled in Continuous Exports, and even then only Event Threat Detection and
Container Threat Detection findings. There is no log named
`securitycenter.googleapis.com`; SCC's own API activity is already covered by
`audit_activity`.

The `%2F` is percent-encoded on purpose. Writing it as `/` matches zero entries
and reports no error.

## Plan and apply

```bash
terraform init && terraform plan
```

Expect **five resources to add** for project scope, or nine for organization
scope, which also creates the project and enables its APIs.

Nothing should be marked for change or destruction. If anything is, stop and
contact Log360 support — this only ever adds. Every IAM change is additive, so
the grants your other sinks depend on are untouched.

```bash
terraform apply
```

If it fails on the sink you are missing Logs Configuration Writer; on the
project, Project Creator or the billing account; on a grant, Pub/Sub Admin.

## Check it works, then finish

```bash
eval $(terraform output -raw verify)
```

Messages coming back means the whole chain works — filter, sink, publisher
grant, subscription.

Nothing? Wait a minute for audit logs to catch up, then check the filter itself
in Logs Explorer:

```bash
terraform output sink_filter
```

Then copy the subscription into Log360:

```bash
terraform output subscription
```

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Collection starts within a minute.

`terraform destroy` removes everything. Removing the account in Log360 does not
— these resources stay and keep costing you. On organization scope, `destroy`
also deletes the logging project it created.

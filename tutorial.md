# Set up GCP log collection for Log360 Cloud

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

This creates the pipeline Log360 reads from: a log sink, a Pub/Sub topic, a pull
subscription, and the two IAM grants that connect them.

You run every command here, with your own credentials. Log360 is not given write
access to your Google Cloud at any point.

## Before you start

You need these roles. Check now — the apply fails at the end otherwise.

| Role | On |
| --- | --- |
| Logs Configuration Writer | the organization, folder or project the sink covers |
| Pub/Sub Admin | the project that will hold the topic |

Confirm which account this session is using:

```bash
gcloud auth list
```

Click **Next** when you are ready.

## Set your values

The file `terraform.tfvars` is open in the editor.

<walkthrough-editor-open-file filePath="terraform.tfvars">Open terraform.tfvars</walkthrough-editor-open-file>

Paste the block Log360 gave you, replacing what is there. It contains your
project, your sink scope, the log sources you selected, and the service account
Log360 will read with.

Save with `Ctrl+S`, then click **Next**.

## Review the plan

```bash
terraform init
terraform plan
```

The plan should show **five resources to add** and nothing to change or destroy:

1. `google_pubsub_topic` — created first, because the sink needs a destination
   that already exists
2. A log sink — organization, folder or project, depending on your scope
3. `google_pubsub_topic_iam_member` — publisher, granted to the sink's writer
   identity
4. `google_pubsub_subscription` — read only by Log360
5. `google_pubsub_subscription_iam_member` — subscriber, granted to the Log360
   collector

If the plan shows anything being destroyed, stop and tell Log360 support. It
should only ever add.

Every IAM change here is additive. Nothing replaces an existing policy, so the
publisher grants your other sinks depend on are untouched.

## Apply

```bash
terraform apply
```

Type `yes` when prompted. It takes under a minute.

If it fails on the sink, you are missing Logs Configuration Writer at that
scope. If it fails on the topic or a grant, you are missing Pub/Sub Admin, or a
custom role without `setIamPolicy`.

## Check that logs are arriving

Print the filter Terraform used and try it in Logs Explorer:

```bash
terraform output sink_filter
```

Then pull a few messages:

```bash
eval $(terraform output -raw verify)
```

Messages coming back means the pipeline works end to end.

**Nothing came back?** Three sources are opt-in inside Google Cloud and a sink
cannot enable them. If you selected Cloud DNS, Cloud NAT or Firewall, check that
query logging is on for your VPC networks, that NAT gateways are set to `ALL` or
`TRANSLATIONS_ONLY` rather than `ERRORS_ONLY`, and that firewall rules have
logging enabled.

## Finish in Log360

```bash
terraform output subscription
```

Copy that value and paste it into the **Subscription** field in Log360, then
click **Add**.

Log360 checks it can read the subscription before saving, so you will know
immediately if something is wrong.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Collection starts within a minute. Each source shows when it last delivered, and
alerts you if it stops.

To remove all of this later, run `terraform destroy` from this directory.
Removing the account in Log360 stops collection but does not delete these
resources.

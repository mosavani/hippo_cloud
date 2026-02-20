# Observability: Logging and Monitoring

Cloud Logging and Cloud Monitoring are enabled by default on the cluster — no extra Terraform changes needed. The GKE logging agent on each node automatically captures stdout/stderr from every container and ships it to Cloud Logging.

---

## What you get out of the box

**Logs — automatic**

Any app writing to stdout/stderr is captured without any changes. View them in:
- **Cloud Logging → Logs Explorer** — filter by namespace, pod, or container
- **GKE → Workloads → your deployment → Logs tab** — directly from the GKE console

**Metrics — partial**

| Metric type | Available | Where |
|---|---|---|
| CPU, memory, restarts per pod | Yes, automatic | GKE → Workloads → your deployment |
| HTTP request count, latency | Only with GKE Ingress/Load Balancer | Cloud Monitoring |
| Custom app metrics (queue depth, error rates, etc.) | No — needs Google Managed Prometheus | Requires extra setup |

---

## Option A — Cloud Monitoring dashboard (no extra infra)

The simplest path: combine log-based metrics and system metrics into a single Cloud Monitoring dashboard with an embedded log panel.

### Step 1 — Create a log-based metric for app errors

In **Cloud Logging → Log-based metrics → Create metric**, use this filter:

```
resource.type="k8s_container"
resource.labels.cluster_name="hippo-dev-cluster"
severity>=ERROR
```

Name it `app_error_count`. This converts log entries into a countable metric you can chart alongside system metrics.

### Step 2 — Build a Cloud Monitoring dashboard

Go to **Cloud Monitoring → Dashboards → Create dashboard** and add these widgets:

| Widget type | Metric | What it shows |
|---|---|---|
| Line chart | `kubernetes.io/container/cpu/core_usage_time` | CPU usage per pod |
| Line chart | `kubernetes.io/container/memory/used_bytes` | Memory usage per pod |
| Line chart | `kubernetes.io/container/restart_count` | Crash loops / restarts |
| Line chart | `logging.googleapis.com/user/app_error_count` | Log-based error count |
| Logs panel | Filter by namespace/pod | Live log tail |

The **Logs panel widget** embeds a live log stream directly inside the dashboard so you see metrics charts and logs in one view.

```
┌─────────────────────────────────────────┐
│  hippo-dev dashboard                    │
├──────────────┬──────────────────────────┤
│ CPU (line)   │ Memory (line)            │
├──────────────┼──────────────────────────┤
│ Restarts     │ Error count (log metric) │
├──────────────┴──────────────────────────┤
│ Logs panel (live tail, filterable)      │
└─────────────────────────────────────────┘
```

### Step 3 — Set up an alert policy

In **Cloud Monitoring → Alerting → Create policy**:

```
Metric:    logging.googleapis.com/user/app_error_count
Condition: > 5 errors in a 5-minute window
Notify:    email / Slack / PagerDuty
```

---

## When to consider Google Managed Prometheus (GMP)

Option A covers system metrics and log-derived metrics. Enable GMP when you need:

- Custom app metrics (e.g. request latency histograms, queue depth, business counters)
- PromQL queries
- Grafana dashboards with logs + metrics side by side

GMP is enabled by adding one block to the GKE module — see the GKE module variables for `enable_managed_prometheus`. Cost is ~$0.15/MiB ingested beyond the free tier.

---

## No Terraform needed for Option A

The dashboard, log-based metrics, and alert policies are all configured in the GCP console. If you want to manage them as code later, Cloud Monitoring supports JSON dashboard exports that can be checked into the repo under `docs/dashboards/`.

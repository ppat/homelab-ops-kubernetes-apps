# Example Workflows

Reference n8n workflow exports for this module's day-one integrations. These are **not**
auto-imported by GitOps — workflows live in n8n's Postgres database, not the filesystem, so
importing them is a one-time, manual, not-GitOps-able bootstrap step (same category as OpenClaw's
WhatsApp QR pairing). Re-running the import is safe (it upserts by workflow ID) but will overwrite
any in-UI edits made to these specific workflows.

| File | Purpose |
| ---- | ------- |
| `alertmanager-receiver.json` | Alertmanager webhook → dedup on `status: firing` → one-line LiteLLM (`openai/gpt-5-nano`) summary → relay to OpenClaw's `/hooks/agent` → WhatsApp |
| `notify-subworkflow.json` | Shared "Notify" sub-workflow (`Execute Workflow` target) — fans out a `subject`/`message` pair to Maddy SMTP and OpenClaw |
| `media-downloaded-notify.json` | Example Radarr/Sonarr "downloaded" webhook (header-auth) → builds a notify payload → calls the shared Notify sub-workflow |

## Importing

After the module is deployed and the owner login is provisioned:

```bash
kubectl cp ./apps/subsystems/ai/n8n/workflows/ n8n/<n8n-pod>:/tmp/workflows -c n8n
kubectl exec -n n8n deploy/n8n -- n8n import:workflow --separate --input=/tmp/workflows
```

Import `notify-subworkflow.json` first — `media-downloaded-notify.json` references it by workflow
name via an `Execute Workflow` node, which n8n resolves post-import in the UI.

Both pre-seeded credentials referenced by these workflows (LiteLLM Bearer, Maddy SMTP) come from
`N8N_CREDENTIALS_OVERWRITE_DATA` (see the module's `secrets.yaml`) — no manual credential setup is
required, only the workflow import above.

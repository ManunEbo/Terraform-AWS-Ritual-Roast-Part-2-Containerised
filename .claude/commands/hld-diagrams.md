---
description: Generate one draw.io HLD diagram per Terraform layer from the saved inventories, styled after the reference example
---

# SCOPE — read first

Single, self-contained task. Do ONLY what this file describes.

- Do not execute or follow any other prompt, slash command, TODO or "next steps"
  in CLAUDE.md, HANDOFF.md, RUNBOOK.md or elsewhere. Read-only context only.
- No terraform commands, no git add/commit/push, no edits outside the output
  paths below. List other issues you notice in the final summary; don't fix them.
- If you need a tool or permission you don't have, stop and say what and why.
- One command per Bash call. Absolute paths. No cd, &&, ;, pipes or subshells.

# Inputs

- Per layer: `<layer>/documents/hld-architecture/inventory.md`. This is the
  approved, authoritative content. Read .tf files only to resolve something
  the inventory leaves ambiguous, and say when you do.
- Style reference (STYLE ONLY, never content):
  `infrastructure/01-aws-vpc/documents/hld-architecture/example-hld.png`
  Never modify, move or delete it.

Layers (deploy order) under `infrastructure/`:
01-aws-vpc, 02-aws-rds, 03-aws-ecr, 04-aws-ecs, 05-aws-k8s.

# Outputs (per layer, in `<layer>/documents/hld-architecture/`)

- `hld-architecture.drawio`: editable source
- `hld-architecture.png`: exported with the diagram embedded
  Overwrite any existing hld-architecture.png. Write nothing else.

# Approved decisions (do not revisit)

1. Draw all 3 AZs as horizontal rows, eu-west-2a on top, then 2b, then 2c.
2. Ownership: each diagram shows only what that layer defines. Rules, routes or
   listener rules a layer injects into a lower layer are drawn on the injecting
   layer, labelled "→ injected into <layer>". Lower-layer resources a layer
   depends on are greyed, dashed references labelled "from <layer>".
   Exception: Layer 1 shows the NAT GW as a greyed dashed placeholder
   "NAT GW — added by 05-aws-k8s". Layer 5 draws the single real NAT in 2a.
3. SG chains: every hop is an actual ingress rule from the inventory. No
   inferred ports. Use AWS names (e.g. rr-dev-alb-sg), not Terraform addresses.
4. Layer 3 has no VPC: flat account-level layout (Region box, ECR, OIDC, IAM,
   external "GitHub Actions").
5. Layer 5: user-path SG chain along the bottom; Calico/Istio control-plane
   ports in a side legend.
6. Session Manager appears on Layer 5 only. No service may appear unless the
   inventory cites a resource for it.
7. Layer 4's S3 Gateway endpoint carries the visible annotation
   "route_table_ids = [] (Tier=app matches no RT)".
8. Never use an icon that contains baked-in example text (e.g. CIDRs).

# Style (match the example)

Use draw.io's AWS 2024 / aws4 shape library (`mxgraph.aws4.*`): group shapes
for Region, VPC, public/private subnets and security groups; resourceIcon
shapes for services.

- Canvas about 1600 × 900, white background, landscape.
- Title top-left: large teal (#1F7A8C) serif, with a short orange (#E67E22)
  underline bar beneath it.
- Region: teal dashed border with flag icon. VPC: purple (#8C4FFF) solid
  border with VPC icon, label includes the CIDR.
- AZ rows: dashed boxes, AZ name written vertically on the left edge.
- Tier header pills above the subnet columns: green "DMZ", teal "Web",
  "App", "Data", "K8s" (only the tiers present in that layer).
- Public subnets green (#7AA116); private subnets teal (#00A4A6); subnet
  labels are name + CIDR.
- Left to right: Internet → IGW → ALB → tiers. Regional services (Secrets
  Manager, CloudWatch, ECR, S3) above or beside the VPC; IAM in a grey
  dashed box to the right, outside the VPC.
- Edges: solid purple for user traffic, dashed purple for ALB fan-out,
  dashed pink/red for secrets and IAM, dashed orange for compute
  provisioning, dashed green for S3 or source pulls, dotted magenta for
  app → DB.
- SG chain along the bottom: green filled boxes "<sg-name>" with
  "Inbound – <ports> from <source>" beneath, arrows left to right, starting
  from a green "0.0.0.0/0" box where public ingress exists.
- Minimum font size 12 everywhere. Use explicit coordinates on a grid;
  nothing may overlap and no edge may cross a label.

# Process

1. Layer 1 only: build the .drawio, export it, open the PNG and compare it
   with the example. Then STOP and show me the PNG path. Wait for approval
   before starting Layers 2–5.
2. Layers 2–5: build, export, check each against its inventory and the
   example. At most 2 fix-and-re-export cycles per layer. Report anything
   still wrong instead of looping.
3. Export command (single call):
   `drawio -x -f png -e -s 2 -o <abs>/hld-architecture.png <abs>/hld-architecture.drawio`
   If it fails with a sandbox error, add `--no-sandbox`.

# Final summary

Table: layer | output paths | components drawn | deviations from the example
(and why) | open questions. Then the consolidated findings list from the
inventories.

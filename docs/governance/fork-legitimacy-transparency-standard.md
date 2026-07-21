# Fork Legitimacy Transparency Standard

## Purpose
Define a minimum public evidence packet for contentious fork events so legitimacy assessment is inspectable and reproducible.

## Required Public Packet
1. Onchain objective state:
- mandate snapshot
- fork threshold and realized support weight
- branch lifecycle and active status
2. Governance continuity state:
- governance handoff status
- pending governance status
- branch governor address
3. Treasury migration state:
- ETH transfer result
- registered ERC20 migration result
4. Timeline and decision log:
- first detection timestamp
- public notice timestamps
- final branch-legitimacy statement

## Reproducibility Requirement
Each packet must include:
- command transcript or command list
- commit SHA
- chain ID and block range used

## Publication Requirement
- Packet must be published in-repo under docs/operations/drills/runs or a dedicated incident folder.
- External witness statements must be attached for production incidents.

## Tooling
Use script:
- scripts/export-fork-legitimacy-report.ts

This script generates machine-readable and markdown-friendly evidence outputs for each mandate/fork event.

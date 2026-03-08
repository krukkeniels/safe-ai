#!/usr/bin/env bash
# safe-ai Enterprise Risk Assessment
# Interactive wizard that generates a tailored risk report and configuration
# Based on docs/enterprise-risk-mapping.md
set -euo pipefail

# ─── Colors & Formatting ─────────────────────────────────────────────────────

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Helper Functions ─────────────────────────────────────────────────────────

print_header() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${BOLD}  $1${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
}

print_question() {
  echo -e "${BOLD}$1${RESET}"
  echo ""
}

# ask_single VARNAME "Question" "label1:value1" "label2:value2" ...
ask_single() {
  local varname="$1"; shift
  local question="$1"; shift
  local options=("$@")
  local count=${#options[@]}

  print_question "$question"

  local i=1
  for opt in "${options[@]}"; do
    local label="${opt%%:*}"
    echo -e "  ${BOLD}${i})${RESET} ${label}"
    i=$((i + 1))
  done
  echo ""

  while true; do
    read -rp "  Select [1-${count}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
      local selected="${options[$((choice - 1))]}"
      local value="${selected##*:}"
      printf -v "$varname" '%s' "$value"
      echo -e "  ${DIM}→ ${selected%%:*}${RESET}"
      echo ""
      return 0
    fi
    echo -e "  ${RED}Invalid choice. Enter a number between 1 and ${count}.${RESET}"
  done
}

# ask_multi VARNAME "Question" "label1:value1" "label2:value2" ...
ask_multi() {
  local varname="$1"; shift
  local question="$1"; shift
  local options=("$@")
  local count=${#options[@]}

  print_question "$question"

  local i=1
  for opt in "${options[@]}"; do
    local label="${opt%%:*}"
    echo -e "  ${BOLD}${i})${RESET} ${label}"
    i=$((i + 1))
  done
  echo ""
  echo -e "  ${DIM}Enter numbers separated by spaces (e.g., 1 3)${RESET}"

  while true; do
    read -rp "  Select: " -a choices
    if [ ${#choices[@]} -eq 0 ]; then
      echo -e "  ${RED}Select at least one option.${RESET}"
      continue
    fi

    local valid=true
    local values=()
    local labels=()
    for c in "${choices[@]}"; do
      if [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "$count" ]; then
        local selected="${options[$((c - 1))]}"
        values+=("${selected##*:}")
        labels+=("${selected%%:*}")
      else
        echo -e "  ${RED}Invalid: ${c}. Enter numbers between 1 and ${count}.${RESET}"
        valid=false
        break
      fi
    done

    if $valid; then
      local joined
      joined=$(IFS=,; echo "${values[*]}")
      printf -v "$varname" '%s' "$joined"
      echo -e "  ${DIM}→ $(IFS=', '; echo "${labels[*]}")${RESET}"
      echo ""
      return 0
    fi
  done
}

# ask_freetext VARNAME "Question" "default"
ask_freetext() {
  local varname="$1"
  local question="$2"
  local default="${3:-}"

  print_question "$question"
  if [ -n "$default" ]; then
    read -rp "  Enter value [${default}]: " answer
    answer="${answer:-$default}"
  else
    read -rp "  Enter value: " answer
  fi
  printf -v "$varname" '%s' "$answer"
  echo -e "  ${DIM}→ ${answer}${RESET}"
  echo ""
}

contains() {
  local list="$1"
  local item="$2"
  [[ ",${list}," == *",${item},"* ]]
}

# ─── Banner ───────────────────────────────────────────────────────────────────

clear 2>/dev/null || true
echo ""
echo -e "${BOLD}┌─────────────────────────────────────────────┐${RESET}"
echo -e "${BOLD}│   safe-ai Enterprise Risk Assessment        │${RESET}"
echo -e "${BOLD}│                                             │${RESET}"
echo -e "${BOLD}│   This wizard will ask 16 questions about   │${RESET}"
echo -e "${BOLD}│   your environment and generate:            │${RESET}"
echo -e "${BOLD}│                                             │${RESET}"
echo -e "${BOLD}│   • A CISO-ready risk report (Markdown)     │${RESET}"
echo -e "${BOLD}│   • Tailored allowlist.yaml                 │${RESET}"
echo -e "${BOLD}│   • Recommended .env configuration          │${RESET}"
echo -e "${BOLD}│   • docker-compose.override.yaml            │${RESET}"
echo -e "${BOLD}│                                             │${RESET}"
echo -e "${BOLD}│   AI Coding Agent Risk Framework            │${RESET}"
echo -e "${BOLD}└─────────────────────────────────────────────┘${RESET}"
echo ""
echo -e "  ${DIM}Press Enter to begin...${RESET}"
read -r

# ─── Question 1: Platform ────────────────────────────────────────────────────

print_header "1/16 — Platform"
ask_single PLATFORM "What OS/runtime are your developers using?" \
  "Windows 11 + WSL2 + Docker Desktop:wsl2" \
  "Native Linux + Docker Engine:linux" \
  "macOS + Docker Desktop:macos"

# ─── Question 2: LLM Providers ───────────────────────────────────────────────

print_header "2/16 — LLM Access"
ask_multi LLM_PROVIDERS "How do you access LLM APIs? (select all that apply)" \
  "Direct cloud API (Anthropic, OpenAI, Google):cloud_direct" \
  "Enterprise gateway — Azure AI Foundry, AWS Bedrock, Google Vertex AI:gateway" \
  "Self-hosted / on-prem LLM (Ollama, vLLM, etc.):selfhosted"

# Follow-up: gateway domain
GATEWAY_DOMAIN=""
GATEWAY_TOKEN_PLACEHOLDER=""
if contains "$LLM_PROVIDERS" "gateway"; then
  echo -e "  ${DIM}Examples: your-resource.openai.azure.com (Azure), your-id.bedrock.us-east-1.amazonaws.com (AWS)${RESET}"
  echo ""
  ask_freetext GATEWAY_DOMAIN "Enter your enterprise gateway domain:"
  GATEWAY_TOKEN_PLACEHOLDER="<your-gateway-token-here>"
fi

# Follow-up: self-hosted domain
SELFHOSTED_DOMAIN=""
if contains "$LLM_PROVIDERS" "selfhosted"; then
  ask_freetext SELFHOSTED_DOMAIN "Enter your self-hosted LLM domain (e.g., llm.internal.corp.com):"
fi

# ─── Question 3: Data Classification ─────────────────────────────────────────

print_header "3/16 — Data Classification"
ask_multi DATA_CLASSES "What types of sensitive data exist in your codebase? (select all)" \
  "Export-controlled (ITAR/EAR):itar" \
  "Classified / restricted:classified" \
  "PII / GDPR-regulated personal data:pii" \
  "Proprietary IP / trade secrets:ip" \
  "No special classification:none"

# ─── Question 4: Code Sensitivity ────────────────────────────────────────────

print_header "4/16 — Code Sensitivity"
ask_single CODE_SENSITIVITY "How critical is preventing code from leaving your network?" \
  "Critical — must never leave the organization (air-gap required):critical" \
  "High — minimize exposure, enterprise gateway with zero-retention:high" \
  "Medium — acceptable with audit trail and approved providers:medium" \
  "Low — open source / public code, no concern:low"

# ─── Question 5: Web Access ──────────────────────────────────────────────────

print_header "5/16 — Web Access"
ask_single WEB_ACCESS "Should the AI agent access external documentation and web resources?" \
  "Yes — scoped to specific documentation sites:scoped" \
  "Yes — internal documentation only (Confluence, SharePoint, wiki):internal" \
  "No — LLM API only, no web access:deny"

# Follow-up: internal docs domain
INTERNAL_DOCS_DOMAIN=""
if [ "$WEB_ACCESS" = "internal" ]; then
  ask_freetext INTERNAL_DOCS_DOMAIN "Enter your internal documentation domain (e.g., wiki.corp.example.com):"
fi

# ─── Question 6: Package Registries ──────────────────────────────────────────

print_header "6/16 — Package Registries"
ask_single PACKAGE_STRATEGY "How should package installation (npm, pip) work?" \
  "Direct access to public registries (npm, PyPI):public" \
  "Internal mirror (Artifactory, Nexus):mirror" \
  "Air-gapped — pre-installed packages only:airgap"

MIRROR_DOMAIN=""
if [ "$PACKAGE_STRATEGY" = "mirror" ]; then
  ask_freetext MIRROR_DOMAIN "Enter your internal mirror domain (e.g., nexus.corp.example.com):"
fi

# ─── Question 7: Developer Tools ─────────────────────────────────────────────

print_header "7/16 — Developer Tools"
ask_multi DEV_TOOLS "Which IDE/tools do developers need? (select all)" \
  "VS Code Remote-SSH:vscode" \
  "JetBrains Gateway:jetbrains" \
  "Cursor / Windsurf (AI-native IDE):cursor" \
  "Terminal / SSH only:terminal"

# ─── Question 8: AI Agents ───────────────────────────────────────────────────

print_header "8/16 — AI Coding Agents"
ask_multi AI_AGENTS "Which AI coding agents will be used? (select all)" \
  "Claude Code (Anthropic):claude" \
  "Codex CLI (OpenAI):codex" \
  "GitHub Copilot:copilot" \
  "Gemini CLI (Google):gemini" \
  "Other agent (Cline, Aider, Amp, etc.):custom"

# ─── Question 9: Action Approval & Output Control ───────────────────────────────────────

print_header "9/16 -- Action Approval & Output Control"
ask_single APPROVAL_GATES "How are destructive agent actions (delete, push, deploy) controlled?" \
  "Agent platform handles approval (Claude Code, Copilot built-in gates):agent_platform" \
  "Git branch protection + PR reviews:git_protection" \
  "No formal gates -- developers manage manually:manual" \
  "Not sure / not yet decided:undecided"

# ─── Question 10: Code Review ───────────────────────────────────────────────

print_header "10/16 -- Code Review"
ask_single CODE_REVIEW "How is agent-generated code reviewed before merge?" \
  "Mandatory PR review + SAST/DAST in CI:pr_sast" \
  "PR review required but no automated scanning:pr_only" \
  "Direct commit to main allowed:direct_commit" \
  "Not yet decided:undecided"

# ─── Question 11: Team Scale ────────────────────────────────────────────────

print_header "11/16 — Team Scale"
ask_single TEAM_SCALE "What is the team scale?" \
  "Single developer:single" \
  "Small team (2-10 developers):small" \
  "Large team (10+ developers):large" \
  "Multi-tenant (multiple teams, different requirements):multitenant"

# ─── Question 12: Compliance ─────────────────────────────────────────────────

print_header "12/16 — Compliance Frameworks"
ask_multi COMPLIANCE "Which compliance frameworks apply? (select all)" \
  "SOC 2:soc2" \
  "ISO 27001:iso27001" \
  "FedRAMP:fedramp" \
  "HIPAA:hipaa" \
  "GDPR:gdpr" \
  "CMMC / NIST 800-171:cmmc" \
  "SOX:sox" \
  "None:none"

# ─── Question 13: Agent Identity ─────────────────────────────────────────────

print_header "13/16 -- Agent Identity"
ask_single AGENT_IDENTITY "How are agent-generated commits identified?" \
  "Dedicated service account or bot user per agent:service_account" \
  "Co-author tags on commits:coauthor" \
  "Same git identity as the developer:same_identity" \
  "Not yet decided:undecided"

# ─── Question 14: Incident Response ─────────────────────────────────────────

print_header "14/16 -- Incident Response"
ask_single INCIDENT_RESPONSE "Do you have an incident response plan for AI agent compromise?" \
  "Documented plan with kill switch and forensics procedures:documented" \
  "General IR plan exists but not specific to AI agents:general" \
  "No plan yet:none"

# ─── Question 15: Audit Level ───────────────────────────────────────────────

print_header "15/16 — Audit Logging"
ask_single AUDIT_LEVEL "What level of audit logging is required?" \
  "Local logs sufficient:local" \
  "Central SIEM integration required:central" \
  "Tamper-evident / append-only logging required:tamper"

# ─── Question 16: Existing Infrastructure ────────────────────────────────────

print_header "16/16 — Existing Infrastructure"
ask_multi EXISTING_INFRA "What enterprise infrastructure do you already have? (select all)" \
  "Internal package mirror (Artifactory, Nexus):pkg_mirror" \
  "Enterprise API gateway:api_gateway" \
  "Central SIEM / logging platform (Splunk, ELK, etc.):siem" \
  "Identity provider (Azure AD / Entra ID, Okta):idp" \
  "None of these:none"

# ─── Decision Engine ─────────────────────────────────────────────────────────

print_header "Analyzing your environment..."

# Does code leave the organization?
CODE_LEAVES_ORG=false
if contains "$LLM_PROVIDERS" "cloud_direct"; then
  CODE_LEAVES_ORG=true
fi

# Risk level = data sensitivity x exposure
if contains "$DATA_CLASSES" "itar" || contains "$DATA_CLASSES" "classified"; then
  if $CODE_LEAVES_ORG; then
    RISK_LEVEL="CRITICAL"
    RISK_EMOJI="🔴"
  else
    RISK_LEVEL="HIGH"       # Sensitive data but code stays in-org
    RISK_EMOJI="🟡"
  fi
elif contains "$DATA_CLASSES" "pii" || contains "$DATA_CLASSES" "ip"; then
  if $CODE_LEAVES_ORG; then
    RISK_LEVEL="HIGH"
    RISK_EMOJI="🟡"
  else
    RISK_LEVEL="MEDIUM"     # IP/PII but self-hosted
    RISK_EMOJI="🟢"
  fi
elif [ "$CODE_SENSITIVITY" = "critical" ] || [ "$CODE_SENSITIVITY" = "high" ]; then
  RISK_LEVEL="HIGH"
  RISK_EMOJI="🟡"
else
  RISK_LEVEL="MEDIUM"
  RISK_EMOJI="🟢"
fi

# gVisor availability
USE_GVISOR=false
GVISOR_NOTE=""
if [ "$PLATFORM" = "linux" ]; then
  USE_GVISOR=true
  GVISOR_NOTE="gVisor (runsc) is available on native Linux. Run \`sudo ./scripts/install-gvisor.sh\` to install."
else
  GVISOR_NOTE="gVisor is NOT available on ${PLATFORM}. It requires a native Linux kernel. Docker Desktop runs containers in a lightweight VM that does not support registering custom OCI runtimes like runsc. Container-level hardening (seccomp, capabilities, read-only root) remains active."
fi

RUNTIME="runc"
$USE_GVISOR && RUNTIME="runsc"

# Logging
ENABLE_LOGGING=false
if [ "$AUDIT_LEVEL" != "local" ] || ! contains "$COMPLIANCE" "none"; then
  ENABLE_LOGGING=true
fi
# Also enable if risk is HIGH or CRITICAL
if [ "$RISK_LEVEL" = "HIGH" ] || [ "$RISK_LEVEL" = "CRITICAL" ]; then
  ENABLE_LOGGING=true
fi

# Build allowlist domains
DOMAINS=()

# LLM providers
if contains "$LLM_PROVIDERS" "cloud_direct"; then
  if contains "$AI_AGENTS" "claude"; then
    DOMAINS+=("api.anthropic.com")
  fi
  if contains "$AI_AGENTS" "codex"; then
    DOMAINS+=("api.openai.com")
  fi
  if contains "$AI_AGENTS" "copilot"; then
    DOMAINS+=("api.github.com")
    DOMAINS+=("copilot-proxy.githubusercontent.com")
  fi
  if contains "$AI_AGENTS" "gemini"; then
    DOMAINS+=("generativelanguage.googleapis.com")
  fi
  # If cloud_direct but no specific agent matched, ask the user
  if [ ${#DOMAINS[@]} -eq 0 ]; then
    echo -e "  ${YELLOW}You selected direct cloud API but no recognized agent was matched.${RESET}"
    ask_freetext CUSTOM_API_DOMAIN "Enter your LLM API domain (e.g., api.anthropic.com):"
    if [ -n "$CUSTOM_API_DOMAIN" ]; then
      DOMAINS+=("$CUSTOM_API_DOMAIN")
    fi
  fi
fi

if contains "$LLM_PROVIDERS" "gateway" && [ -n "$GATEWAY_DOMAIN" ]; then
  DOMAINS+=("$GATEWAY_DOMAIN")
fi

if contains "$LLM_PROVIDERS" "selfhosted" && [ -n "$SELFHOSTED_DOMAIN" ]; then
  DOMAINS+=("$SELFHOSTED_DOMAIN")
fi

# Code hosting (unless fully air-gapped)
if [ "$CODE_SENSITIVITY" != "critical" ]; then
  DOMAINS+=("github.com" "api.github.com")
fi

# Web access
if [ "$WEB_ACCESS" = "scoped" ]; then
  DOMAINS+=("stackoverflow.com" "docs.python.org" "developer.mozilla.org" "pkg.go.dev")
elif [ "$WEB_ACCESS" = "internal" ] && [ -n "$INTERNAL_DOCS_DOMAIN" ]; then
  DOMAINS+=("$INTERNAL_DOCS_DOMAIN")
fi

# Package registries
if [ "$PACKAGE_STRATEGY" = "public" ]; then
  DOMAINS+=("registry.npmjs.org" "pypi.org" "files.pythonhosted.org")
elif [ "$PACKAGE_STRATEGY" = "mirror" ] && [ -n "$MIRROR_DOMAIN" ]; then
  DOMAINS+=("$MIRROR_DOMAIN")
fi

# Deduplicate
UNIQUE_DOMAINS=()
declare -A seen_domains
for d in "${DOMAINS[@]}"; do
  if [ -z "${seen_domains[$d]:-}" ]; then
    UNIQUE_DOMAINS+=("$d")
    seen_domains[$d]=1
  fi
done
DOMAINS=("${UNIQUE_DOMAINS[@]}")

# Risk ratings for AI Coding Agent Requirements (R1-R12)
# Source: docs/security-requirements.md
declare -A RISK_COVERAGE
declare -A RISK_NOTES
declare -A RISK_LABELS

RISK_LABELS[R1]="Network Egress Control"
RISK_LABELS[R2]="Sandbox Isolation"
RISK_LABELS[R3]="Credential Separation"
RISK_LABELS[R4]="Action Approval & Output Control"
RISK_LABELS[R5]="Audit Logging"
RISK_LABELS[R6]="Workspace & Context Isolation"
RISK_LABELS[R7]="Resource Limits"
RISK_LABELS[R8]="Supply Chain Controls"
RISK_LABELS[R9]="Code Review Enforcement"
RISK_LABELS[R10]="Data Classification Policy"
RISK_LABELS[R11]="Agent Identity & Attribution"
RISK_LABELS[R12]="Incident Response"

# R1: Network Egress Control (Mandatory)
RISK_COVERAGE[R1]="MITIGATED"
RISK_NOTES[R1]="Docker internal:true network (no default gateway). DNS filtering blocks non-allowlisted domains. Squid ACLs enforce domain allowlist of ${#DOMAINS[@]} domains. Only ports 80/443 permitted."

# R2: Sandbox Isolation (Mandatory)
if $USE_GVISOR; then
  RISK_COVERAGE[R2]="MITIGATED"
  RISK_NOTES[R2]="gVisor intercepts syscalls in user-space. Combined with seccomp whitelist, cap_drop ALL, no-new-privileges, read-only root, and noexec tmpfs."
else
  RISK_COVERAGE[R2]="PARTIALLY"
  RISK_NOTES[R2]="Seccomp whitelist, cap_drop ALL, no-new-privileges, read-only root, noexec tmpfs. Without gVisor, kernel exploits in allowed syscalls remain a theoretical escape path."
fi

# R3: Credential Separation (Mandatory)
if [ -n "$GATEWAY_DOMAIN" ]; then
  RISK_COVERAGE[R3]="MITIGATED"
  RISK_NOTES[R3]="Gateway token injected at proxy layer -- never enters sandbox. Anti-spoofing strips sandbox-originated headers. SSH key-only auth with max 3 attempts."
else
  RISK_COVERAGE[R3]="PARTIALLY"
  RISK_NOTES[R3]="SSH key-only auth. No gateway token injection configured -- API tokens may be passed via environment variables visible to sandbox processes."
fi

# R4: Action Approval & Output Control (Mandatory)
case "$APPROVAL_GATES" in
  agent_platform)
    RISK_COVERAGE[R4]="PARTIALLY"
    RISK_NOTES[R4]="Agent platform provides built-in approval gates. safe-ai ships a git pre-push hook (config/git/pre-push). Note: safe-ai cannot verify that agent platform gates are active -- this is a trust boundary."
    ;;
  git_protection)
    RISK_COVERAGE[R4]="PARTIALLY"
    RISK_NOTES[R4]="Git branch protection prevents direct pushes to main. PR reviews required. Server-side branch protection is the strongest control -- it cannot be bypassed from inside the sandbox. safe-ai ships a pre-push hook as an additional soft gate."
    ;;
  manual|undecided)
    RISK_COVERAGE[R4]="MINIMAL"
    RISK_NOTES[R4]="No formal approval gates configured. safe-ai controls WHERE data goes (network allowlist) but cannot distinguish git push from git pull within an encrypted HTTPS tunnel. Approval must come from: (1) GitHub/GitLab branch protection (server-side, tamper-proof), (2) read-only deploy keys (allows clone, blocks push), or (3) agent platform built-in gates. safe-ai also ships a pre-push hook: cp config/git/pre-push .git/hooks/"
    ;;
esac

# R5: Audit Logging (Mandatory)
if $ENABLE_LOGGING; then
  RISK_COVERAGE[R5]="MITIGATED"
  RISK_NOTES[R5]="Structured JSON logging of all proxy requests (allowed and denied). Fluent Bit ships to Loki. Grafana dashboard with pre-built visualizations."
else
  RISK_COVERAGE[R5]="MINIMAL"
  RISK_NOTES[R5]="Audit logging not enabled. No visibility into proxy activity. Enable with: docker compose --profile logging up -d"
fi

# R6: Workspace & Context Isolation (Mandatory)
RISK_COVERAGE[R6]="MITIGATED"
RISK_NOTES[R6]="Workspace mounted as named volume at /workspace. Sandbox cannot access host filesystem. Read-only root prevents system modification. Agent has full R/W access to /workspace only."

# R7: Resource Limits (Mandatory)
RISK_COVERAGE[R7]="PARTIALLY"
RISK_NOTES[R7]="Memory (8GB), CPU (4 cores), PID (512) limits enforced via cgroups. No /workspace volume size limit (Docker limitation on ext4). No API call rate limiting at proxy level."

# R8: Supply Chain Controls (Conditional — mandatory when agents install packages or use MCP)
case "$PACKAGE_STRATEGY" in
  mirror)
    RISK_COVERAGE[R8]="MITIGATED"
    RISK_NOTES[R8]="Internal mirror with scanned packages. Read-only root prevents system modification. noexec /tmp blocks binary execution."
    ;;
  airgap)
    RISK_COVERAGE[R8]="MITIGATED"
    RISK_NOTES[R8]="Air-gapped -- no external package installation possible."
    ;;
  public)
    RISK_COVERAGE[R8]="PARTIALLY"
    RISK_NOTES[R8]="Public registries (npm, PyPI) are reachable. No per-package filtering. Malicious post-install scripts execute within sandbox. Use lock files with integrity hashes."
    ;;
esac

# R9: Code Review Enforcement (Recommended)
case "$CODE_REVIEW" in
  pr_sast)
    RISK_COVERAGE[R9]="MITIGATED"
    RISK_NOTES[R9]="PR-based workflow with mandatory review and automated SAST/DAST scanning. Agent commits tagged for identification."
    ;;
  pr_only)
    RISK_COVERAGE[R9]="PARTIALLY"
    RISK_NOTES[R9]="PR review required but no automated security scanning. Consider adding SAST/DAST in CI. 45% of AI-generated code contains security flaws (Veracode 2025)."
    ;;
  direct_commit|undecided)
    RISK_COVERAGE[R9]="MINIMAL"
    RISK_NOTES[R9]="No enforced code review for agent-generated code. Direct commits to main allowed. This is high-risk -- 45% of AI-generated code has flaws. Implement PR-based workflows."
    ;;
esac

# R10: Data Classification Policy (Mandatory)
if contains "$DATA_CLASSES" "none"; then
  RISK_COVERAGE[R10]="NOT_ADDRESSED"
  RISK_NOTES[R10]="No data classification concerns identified. Review if regulatory requirements apply to your use of AI coding agents."
elif contains "$DATA_CLASSES" "itar" || contains "$DATA_CLASSES" "classified"; then
  if ! $CODE_LEAVES_ORG; then
    RISK_COVERAGE[R10]="PARTIALLY"
    RISK_NOTES[R10]="Export-controlled/classified data identified. Self-hosted LLM keeps code in-org. Ensure per-compartment sandboxes for classified work."
  else
    RISK_COVERAGE[R10]="MINIMAL"
    RISK_NOTES[R10]="CRITICAL: Export-controlled/classified data with external LLM APIs. This may constitute an export violation. Use ONLY self-hosted LLM."
  fi
elif contains "$DATA_CLASSES" "pii"; then
  RISK_COVERAGE[R10]="PARTIALLY"
  RISK_NOTES[R10]="PII identified. Use EU-region API endpoints, execute DPAs with LLM providers, use synthetic test data. safe-ai does not scan for or redact PII."
else
  RISK_COVERAGE[R10]="PARTIALLY"
  RISK_NOTES[R10]="IP/trade secrets identified. Use enterprise LLM tiers with zero-retention agreements. Allowlist limits data destinations."
fi

# R11: Agent Identity & Attribution (Recommended)
case "$AGENT_IDENTITY" in
  service_account)
    RISK_COVERAGE[R11]="MITIGATED"
    RISK_NOTES[R11]="Dedicated service accounts distinguish agent actions from developer actions. Per-developer audit trails via SAFE_AI_HOSTNAME."
    ;;
  coauthor)
    RISK_COVERAGE[R11]="PARTIALLY"
    RISK_NOTES[R11]="Co-author tags identify agent involvement. Set SAFE_AI_HOSTNAME per developer for audit trail separation."
    ;;
  same_identity|undecided)
    RISK_COVERAGE[R11]="MINIMAL"
    RISK_NOTES[R11]="Agent commits are indistinguishable from developer commits. No audit trail separation. Configure git: git config user.name 'dev (via safe-ai)'"
    ;;
esac

# R12: Incident Response (Recommended)
case "$INCIDENT_RESPONSE" in
  documented)
    RISK_COVERAGE[R12]="MITIGATED"
    RISK_NOTES[R12]="Documented IR plan. safe-ai provides kill switch (make kill), workspace snapshots (make snapshot), and a runbook (docs/incident-response.md)."
    ;;
  general)
    RISK_COVERAGE[R12]="PARTIALLY"
    RISK_NOTES[R12]="General IR plan exists. Extend it for AI agents using docs/incident-response.md. Key commands: make kill (contain), make snapshot (preserve evidence)."
    ;;
  none)
    RISK_COVERAGE[R12]="MINIMAL"
    RISK_NOTES[R12]="No incident response plan. Create one using docs/incident-response.md as a starting point. At minimum: know how to run make kill and make snapshot."
    ;;
esac

# ─── Enterprise Scenario Detection ────────────────────────────────────────────
# Maps to scenarios in docs/security-requirements.md

SCENARIO=""
SCENARIO_NAME=""
SCENARIO_DESCRIPTION=""

if contains "$DATA_CLASSES" "itar" || contains "$DATA_CLASSES" "classified" || [ "$CODE_SENSITIVITY" = "critical" ]; then
  SCENARIO="defense"
  SCENARIO_NAME="Defense / Export-Controlled Code (Scenario 4)"
  SCENARIO_DESCRIPTION="ITAR/EAR-controlled or classified source code. Requires air-gapped configuration with self-hosted LLM only. Per-compartment sandboxes. No external domains."
elif contains "$COMPLIANCE" "hipaa" || (contains "$DATA_CLASSES" "pii" && (contains "$COMPLIANCE" "soc2" || contains "$COMPLIANCE" "gdpr")); then
  SCENARIO="regulated"
  SCENARIO_NAME="Regulated Financial / Healthcare (Scenario 3)"
  SCENARIO_DESCRIPTION="SOC 2, HIPAA, or GDPR compliance with PII. Requires central SIEM, tamper-evident logging, internal mirrors, and mandatory code review."
elif [ "$TEAM_SCALE" = "multitenant" ]; then
  SCENARIO="multitenant"
  SCENARIO_NAME="Multi-Tenant / Team Isolation (Scenario 6)"
  SCENARIO_DESCRIPTION="Multiple teams with different security requirements on shared infrastructure. Requires per-team allowlists, log segregation, and separate hosts per classification level."
elif contains "$DATA_CLASSES" "ip" || (contains "$COMPLIANCE" "soc2" && [ "$TEAM_SCALE" = "large" ]); then
  SCENARIO="enterprise_saas"
  SCENARIO_NAME="Enterprise SaaS Development (Scenario 2)"
  SCENARIO_DESCRIPTION="Commercial product with IP protection. Enterprise LLM gateway with zero-retention. Central SIEM. Internal package mirrors. Mandatory PR review."
elif contains "$DATA_CLASSES" "none" && [ "$CODE_SENSITIVITY" = "low" ]; then
  SCENARIO="opensource"
  SCENARIO_NAME="Open-Source Development (Scenario 1)"
  SCENARIO_DESCRIPTION="Public open-source projects. No sensitive data. Productivity is the priority. Local logs sufficient."
else
  SCENARIO="general"
  SCENARIO_NAME="General Enterprise Development"
  SCENARIO_DESCRIPTION="Standard enterprise development environment. Balance security controls with developer productivity."
fi

# Platform display name
case "$PLATFORM" in
  wsl2) PLATFORM_DISPLAY="Windows 11 + WSL2 + Docker Desktop" ;;
  linux) PLATFORM_DISPLAY="Native Linux + Docker Engine" ;;
  macos) PLATFORM_DISPLAY="macOS + Docker Desktop" ;;
  *) PLATFORM_DISPLAY="Unknown (${PLATFORM})" ;;
esac

# ─── Output Directory ────────────────────────────────────────────────────────

DATE_STAMP=$(date +%Y-%m-%d)
OUTPUT_DIR="risk-assessment-${DATE_STAMP}"
mkdir -p "$OUTPUT_DIR"

# ─── Generate allowlist.yaml ─────────────────────────────────────────────────

{
  echo "# Generated by safe-ai risk assessment on ${DATE_STAMP}"
  echo "# Risk level: ${RISK_LEVEL} | Platform: ${PLATFORM_DISPLAY}"
  echo "# Domains: ${#DOMAINS[@]}"
  echo "#"
  echo "# To use: cp this file to your safe-ai project root as allowlist.yaml"
  echo "# Or set SAFE_AI_ALLOWLIST=$(pwd)/${OUTPUT_DIR}/allowlist.yaml"
  echo ""
  echo "domains:"

  # Group domains by category with comments
  local_llm_domains=()
  local_code_domains=()
  local_web_domains=()
  local_pkg_domains=()
  local_other_domains=()

  for d in "${DOMAINS[@]}"; do
    case "$d" in
      api.anthropic.com|api.openai.com|generativelanguage.googleapis.com|copilot-proxy.githubusercontent.com)
        local_llm_domains+=("$d") ;;
      github.com|api.github.com)
        local_code_domains+=("$d") ;;
      stackoverflow.com|docs.python.org|developer.mozilla.org|pkg.go.dev)
        local_web_domains+=("$d") ;;
      registry.npmjs.org|pypi.org|files.pythonhosted.org)
        local_pkg_domains+=("$d") ;;
      *)
        local_other_domains+=("$d") ;;
    esac
  done

  if [ ${#local_llm_domains[@]} -gt 0 ]; then
    echo "  # LLM API providers"
    for d in "${local_llm_domains[@]}"; do echo "  - $d"; done
  fi
  if [ ${#local_other_domains[@]} -gt 0 ]; then
    echo "  # Enterprise / self-hosted"
    for d in "${local_other_domains[@]}"; do echo "  - $d"; done
  fi
  if [ ${#local_code_domains[@]} -gt 0 ]; then
    echo "  # Code hosting"
    for d in "${local_code_domains[@]}"; do echo "  - $d"; done
  fi
  if [ ${#local_web_domains[@]} -gt 0 ]; then
    echo "  # Documentation (web access)"
    for d in "${local_web_domains[@]}"; do echo "  - $d"; done
  fi
  if [ ${#local_pkg_domains[@]} -gt 0 ]; then
    echo "  # Package registries"
    for d in "${local_pkg_domains[@]}"; do echo "  - $d"; done
  fi
} > "${OUTPUT_DIR}/allowlist.yaml"

# ─── Generate .env ───────────────────────────────────────────────────────────

{
  echo "# Generated by safe-ai risk assessment on ${DATE_STAMP}"
  echo "# Risk level: ${RISK_LEVEL} | Platform: ${PLATFORM_DISPLAY}"
  echo ""
  echo "# ── Runtime ──────────────────────────────────────────────"
  if $USE_GVISOR; then
    echo "SAFE_AI_RUNTIME=runsc"
  else
    echo "SAFE_AI_RUNTIME=runc    # gVisor not available on ${PLATFORM}"
  fi
  echo ""
  echo "# ── SSH Access ───────────────────────────────────────────"
  echo "SAFE_AI_SSH_KEY=~/.ssh/id_ed25519.pub"
  echo "SAFE_AI_SSH_PORT=2222"
  echo ""
  echo "# ── Allowlist ────────────────────────────────────────────"
  echo "SAFE_AI_ALLOWLIST=./allowlist.yaml"
  echo "# SAFE_AI_DEFAULT_DOMAINS=    # Additional domains (comma-separated)"
  echo ""
  echo "# ── Resource Limits ──────────────────────────────────────"
  echo "SAFE_AI_SANDBOX_MEMORY=8g"
  echo "SAFE_AI_SANDBOX_CPUS=4"
  echo ""
  echo "# ── Audit Logging ────────────────────────────────────────"
  echo "SAFE_AI_HOSTNAME=$(hostname 2>/dev/null || echo 'enterprise-dev-01')"
  if [ "$AUDIT_LEVEL" = "central" ] || [ "$AUDIT_LEVEL" = "tamper" ]; then
    echo "# Set this to your central SIEM endpoint:"
    echo "# SAFE_AI_LOKI_URL=https://loki.corp.example.com:3100"
  else
    echo "# SAFE_AI_LOKI_URL=    # Set for central SIEM integration"
  fi
  echo "SAFE_AI_GRAFANA_PORT=3000"
  echo "SAFE_AI_GRAFANA_PASSWORD=changeme"
  echo ""
  echo "# ── Gateway (token injection) ────────────────────────────"
  if [ -n "$GATEWAY_DOMAIN" ]; then
    echo "SAFE_AI_GATEWAY_DOMAIN=${GATEWAY_DOMAIN}"
    echo "SAFE_AI_GATEWAY_TOKEN=${GATEWAY_TOKEN_PLACEHOLDER}"
  else
    echo "# SAFE_AI_GATEWAY_DOMAIN="
    echo "# SAFE_AI_GATEWAY_TOKEN="
  fi
} > "${OUTPUT_DIR}/.env"

# ─── Generate docker-compose.override.yaml ───────────────────────────────────

{
  echo "# Generated by safe-ai risk assessment on ${DATE_STAMP}"
  echo "# Risk level: ${RISK_LEVEL} | Platform: ${PLATFORM_DISPLAY}"
  echo "#"
  echo "# Copy to your safe-ai project root as docker-compose.override.yaml"
  echo ""
  echo "services:"
  echo "  sandbox:"
  echo "    volumes:"
  echo "      # Mount your project directory into the sandbox"
  echo "      # - /path/to/your/project:/workspace"
  if contains "$DEV_TOOLS" "vscode"; then
    echo "      - vscode-server:/home/dev/.vscode-server"
  fi
  if contains "$DEV_TOOLS" "jetbrains"; then
    echo "      - jetbrains-data:/home/dev/.cache/JetBrains"
  fi
  if contains "$DEV_TOOLS" "cursor"; then
    echo "      - cursor-server:/home/dev/.cursor-server"
  fi
  echo "    # environment:"
  echo "    #   - GIT_AUTHOR_NAME=Your Name"
  echo "    #   - GIT_AUTHOR_EMAIL=you@example.com"
} > "${OUTPUT_DIR}/docker-compose.override.yaml"

# ─── Generate Risk Report ────────────────────────────────────────────────────

risk_status_icon() {
  case "$1" in
    MITIGATED)     echo "🟢 Mitigated" ;;
    PARTIALLY)     echo "🟡 Partial" ;;
    MINIMAL)       echo "🔴 Minimal" ;;
    NOT_ADDRESSED) echo "⚪ N/A" ;;
  esac
}

# Build risks-you-accept list
ACCEPTED_RISKS=""

# Always present
ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🟡 **Workspace file access** — The AI agent has full read/write access to \`/workspace\`. It can delete, modify, or exfiltrate workspace files to allowlisted domains. **Mitigation:** Use git with pre-push hooks requiring human approval. Take workspace snapshots."

if contains "$LLM_PROVIDERS" "cloud_direct"; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🔴 **Encrypted API payloads** — Code sent to cloud LLM APIs (${DOMAINS[0]:-api providers}) is encrypted (HTTPS). safe-ai logs the domain and byte count but cannot inspect what data is sent. **Mitigation:** Use enterprise LLM tiers with zero-retention agreements. Consider self-hosted LLM for sensitive code."
fi

if ! $USE_GVISOR; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🟡 **No gVisor kernel isolation** — gVisor is not available on ${PLATFORM_DISPLAY}. Kernel exploits in allowed syscalls remain a theoretical container escape path. The seccomp whitelist, capability drops, and read-only root still provide strong isolation. **Mitigation:** Keep Docker Desktop and host OS updated. This is the primary remaining escape vector."
fi

if [ "$PACKAGE_STRATEGY" = "public" ]; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🟡 **Public package registries** — npm and PyPI are allowlisted. The AI agent could install malicious or typosquatted packages. Post-install scripts execute within the sandbox. **Mitigation:** Use an internal package mirror with vulnerability scanning. Enforce lock files with integrity hashes."
fi

if [ "$WEB_ACCESS" = "scoped" ]; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🟡 **Web search queries** — Requests to documentation sites may contain code snippets in URLs or search parameters. This is logged but the content is encrypted. **Mitigation:** Review audit logs for unusual request patterns to documentation domains."
fi

if contains "$DATA_CLASSES" "pii"; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🔴 **PII in code context** — Test fixtures, config files, and logs may contain PII that gets sent to LLM APIs as prompt context. safe-ai does not scan for or redact PII. **Mitigation:** Use synthetic test data. Execute DPAs with LLM providers. Use EU-region API endpoints if required."
fi

if contains "$DATA_CLASSES" "itar" && contains "$LLM_PROVIDERS" "cloud_direct"; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🔴 **CRITICAL: Export-controlled code to cloud APIs** — Sending ITAR/EAR-controlled code to external cloud APIs may constitute an export violation. safe-ai cannot prevent this for allowlisted domains. **Mitigation:** REMOVE cloud API domains from allowlist. Use ONLY self-hosted LLM."
fi

ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🟡 **Interpreted script execution** — While \`/tmp\` is mounted noexec, interpreted scripts (\`bash /tmp/script.sh\`, \`python3 /tmp/exploit.py\`) still execute. The noexec flag only blocks direct ELF binary execution. **Mitigation:** This is constrained by network isolation and seccomp — scripts cannot reach unauthorized destinations or use dangerous syscalls."

ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🟡 **memfd_create bypass** — The \`memfd_create\` syscall is allowed (required by some dev tools). It enables fileless execution by writing an ELF binary to anonymous memory and executing it, bypassing noexec restrictions. **Mitigation:** For high-security environments, consider blocking memfd_create in the seccomp profile if your tools don't require it."

if [ "$APPROVAL_GATES" = "manual" ] || [ "$APPROVAL_GATES" = "undecided" ]; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🔴 **Approval gates require org-level controls** — safe-ai cannot distinguish git push from git pull at the network layer (both are encrypted HTTPS tunnels to github.com:443). The agent can push code if github.com is allowlisted. **Mitigation:** Enable GitHub/GitLab branch protection (server-side, tamper-proof). Use read-only SSH deploy keys. Install the pre-push hook as a soft gate."
fi

if [ "$CODE_REVIEW" = "direct_commit" ] || [ "$CODE_REVIEW" = "undecided" ]; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🔴 **No code review enforcement** — Agent-generated code goes directly to main. 45% of AI-generated code contains security flaws. **Mitigation:** Require PR-based workflows with mandatory review. Add SAST/DAST scanning in CI."
fi

if [ "$AGENT_IDENTITY" = "same_identity" ] || [ "$AGENT_IDENTITY" = "undecided" ]; then
  ACCEPTED_RISKS="${ACCEPTED_RISKS}
- 🟡 **Agent commits indistinguishable** — Cannot identify which commits came from an AI agent in forensics or code review. **Mitigation:** Use dedicated service accounts or co-author tags. Set SAFE_AI_HOSTNAME per developer."
fi

# Build mitigated risks list
MITIGATED_RISKS="### Network Isolation
- 🟢 **Unauthorized egress blocked** — Docker \`internal: true\` network removes the default gateway. The sandbox has no route to the internet.
- 🟢 **Domain-level allowlisting** — Squid proxy ACLs enforce a strict allowlist. Only ${#DOMAINS[@]} domains are reachable.
- 🟢 **DNS filtering** — dnsmasq returns empty responses for non-allowlisted domains. DNS tunneling is blocked.
- 🟢 **Port restriction** — Only ports 80 (HTTP) and 443 (HTTPS) are allowed through the proxy.

### Container Hardening
- 🟢 **Read-only root filesystem** — System binaries cannot be modified. Backdoors cannot be installed.
- 🟢 **Seccomp whitelist** — Default-DENY syscall policy (vs Docker's default blacklist). Blocks ptrace, mount, bpf, unshare, io_uring, kernel modules.
- 🟢 **All capabilities dropped** — Only 5 minimal capabilities re-added for SSH. No namespace manipulation, no raw network.
- 🟢 **no-new-privileges** — Prevents privilege escalation via setuid/setgid binaries.
- 🟢 **noexec tmpfs** — \`/tmp\` and \`/run\` mounted with noexec flag. Direct ELF execution blocked.
- 🟢 **Resource limits** — Memory (8GB), CPU (4 cores), PID (512) limits prevent resource exhaustion."

if $USE_GVISOR; then
  MITIGATED_RISKS="${MITIGATED_RISKS}
- 🟢 **gVisor kernel isolation** — Syscalls intercepted by user-space kernel. Host kernel exploits blocked."
fi

MITIGATED_RISKS="${MITIGATED_RISKS}

### Credential Protection"

if [ -n "$GATEWAY_DOMAIN" ]; then
  MITIGATED_RISKS="${MITIGATED_RISKS}
- 🟢 **Gateway token injection** — API tokens are injected by the proxy, never visible to the sandbox.
- 🟢 **Anti-spoofing** — Sandbox cannot forge \`X-Safe-AI-Token\` headers. The proxy strips and re-adds them."
fi

MITIGATED_RISKS="${MITIGATED_RISKS}
- 🟢 **SSH key-only auth** — Password authentication disabled. Max 3 auth attempts."

if $ENABLE_LOGGING; then
  MITIGATED_RISKS="${MITIGATED_RISKS}

### Audit & Monitoring
- 🟢 **Structured JSON logging** — Every proxy request (allowed and denied) logged with timestamp, domain, method, bytes, SNI.
- 🟢 **Grafana dashboard** — Pre-built visualizations for request patterns, denied requests, data transfer volumes."
fi

# Build hardening roadmap
ROADMAP_TIER1=""
ROADMAP_TIER2=""
ROADMAP_TIER3=""

# Tier 1
if $USE_GVISOR; then
  ROADMAP_TIER1="${ROADMAP_TIER1}
| ✅ | Enable gVisor | Done — \`SAFE_AI_RUNTIME=runsc\` | Eliminates kernel exploit escape |"
else
  ROADMAP_TIER1="${ROADMAP_TIER1}
| ⬜ | gVisor alternative | Not available on ${PLATFORM} — keep Docker Desktop updated | Kernel exploits remain theoretical risk |"
fi

if $ENABLE_LOGGING; then
  ROADMAP_TIER1="${ROADMAP_TIER1}
| ✅ | Enable audit logging | Done — \`--profile logging\` | Visibility into all proxy activity |"
else
  ROADMAP_TIER1="${ROADMAP_TIER1}
| ⬜ | Enable audit logging | Run \`docker compose --profile logging up -d\` | No visibility without it |"
fi

ROADMAP_TIER1="${ROADMAP_TIER1}
| ✅ | Scope allowlist | Done — ${#DOMAINS[@]} domains configured | Reduces exfiltration surface |"

if [ -n "$GATEWAY_DOMAIN" ]; then
  ROADMAP_TIER1="${ROADMAP_TIER1}
| ✅ | Gateway token injection | Done — \`${GATEWAY_DOMAIN}\` | Credentials never in sandbox |"
else
  ROADMAP_TIER1="${ROADMAP_TIER1}
| ⬜ | Gateway token injection | Set \`SAFE_AI_GATEWAY_DOMAIN\` and \`SAFE_AI_GATEWAY_TOKEN\` | Keeps API credentials isolated |"
fi

ROADMAP_TIER1="${ROADMAP_TIER1}
| ✅ | Set hostname label | Done — \`SAFE_AI_HOSTNAME\` in .env | Per-developer audit trail |"

if [ "$APPROVAL_GATES" = "manual" ] || [ "$APPROVAL_GATES" = "undecided" ]; then
  ROADMAP_TIER1="${ROADMAP_TIER1}
| ⬜ | Install pre-push hook | \`cp config/git/pre-push .git/hooks/\` | Prevents unreviewed pushes |"
fi

# Tier 2
if [ "$PACKAGE_STRATEGY" = "public" ] && contains "$EXISTING_INFRA" "pkg_mirror"; then
  ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Use internal package mirror | You have one — update allowlist to use it instead of public registries | Supply chain protection |"
elif [ "$PACKAGE_STRATEGY" = "public" ]; then
  ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Deploy internal package mirror | Set up Artifactory/Nexus, remove registry.npmjs.org and pypi.org | Supply chain protection |"
fi

if $ENABLE_LOGGING; then
  ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Configure Grafana alerts | Set alerts for denied request spikes, unusual upload volume, off-hours activity | Active threat detection |"
fi

if [ "$AUDIT_LEVEL" = "central" ] || [ "$AUDIT_LEVEL" = "tamper" ]; then
  if contains "$EXISTING_INFRA" "siem"; then
    ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Ship logs to central SIEM | Set \`SAFE_AI_LOKI_URL\` to your SIEM endpoint | Org-wide visibility |"
  else
    ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Deploy central SIEM | Use \`examples/central-logging/docker-compose.yaml\` or connect to existing platform | Org-wide visibility |"
  fi
fi

ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Disable IPv6 on internal network | Add \`enable_ipv6: false\` to internal network in docker-compose.yaml | Close IPv6 bypass gap |
| ⬜ | Restrict SSH tunneling | Set \`AllowTcpForwarding local\` in sshd_config | Prevent SSH tunnel abuse |"

if [ "$CODE_REVIEW" = "direct_commit" ] || [ "$CODE_REVIEW" = "undecided" ]; then
  ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Enforce PR-based code review | Configure branch protection in GitHub/GitLab | 45% of AI code has flaws |"
fi

if [ "$AGENT_IDENTITY" = "same_identity" ] || [ "$AGENT_IDENTITY" = "undecided" ]; then
  ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Configure agent commit identity | \`git config user.name 'dev (via safe-ai)'\` in sandbox | Audit trail separation |"
fi

if [ "$INCIDENT_RESPONSE" = "none" ]; then
  ROADMAP_TIER2="${ROADMAP_TIER2}
| ⬜ | Create incident response plan | Use docs/incident-response.md as template | Uncontained compromise risk |"
fi

# Tier 3
if contains "$DATA_CLASSES" "itar" || contains "$DATA_CLASSES" "classified" || [ "$CODE_SENSITIVITY" = "critical" ]; then
  ROADMAP_TIER3="${ROADMAP_TIER3}
| ⬜ | Deploy self-hosted LLM | Remove external API domains from allowlist entirely | No data leaves the org |"
fi

ROADMAP_TIER3="${ROADMAP_TIER3}
| ⬜ | Block memfd_create in seccomp | Remove from config/seccomp.json if tools don't need it | Prevent fileless execution |
| ⬜ | Add volume size limits | Use XFS quotas on /workspace | Prevent disk exhaustion |
| ⬜ | Ship DNS + SSH logs | Add Fluent Bit inputs for dnsmasq and sshd logs | Close monitoring gaps |"

if [ "$AUDIT_LEVEL" = "tamper" ]; then
  ROADMAP_TIER3="${ROADMAP_TIER3}
| ⬜ | Tamper-evident logging | Ship to append-only store, enable Loki auth, consider hash-chaining | Log integrity |"
fi

# Compliance-specific notes
COMPLIANCE_NOTES=""
if contains "$COMPLIANCE" "gdpr"; then
  COMPLIANCE_NOTES="${COMPLIANCE_NOTES}
- **GDPR:** Use EU-region LLM API endpoints. Execute Data Processing Agreements (DPAs) with all LLM providers. Define log retention period (current: 30 days). Ensure right-to-erasure workflow for data sent to LLM APIs."
fi
if contains "$COMPLIANCE" "hipaa"; then
  COMPLIANCE_NOTES="${COMPLIANCE_NOTES}
- **HIPAA:** Execute BAAs with LLM providers. Ensure PHI is not present in code/test data sent to external APIs. Enable audit logging with 6-year retention. Consider self-hosted LLM."
fi
if contains "$COMPLIANCE" "soc2"; then
  COMPLIANCE_NOTES="${COMPLIANCE_NOTES}
- **SOC 2:** Enable audit logging (Trust Services Criteria CC7.2). Document allowlist change management process. Implement access reviews for SSH keys. Define incident response plan for sandbox compromise."
fi
if contains "$COMPLIANCE" "iso27001"; then
  COMPLIANCE_NOTES="${COMPLIANCE_NOTES}
- **ISO 27001:** Document safe-ai in your ISMS scope (A.8 Asset Management, A.13 Network Security). Include allowlist in change management (A.12.1.2). Log retention per A.12.4."
fi
if contains "$COMPLIANCE" "fedramp"; then
  COMPLIANCE_NOTES="${COMPLIANCE_NOTES}
- **FedRAMP:** Requires FIPS 140-2 validated cryptography — verify TLS configuration. Enable continuous monitoring (audit logging mandatory). Use FedRAMP-authorized LLM providers only. gVisor recommended (or equivalent isolation)."
fi
if contains "$COMPLIANCE" "cmmc"; then
  COMPLIANCE_NOTES="${COMPLIANCE_NOTES}
- **CMMC / NIST 800-171:** Requires FIPS-validated cryptography, access control logging, and media protection. Use self-hosted LLM for CUI. Enable audit logging with retention per NIST 800-171 3.3.1."
fi
if contains "$COMPLIANCE" "sox"; then
  COMPLIANCE_NOTES="${COMPLIANCE_NOTES}
- **SOX:** Ensure audit trail integrity for code changes. Enable tamper-evident logging. Document allowlist as an IT general control (ITGC)."
fi

# WSL2 callout
WSL2_SECTION=""
if [ "$PLATFORM" = "wsl2" ]; then
  WSL2_SECTION="
---

## WSL2-Specific Considerations

> **Important:** Your environment runs on Windows 11 with WSL2 and Docker Desktop.

| Requirement | Details |
|-------------|---------|
| **Filesystem** | Clone safe-ai onto the WSL2 native filesystem (\`~/\`), NOT \`/mnt/c/\`. NTFS mounts cause permission and performance issues. |
| **SSH keys** | SSH keys must be on the WSL2 filesystem (\`~/.ssh/\`), not the Windows side. |
| **gVisor** | Not available. Docker Desktop runs containers in a lightweight VM that does not support custom OCI runtimes. |
| **Docker variant** | Docker Desktop is recommended. Native Docker Engine in WSL2 works but requires manual iptables configuration. |
| **Line endings** | Ensure shell scripts use LF line endings (not CRLF). Run \`scripts/setup.sh\` to auto-fix. |
| **Networking** | Use NAT mode (default). Mirrored networking mode is not supported. |
"
fi

# Build supply chain section
SUPPLY_CHAIN_SECTION=""
if [ "$PACKAGE_STRATEGY" != "airgap" ]; then
  SUPPLY_CHAIN_SECTION="
---

## Supply Chain Security Guidance

### Lock Files

Always use lock files with integrity hashes:

| Ecosystem | Lock file | Secure install command |
|-----------|-----------|----------------------|
| npm | package-lock.json | npm ci |
| Yarn | yarn.lock | yarn install --frozen-lockfile |
| pip | requirements.txt with hashes | pip install --require-hashes -r requirements.txt |
| Poetry | poetry.lock | poetry install |

### Hallucinated Packages

AI agents may suggest packages that do not exist. Attackers register these hallucinated names on public registries — a technique known as slopsquatting (typosquatting via AI hallucinations). Always verify: \`npm info <package>\` or \`pip index versions <package>\`.

### MCP Servers

MCP server traffic is controlled by the domain allowlist. Before adding an MCP server domain, verify source code and maintainer, check for vulnerabilities, and prefer self-hosted servers for sensitive environments.
$(if [ "$PACKAGE_STRATEGY" = "public" ]; then echo "
### Recommendation: Internal Package Mirror

You are using public registries. For supply chain protection, deploy an internal mirror (Artifactory, Nexus) and remove registry.npmjs.org and pypi.org from the allowlist."; fi)
"
fi

# Build incident response section
IR_SECTION="
---

## Incident Response

$(if [ "$INCIDENT_RESPONSE" = "documented" ]; then echo "Your organization has a documented incident response plan."; elif [ "$INCIDENT_RESPONSE" = "general" ]; then echo "Extend your general IR plan for AI agent scenarios."; else echo "**Action required:** Create an incident response plan for AI agent compromise."; fi)

safe-ai provides the following IR tooling:

| Command | Phase | Purpose |
|---------|-------|---------|
| \`make kill\` | Contain | Stop all containers including logging |
| \`make snapshot\` | Preserve | Tar the workspace volume for forensics |
| \`docker cp safe-ai-proxy:/var/log/squid/ ./incident-logs/\` | Preserve | Copy proxy logs |

See [Incident Response Runbook](docs/incident-response.md) for the full 4-phase procedure: Contain, Preserve Evidence, Analyze, Recover.
"

# ─── Human-readable display values for report ────────────────────────────────

LLM_DISPLAY=$(echo "$LLM_PROVIDERS" | sed 's/cloud_direct/Direct cloud API/g; s/gateway/Enterprise gateway/g; s/selfhosted/Self-hosted/g' | tr ',' ', ')
DATA_DISPLAY=$(echo "$DATA_CLASSES" | sed 's/itar/Export-controlled (ITAR\/EAR)/g; s/classified/Classified\/restricted/g; s/pii/PII\/GDPR-regulated/g; s/ip/Proprietary IP/g; s/none/None/g' | tr ',' ', ')
SENSITIVITY_DISPLAY=$(echo "$CODE_SENSITIVITY" | sed 's/critical/Critical (air-gap required)/; s/high/High (minimize exposure)/; s/medium/Medium (audit trail required)/; s/low/Low (no concern)/')
WEB_DISPLAY=$(echo "$WEB_ACCESS" | sed 's/scoped/Scoped external docs/; s/internal/Internal docs only/; s/deny/Denied/')
PKG_DISPLAY=$(echo "$PACKAGE_STRATEGY" | sed 's/public/Public registries/; s/mirror/Internal mirror/; s/airgap/Air-gapped/')
TOOLS_DISPLAY=$(echo "$DEV_TOOLS" | sed 's/vscode/VS Code/g; s/jetbrains/JetBrains/g; s/cursor/Cursor\/Windsurf/g; s/terminal/Terminal/g' | tr ',' ', ')
AGENTS_DISPLAY=$(echo "$AI_AGENTS" | sed 's/claude/Claude Code/g; s/codex/Codex CLI/g; s/copilot/GitHub Copilot/g; s/gemini/Gemini CLI/g; s/custom/Other/g' | tr ',' ', ')
SCALE_DISPLAY=$(echo "$TEAM_SCALE" | sed 's/single/Single developer/; s/small/Small team (2-10)/; s/large/Large team (10+)/; s/multitenant/Multi-tenant/')
COMPLIANCE_DISPLAY=$(echo "$COMPLIANCE" | sed 's/soc2/SOC 2/g; s/iso27001/ISO 27001/g; s/fedramp/FedRAMP/g; s/hipaa/HIPAA/g; s/gdpr/GDPR/g; s/cmmc/CMMC\/NIST 800-171/g; s/sox/SOX/g; s/none/None/g' | tr ',' ', ')
AUDIT_DISPLAY=$(echo "$AUDIT_LEVEL" | sed 's/local/Local logs/; s/central/Central SIEM/; s/tamper/Tamper-evident/')
INFRA_DISPLAY=$(echo "$EXISTING_INFRA" | sed 's/pkg_mirror/Package mirror/g; s/api_gateway/API gateway/g; s/siem/Central SIEM/g; s/idp/Identity provider/g; s/none/None/g' | tr ',' ', ')
APPROVAL_DISPLAY=$(echo "$APPROVAL_GATES" | sed 's/agent_platform/Agent platform gates/; s/git_protection/Git branch protection/; s/manual/Manual/; s/undecided/Not yet decided/')
REVIEW_DISPLAY=$(echo "$CODE_REVIEW" | sed 's/pr_sast/PR + SAST\/DAST/; s/pr_only/PR review only/; s/direct_commit/Direct commit/; s/undecided/Not yet decided/')
IDENTITY_DISPLAY=$(echo "$AGENT_IDENTITY" | sed 's/service_account/Dedicated service account/; s/coauthor/Co-author tags/; s/same_identity/Same as developer/; s/undecided/Not yet decided/')
IR_DISPLAY=$(echo "$INCIDENT_RESPONSE" | sed 's/documented/Documented plan/; s/general/General plan (not AI-specific)/; s/none/No plan/')

# ─── Build TL;DR content ─────────────────────────────────────────────────────

TLDR_RISK_ITEMS=()
TLDR_ACTION_ITEMS=()

# Top risks — pick the most impactful accepted risks
if contains "$LLM_PROVIDERS" "cloud_direct"; then
  TLDR_RISK_ITEMS+=("Encrypted API payloads — code sent to cloud LLM APIs cannot be inspected")
fi
if ! $USE_GVISOR; then
  TLDR_RISK_ITEMS+=("No gVisor kernel isolation — theoretical container escape path remains")
fi
TLDR_RISK_ITEMS+=("Workspace file access — agent has full R/W within /workspace")

# Top actions — pick from roadmap
TLDR_ACTION_ITEMS+=("Review and approve the ${#DOMAINS[@]}-domain allowlist (see allowlist.yaml)")
if ! $ENABLE_LOGGING; then
  TLDR_ACTION_ITEMS+=("Enable audit logging: \`docker compose --profile logging up -d\`")
else
  TLDR_ACTION_ITEMS+=("Configure Grafana alerts for anomaly detection")
fi
if [ -n "$GATEWAY_DOMAIN" ]; then
  TLDR_ACTION_ITEMS+=("Set SAFE_AI_GATEWAY_TOKEN for credential isolation")
else
  TLDR_ACTION_ITEMS+=("Configure enterprise gateway for credential separation")
fi

# Format numbered lists
TLDR_RISKS=""
for i in "${!TLDR_RISK_ITEMS[@]}"; do
  TLDR_RISKS="${TLDR_RISKS}
$((i + 1)). ${TLDR_RISK_ITEMS[$i]}"
done

TLDR_ACTIONS=""
for i in "${!TLDR_ACTION_ITEMS[@]}"; do
  TLDR_ACTIONS="${TLDR_ACTIONS}
$((i + 1)). ${TLDR_ACTION_ITEMS[$i]}"
done

# ─── Write Report ─────────────────────────────────────────────────────────────

cat > "${OUTPUT_DIR}/risk-report.md" << REPORT_EOF
# safe-ai Enterprise Risk Assessment

**Generated:** ${DATE_STAMP}
**Risk Level:** ${RISK_EMOJI} **${RISK_LEVEL}**
**Platform:** ${PLATFORM_DISPLAY}

---

## TL;DR

| | |
|---|---|
| **Risk Level** | ${RISK_EMOJI} ${RISK_LEVEL} |
| **Scenario** | ${SCENARIO_NAME} |
| **Allowlisted Domains** | ${#DOMAINS[@]} |
| **Runtime** | ${RUNTIME} |

**Top Risks:**
${TLDR_RISKS}

**Top Actions:**
${TLDR_ACTIONS}

---

## Executive Summary

This report assesses the security posture of deploying AI coding agents using safe-ai in your environment. Based on your responses, your organization's risk level is **${RISK_LEVEL}**.

safe-ai provides **defense-in-depth container isolation** with network-layer allowlisting, filesystem immutability, syscall filtering, and audit logging — without requiring changes to the AI agent itself.

### Coverage at a Glance

| Domain | Coverage |
|--------|----------|
| Unauthorized network egress | 🟢 Excellent |
| Container escape / privilege escalation | $(if $USE_GVISOR; then echo "🟢 Excellent (gVisor enabled)"; else echo "🟡 Strong (gVisor not available on ${PLATFORM})"; fi) |
| Data exfiltration to allowlisted domains | 🟡 Metadata-only detection |
| Content-level DLP (inspect HTTPS payloads) | 🔴 Not addressed (by design) |
| Supply chain (package security) | $(if [ "$PACKAGE_STRATEGY" = "mirror" ] || [ "$PACKAGE_STRATEGY" = "airgap" ]; then echo "🟢 Controlled"; else echo "🟡 Domain-level only"; fi) |
| Audit & forensics | $(if $ENABLE_LOGGING; then echo "🟢 Good (logging enabled)"; else echo "🟡 Network only (enable --profile logging)"; fi) |

> **Key principle:** The sandbox has *no route to the internet*. All traffic is forced through the proxy, which enforces the allowlist. Even if the AI agent is fully compromised, it cannot bypass the network boundary.

---

## Your Environment Profile

| Question | Your Answer |
|----------|-------------|
| Platform | ${PLATFORM_DISPLAY} |
| LLM access | ${LLM_DISPLAY} |
| Data classification | ${DATA_DISPLAY} |
| Code sensitivity | ${SENSITIVITY_DISPLAY} |
| Web access | ${WEB_DISPLAY} |
| Package strategy | ${PKG_DISPLAY} |
| Developer tools | ${TOOLS_DISPLAY} |
| AI agents | ${AGENTS_DISPLAY} |
| Team scale | ${SCALE_DISPLAY} |
| Compliance | ${COMPLIANCE_DISPLAY} |
| Audit level | ${AUDIT_DISPLAY} |
| Existing infrastructure | ${INFRA_DISPLAY} |
| Approval gates | ${APPROVAL_DISPLAY} |
| Code review | ${REVIEW_DISPLAY} |
| Agent identity | ${IDENTITY_DISPLAY} |
| Incident response | ${IR_DISPLAY} |

---

## Enterprise Scenario Match

Based on your responses, your environment most closely matches:

**${SCENARIO_NAME}**

${SCENARIO_DESCRIPTION}

See [AI Coding Agent Security Requirements -- Enterprise Scenarios](docs/security-requirements.md#enterprise-scenarios) for detailed configuration guidance.

---

## AI Coding Agent Security Requirements Assessment

The following assessment maps your environment against the [12 requirements](docs/security-requirements.md) for enterprise AI coding agent deployment. R1-R7 and R10 are **mandatory**. R8 is **conditional** (mandatory when agents install packages or use MCP servers). R9, R11, and R12 are **recommended** and become mandatory at higher risk levels.

| # | Requirement | Priority | Your Coverage | Controls & Notes |
|---|------------|----------|--------------|-----------------|
| R1 | ${RISK_LABELS[R1]} | **Mandatory** | $(risk_status_icon "${RISK_COVERAGE[R1]}") | ${RISK_NOTES[R1]} |
| R2 | ${RISK_LABELS[R2]} | **Mandatory** | $(risk_status_icon "${RISK_COVERAGE[R2]}") | ${RISK_NOTES[R2]} |
| R3 | ${RISK_LABELS[R3]} | **Mandatory** | $(risk_status_icon "${RISK_COVERAGE[R3]}") | ${RISK_NOTES[R3]} |
| R4 | ${RISK_LABELS[R4]} | **Mandatory** | $(risk_status_icon "${RISK_COVERAGE[R4]}") | ${RISK_NOTES[R4]} |
| R5 | ${RISK_LABELS[R5]} | **Mandatory** | $(risk_status_icon "${RISK_COVERAGE[R5]}") | ${RISK_NOTES[R5]} |
| R6 | ${RISK_LABELS[R6]} | **Mandatory** | $(risk_status_icon "${RISK_COVERAGE[R6]}") | ${RISK_NOTES[R6]} |
| R7 | ${RISK_LABELS[R7]} | **Mandatory** | $(risk_status_icon "${RISK_COVERAGE[R7]}") | ${RISK_NOTES[R7]} |
| R8 | ${RISK_LABELS[R8]} | Conditional* | $(risk_status_icon "${RISK_COVERAGE[R8]}") | ${RISK_NOTES[R8]} |
| R9 | ${RISK_LABELS[R9]} | Recommended | $(risk_status_icon "${RISK_COVERAGE[R9]}") | ${RISK_NOTES[R9]} |
| R10 | ${RISK_LABELS[R10]} | **Mandatory** | $(risk_status_icon "${RISK_COVERAGE[R10]}") | ${RISK_NOTES[R10]} |
| R11 | ${RISK_LABELS[R11]} | Recommended | $(risk_status_icon "${RISK_COVERAGE[R11]}") | ${RISK_NOTES[R11]} |
| R12 | ${RISK_LABELS[R12]} | Recommended | $(risk_status_icon "${RISK_COVERAGE[R12]}") | ${RISK_NOTES[R12]} |

### How to Read This Table

- 🟢 **Mitigated** — safe-ai provides strong controls for your configuration. Residual risk is low.
- 🟡 **Partial** — safe-ai reduces the risk but does not eliminate it. Additional controls recommended.
- 🔴 **Minimal** — safe-ai provides limited protection here. Enterprise must add controls or accept the risk.
- ⚪ **N/A** — Not applicable to your configuration.

### Framework Mapping

Each requirement maps to established industry frameworks:

| Req | OWASP Agentic 2026 | OWASP LLM 2025 | NIST AI RMF | MITRE ATLAS |
|-----|-------------------|----------------|-------------|-------------|
| R1 | ASI02 (Tool Misuse) | -- | MANAGE 4.1 | Exfiltration |
| R2 | ASI05, ASI10 | LLM05 | -- | Execution |
| R3 | ASI03 | LLM02 | GOVERN | Credential Access |
| R4 | ASI09, ASI02 | LLM05, LLM06 | MANAGE | -- |
| R5 | ASI03 | -- | GOVERN | -- |
| R6 | ASI01, ASI06 | LLM01, LLM07 | -- | Collection |
| R7 | -- | LLM10 | -- | -- |
| R8 | ASI04 | LLM03 | MAP | Supply chain |
| R9 | ASI09 | LLM09 | MEASURE | -- |
| R10 | ASI03 | LLM02 | GOVERN | -- |
| R11 | ASI03 | -- | GOVERN | -- |
| R12 | ASI08 | -- | MANAGE | -- |

*R8 is mandatory when agents can install packages, connect to MCP servers, or pull tooling dynamically.

---

## Recommended Configuration

The following files have been generated in \`${OUTPUT_DIR}/\`:

| File | Purpose |
|------|---------|
| \`allowlist.yaml\` | ${#DOMAINS[@]} domains — your tailored network allowlist |
| \`.env\` | Environment variables for docker-compose |
| \`docker-compose.override.yaml\` | Volume mounts and tool-specific overrides |

### Allowlist (${#DOMAINS[@]} domains)

Your allowlist permits outbound access to **only** these domains:

$(for d in "${DOMAINS[@]}"; do echo "- \`${d}\`"; done)

Every other domain on the internet is **blocked** at both the DNS and proxy layers. Each domain above is a potential data exfiltration path — treat this list like a firewall rule set.

### Runtime Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| Runtime | \`${RUNTIME}\` | ${GVISOR_NOTE} |
| Logging | $(if $ENABLE_LOGGING; then echo "\`--profile logging\` (enabled)"; else echo "Disabled (consider enabling)"; fi) | $(if $ENABLE_LOGGING; then echo "Required for your compliance and audit requirements"; else echo "Provides visibility into proxy activity"; fi) |
| Gateway | $(if [ -n "$GATEWAY_DOMAIN" ]; then echo "\`${GATEWAY_DOMAIN}\`"; else echo "Not configured"; fi) | $(if [ -n "$GATEWAY_DOMAIN" ]; then echo "Token injection keeps credentials out of sandbox"; else echo "Configure if using enterprise API gateway"; fi) |

---

## What safe-ai Protects (Risks Mitigated)

${MITIGATED_RISKS}

---

## Risks You Accept

The following risks are **not fully mitigated** by safe-ai in your configuration. For each, we explain the risk and recommend additional controls.

${ACCEPTED_RISKS}

---

## Responsibility Boundary

safe-ai enforces controls at the **infrastructure level**. The following shows what safe-ai handles vs what your organization and agent platform must provide.

### safe-ai provides

| Control | Requirement | How |
|---------|-------------|-----|
| Network isolation and domain allowlisting | R1 | Docker internal:true + Squid proxy + dnsmasq |
| Container sandbox | R2 | Seccomp whitelist, cap_drop ALL, read-only root, noexec, no-new-privileges |
| Credential separation | R3 | Gateway token injection at proxy layer |
| Audit logging of proxy traffic | R5 | Structured JSON logs, Fluent Bit, Loki, Grafana |
| Filesystem scoping to /workspace | R6 | Named volume mount; no host access |
| Resource limits | R7 | Memory, CPU, PID limits via cgroups |

### Your organization must provide

| Control | Requirement | Why safe-ai cannot enforce it |
|---------|-------------|-------------------------------|
| Human approval gates | R4 | Cannot gate arbitrary agent tool use from infrastructure layer |
| Code review enforcement | R9 | GitHub/GitLab policy, not sandbox policy |
| Data classification decisions | R10 | Organizational policy determines what data goes where |
| Agent identity management | R11 | Identity federation is a platform responsibility |
| Incident response execution | R12 | safe-ai provides the runbook; the org executes |

> **Important:** An agent inside safe-ai can still delete workspace files, rewrite CI configs, or push to GitHub. The sandbox constrains WHERE data goes and WHAT the process can do to the host. It does not constrain what the agent does within /workspace.

${SUPPLY_CHAIN_SECTION}
${IR_SECTION}

---

## Hardening Roadmap

Prioritized actions for your environment. Items marked ✅ are already covered by your generated configuration.

### Tier 1 — Mandatory (Day 1)

| Status | Action | Details | Impact |
|--------|--------|---------|--------|
${ROADMAP_TIER1}

### Tier 2 — Recommended (Week 1)

| Status | Action | Details | Impact |
|--------|--------|---------|--------|
${ROADMAP_TIER2}

### Tier 3 — High Security (Month 1)

| Status | Action | Details | Impact |
|--------|--------|---------|--------|
${ROADMAP_TIER3}
${WSL2_SECTION}
$(if [ -n "$COMPLIANCE_NOTES" ]; then echo "
---

## Compliance-Specific Notes
${COMPLIANCE_NOTES}"; fi)

---

## Risk Acceptance Checklist

Use this checklist when deploying safe-ai. For each item, document whether your organization **accepts the residual risk** or **adds additional controls**. Items marked \`[x]\` are addressed by your generated configuration.

### Network & Data Flow

- [x] **Allowlist reviewed** — ${#DOMAINS[@]} domains approved (see allowlist.yaml)
- $(if [ "$WEB_ACCESS" = "scoped" ]; then echo "[x] **Web search**: Scoped to documentation sites"; elif [ "$WEB_ACCESS" = "internal" ]; then echo "[x] **Web search**: Internal documentation only"; else echo "[x] **Web search**: Denied — LLM API only"; fi)
- $(if [ "$PACKAGE_STRATEGY" = "public" ]; then echo "[ ] **Package registries**: Public registries allowed — consider internal mirror"; elif [ "$PACKAGE_STRATEGY" = "mirror" ]; then echo "[x] **Package registries**: Internal mirror configured"; else echo "[x] **Package registries**: Air-gapped — no external packages"; fi)
- $(if contains "$LLM_PROVIDERS" "selfhosted" && ! contains "$LLM_PROVIDERS" "cloud_direct"; then echo "[x] **LLM provider**: Self-hosted — code stays within org"; elif contains "$LLM_PROVIDERS" "gateway"; then echo "[x] **LLM provider**: Enterprise gateway configured"; else echo "[ ] **LLM provider**: Cloud API — code reaches third-party servers"; fi)
- [ ] **Exfiltration via allowlisted domains**: $(if contains "$LLM_PROVIDERS" "cloud_direct"; then echo "Accepted risk — encrypted payloads not inspectable"; else echo "Low risk — self-hosted/gateway LLM"; fi)

### Container Isolation

- $(if $USE_GVISOR; then echo "[x] **gVisor enabled** — kernel-level isolation active"; else echo "[ ] **gVisor**: Not available on ${PLATFORM} — accept residual kernel exploit risk"; fi)
- [x] **Resource limits** — 8GB memory, 4 CPUs, 512 PIDs
- [ ] **memfd_create risk** — Allows fileless execution. Accept or block in seccomp profile.

### Audit & Monitoring

- $(if $ENABLE_LOGGING; then echo "[x] **Audit logging enabled** — \`--profile logging\`"; else echo "[ ] **Audit logging** — NOT enabled. Run \`docker compose --profile logging up -d\`"; fi)
- $(if [ "$AUDIT_LEVEL" = "central" ] || [ "$AUDIT_LEVEL" = "tamper" ]; then echo "[ ] **Central SIEM** — Set \`SAFE_AI_LOKI_URL\` to your SIEM endpoint"; else echo "[ ] **Central SIEM** — Optional. Set \`SAFE_AI_LOKI_URL\` if needed"; fi)
- [ ] **Grafana alerting** — Configure alerts for anomalies (denied request spikes, upload volume)
- [ ] **Log retention** — Define retention period (current default: 30 days)

### Data Classification

$(if contains "$DATA_CLASSES" "itar"; then echo "- [ ] **Export-controlled code** — VERIFY: self-hosted LLM only. No cloud API domains in allowlist."; fi)
$(if contains "$DATA_CLASSES" "classified"; then echo "- [ ] **Classified data** — VERIFY: air-gapped configuration. Per-compartment sandboxes."; fi)
$(if contains "$DATA_CLASSES" "pii"; then echo "- [ ] **PII** — Execute DPAs with LLM providers. Use EU endpoints if required. Synthetic test data."; fi)
$(if contains "$DATA_CLASSES" "ip"; then echo "- [ ] **Intellectual property** — Enterprise LLM tier with zero-retention agreement."; fi)

### Human Approval & Code Review

- $(if [ "$APPROVAL_GATES" = "agent_platform" ] || [ "$APPROVAL_GATES" = "git_protection" ]; then echo "[x] **Approval gates**: ${APPROVAL_GATES}"; else echo "[ ] **Approval gates** -- NOT configured. Install pre-push hook: cp config/git/pre-push .git/hooks/"; fi)
- $(if [ "$CODE_REVIEW" = "pr_sast" ]; then echo "[x] **Code review**: PR + SAST/DAST"; elif [ "$CODE_REVIEW" = "pr_only" ]; then echo "[x] **Code review**: PR review (consider adding SAST scanning)"; else echo "[ ] **Code review** -- NOT enforced. Implement PR-based workflows"; fi)

### Agent Identity & Incident Response

- $(if [ "$AGENT_IDENTITY" = "service_account" ]; then echo "[x] **Agent identity**: Dedicated service accounts"; elif [ "$AGENT_IDENTITY" = "coauthor" ]; then echo "[x] **Agent identity**: Co-author tags"; else echo "[ ] **Agent identity** -- Agent commits indistinguishable from developer commits"; fi)
- $(if [ "$INCIDENT_RESPONSE" = "documented" ]; then echo "[x] **Incident response**: Documented plan"; elif [ "$INCIDENT_RESPONSE" = "general" ]; then echo "[ ] **Incident response** -- Extend general IR plan for AI agents (see docs/incident-response.md)"; else echo "[ ] **Incident response** -- Create plan using docs/incident-response.md"; fi)

### Organizational

- [ ] **Allowlist change management** — Define who can modify allowlist.yaml and how changes are reviewed
- [ ] **Incident response drill** — Schedule periodic IR drill for AI agent scenarios
- [ ] **Developer onboarding** — Create documentation for safe-ai usage and security boundaries

---

*Generated by safe-ai risk assessment. Review with your security team before deployment.*
*Source: [AI Coding Agent Security Requirements](docs/security-requirements.md) | [Enterprise Risk Mapping](docs/enterprise-risk-mapping.md)*
REPORT_EOF

# ─── Terminal Summary ─────────────────────────────────────────────────────────

print_header "Assessment Complete"

echo -e "  ${BOLD}Risk Level:${RESET}  ${RISK_EMOJI} ${RISK_LEVEL}"
echo -e "  ${BOLD}Platform:${RESET}    ${PLATFORM_DISPLAY}"
echo -e "  ${BOLD}Domains:${RESET}     ${#DOMAINS[@]} allowlisted"
echo -e "  ${BOLD}Runtime:${RESET}     ${RUNTIME}"
echo -e "  ${BOLD}Logging:${RESET}     $(if $ENABLE_LOGGING; then echo 'Enabled'; else echo 'Disabled'; fi)"
echo -e "  ${BOLD}Scenario:${RESET}    ${SCENARIO_NAME}"
echo ""
echo -e "  ${BOLD}Output directory:${RESET} ${OUTPUT_DIR}/"
echo -e "    ├── risk-report.md"
echo -e "    ├── allowlist.yaml"
echo -e "    ├── .env"
echo -e "    └── docker-compose.override.yaml"
echo ""

echo -e "  ${BOLD}Top recommendations:${RESET}"
if ! $USE_GVISOR; then
  echo -e "    ${YELLOW}⚠${RESET}  gVisor not available on ${PLATFORM} — keep host OS updated"
fi
if ! $ENABLE_LOGGING; then
  echo -e "    ${YELLOW}⚠${RESET}  Enable audit logging: docker compose --profile logging up -d"
fi
if contains "$DATA_CLASSES" "itar" && contains "$LLM_PROVIDERS" "cloud_direct"; then
  echo -e "    ${RED}✖${RESET}  CRITICAL: Remove cloud API domains for ITAR-controlled code"
fi
if [ "$PACKAGE_STRATEGY" = "public" ]; then
  echo -e "    ${YELLOW}⚠${RESET}  Consider internal package mirror for supply chain security"
fi
if [ "$APPROVAL_GATES" = "manual" ] || [ "$APPROVAL_GATES" = "undecided" ]; then
  echo -e "    ${YELLOW}⚠${RESET}  Approval gates need org controls -- enable branch protection + deploy keys"
fi
if [ "$CODE_REVIEW" = "direct_commit" ] || [ "$CODE_REVIEW" = "undecided" ]; then
  echo -e "    ${YELLOW}⚠${RESET}  No code review enforcement -- implement PR workflows"
fi
if [ "$INCIDENT_RESPONSE" = "none" ]; then
  echo -e "    ${YELLOW}⚠${RESET}  No incident response plan -- see docs/incident-response.md"
fi
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e "    1. Review ${OUTPUT_DIR}/risk-report.md with your security team"
echo -e "    2. Copy config files to your safe-ai project root:"
echo -e "       cp ${OUTPUT_DIR}/allowlist.yaml ${OUTPUT_DIR}/.env ."
echo -e "       cp ${OUTPUT_DIR}/docker-compose.override.yaml ."
echo -e "    3. Run ./scripts/setup.sh to validate and build"
echo -e "    4. docker compose $(if $ENABLE_LOGGING; then echo '--profile logging '; fi)up -d"
echo ""

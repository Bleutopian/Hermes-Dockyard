import type { DesktopSnapshot, FixtureId } from "../types";

const fixtures: Record<FixtureId, DesktopSnapshot> = {
  "no-wsl": {
    id: "no-wsl",
    label: "M1 ， No WSL distro",
    headline: "The host is missing the Ubuntu payload baseline.",
    summary:
      "Use this state to validate first-run empty-machine messaging before privileged setup exists.",
    availability: "missing",
    sections: [
      {
        label: "WSL platform",
        state: "missing",
        detail: "Required Windows feature or distro is absent.",
        evidence: "Expected M1 error code: WSL_MISSING",
      },
      {
        label: "Payload presence",
        state: "missing",
        detail: "No Hermes payload detected inside the distro.",
        evidence: "Expected M1 error code: PAYLOAD_NOT_INSTALLED",
      },
      {
        label: "Desktop posture",
        state: "ready",
        detail: "UI remains read-only and can still show diagnostics, logs, and next steps.",
        evidence: "No mutation path exposed in M2",
      },
    ],
    events: [
      {
        id: "evt-001",
        type: "operation_started",
        phase: "preflight",
        timestamp: "00:00",
        message: "Read-only preflight requested.",
      },
      {
        id: "evt-002",
        type: "error",
        phase: "wsl-check",
        timestamp: "00:02",
        message: "WSL_MISSING: Ubuntu 24.04 is not present.",
      },
      {
        id: "evt-003",
        type: "operation_completed",
        phase: "preflight",
        timestamp: "00:03",
        message: "Preflight completed with typed blockers.",
      },
    ],
    tools: [
      {
        name: "Hermes gateway",
        state: "missing",
        evidence: "Gateway status unavailable without distro.",
        note: "Tools view should degrade without attempting any recovery action.",
      },
      {
        name: "ClawPanel desktop payload",
        state: "missing",
        evidence: "No local install evidence in mock state.",
        note: "Install/repair actions are intentionally future-only.",
      },
    ],
    settings: [
      {
        label: "Backend mode",
        value: "Mock fixtures",
        mutability: "read-only",
        note: "Real integration is allowed only for read-only probes.",
      },
      {
        label: "Privilege boundary",
        value: "Unelevated shell only",
        mutability: "read-only",
        note: "Mutation remains blocked until M1b/M2b.",
      },
    ],
    logs: [
      {
        label: "preflight.json",
        lines: [
          "{",
          '  "code": "WSL_MISSING",',
          '  "message": "Ubuntu 24.04 not installed",',
          '  "mutated": false',
          "}",
        ],
      },
    ],
    videoAutomation: {
      state: "missing",
      binding: "127.0.0.1 only (future)",
      note: "CapCut Mate remains disabled-by-default and should not block M2.",
      gates: [
        "Requires M6 local service profile",
        "Requires Tools discovery contract",
        "Remains opt-in even after implementation",
      ],
    },
    blockers: [
      "WSL distro absent",
      "Payload not installed",
      "No privileged helper available yet",
    ],
    nextSteps: [
      "Show typed blocker messaging on Welcome and Preflight.",
      "Keep the dashboard readable without system mutation.",
    ],
  },
  "payload-missing": {
    id: "payload-missing",
    label: "M1 ， Distro exists, payload missing",
    headline: "WSL exists, but Hermes Dockyard resources are not installed.",
    summary:
      "Use this state to prove that the app can distinguish host prerequisites from payload prerequisites.",
    availability: "degraded",
    sections: [
      {
        label: "WSL platform",
        state: "ready",
        detail: "Ubuntu 24.04 distro is present and reachable.",
        evidence: "Read-only status returns distro identity.",
      },
      {
        label: "Payload presence",
        state: "missing",
        detail: "Hermes/Docker resources have not been staged into the distro.",
        evidence: "Expected M1 error code: PAYLOAD_NOT_INSTALLED",
      },
      {
        label: "Logs and diagnostics",
        state: "ready",
        detail: "Host-side diagnostics remain available for inspection.",
        evidence: "No escalated action required to read logs",
      },
    ],
    events: [
      {
        id: "evt-101",
        type: "operation_started",
        phase: "status",
        timestamp: "00:00",
        message: "Status requested for existing distro.",
      },
      {
        id: "evt-102",
        type: "warning",
        phase: "payload-check",
        timestamp: "00:01",
        message: "PAYLOAD_NOT_INSTALLED: /opt/agent-system manifest missing.",
      },
      {
        id: "evt-103",
        type: "status",
        phase: "summary",
        timestamp: "00:02",
        message: "Host ready, payload missing, mutation deferred.",
      },
    ],
    tools: [
      {
        name: "Docker daemon",
        state: "degraded",
        evidence: "Distro present, daemon not provisioned.",
        note: "Read-only scaffold should show evidence without implying a fix exists yet.",
      },
      {
        name: "Hermes tmux session",
        state: "missing",
        evidence: "No payload means no gateway session.",
        note: "Logs view should prefer structured absence over generic failure text.",
      },
    ],
    settings: [
      {
        label: "Read-only probe",
        value: "Enabled",
        mutability: "read-only",
        note: "Backend probes are fixed allowlisted commands.",
      },
      {
        label: "Repair actions",
        value: "Not yet exposed",
        mutability: "future",
        note: "M2 shell intentionally omits mutation controls.",
      },
    ],
    logs: [
      {
        label: "status.json",
        lines: [
          "{",
          '  "wsl": "ready",',
          '  "payload": "missing",',
          '  "error_code": "PAYLOAD_NOT_INSTALLED"',
          "}",
        ],
      },
    ],
    videoAutomation: {
      state: "missing",
      binding: "127.0.0.1 only (future)",
      note: "Tools must be detected before video automation can be enabled.",
      gates: ["Requires Tools discovery contract", "Requires payload baseline"],
    },
    blockers: ["Hermes payload absent inside WSL", "No resource repair helper yet"],
    nextSteps: [
      "Render payload-specific messaging in Dashboard and Tools.",
      "Keep Settings explicit about future-only mutation.",
    ],
  },
  "partial-install": {
    id: "partial-install",
    label: "M1 ， Partial install / degraded",
    headline: "Core payload exists, but one or more subsystems are degraded.",
    summary:
      "Use this state to exercise warning-heavy flows, restart guidance, and typed blocker rendering.",
    availability: "degraded",
    sections: [
      {
        label: "WSL platform",
        state: "ready",
        detail: "Ubuntu 24.04 and payload roots are present.",
        evidence: "Distro and /opt/agent-system manifest discovered.",
      },
      {
        label: "Docker daemon",
        state: "degraded",
        detail: "Daemon failed its most recent health check.",
        evidence: "Expected M1 error code: DOCKER_DAEMON_FAILED",
      },
      {
        label: "Hermes gateway",
        state: "degraded",
        detail: "Gateway session exists, but health endpoint is stale.",
        evidence: "Status event remains read-only and typed.",
      },
    ],
    events: [
      {
        id: "evt-201",
        type: "operation_started",
        phase: "status",
        timestamp: "00:00",
        message: "Status requested for partially installed machine.",
      },
      {
        id: "evt-202",
        type: "warning",
        phase: "docker-check",
        timestamp: "00:01",
        message: "DOCKER_DAEMON_FAILED: systemd unit inactive.",
      },
      {
        id: "evt-203",
        type: "warning",
        phase: "gateway-check",
        timestamp: "00:03",
        message: "Hermes gateway heartbeat is older than the stale threshold.",
      },
      {
        id: "evt-204",
        type: "operation_completed",
        phase: "status",
        timestamp: "00:04",
        message: "Status completed with degraded subsystems.",
      },
    ],
    tools: [
      {
        name: "Docker daemon",
        state: "degraded",
        evidence: "systemd unit inactive in mock fixture.",
        note: "Repair affordance remains descriptive-only for M2.",
      },
      {
        name: "Hermes gateway",
        state: "degraded",
        evidence: "Gateway heartbeat exceeds stale threshold.",
        note: "Logs and Dashboard should align on the same typed warning.",
      },
      {
        name: "ClawPanel desktop payload",
        state: "ready",
        evidence: "Existing host install detected in fixture.",
        note: "Read-only evidence can still power the Tools view.",
      },
    ],
    settings: [
      {
        label: "Diagnostics export",
        value: "Planned",
        mutability: "future",
        note: "Logs shown now are preview-only and non-exporting.",
      },
      {
        label: "Bridge / local tools",
        value: "Discovery only",
        mutability: "future",
        note: "No host app launch or control is permitted here.",
      },
    ],
    logs: [
      {
        label: "operations.jsonl",
        lines: [
          '{"type":"warning","code":"DOCKER_DAEMON_FAILED","phase":"docker-check"}',
          '{"type":"warning","code":"HERMES_INSTALL_FAILED","phase":"gateway-check"}',
        ],
      },
      {
        label: "hermes-gateway.log",
        lines: [
          "[warn] last heartbeat exceeded stale threshold",
          "[info] restart not attempted by read-only shell",
        ],
      },
    ],
    videoAutomation: {
      state: "degraded",
      binding: "127.0.0.1 only (future)",
      note: "Video automation is blocked behind M6 even when other subsystems are mostly healthy.",
      gates: ["Requires M6 service health contract", "Remains disabled by default"],
    },
    blockers: ["Docker daemon unhealthy", "Gateway heartbeat stale"],
    nextSteps: [
      "Exercise warning banners across Dashboard, Logs, and Tools.",
      "Keep any restart or repair affordance explicitly placeholder-only.",
    ],
  },
  healthy: {
    id: "healthy",
    label: "M1 ， Healthy baseline",
    headline: "Read-only checks can render a mostly healthy system without falling back to text parsing.",
    summary:
      "Use this state to validate the primary dashboard path and baseline M2 navigation polish.",
    availability: "ready",
    sections: [
      {
        label: "WSL platform",
        state: "ready",
        detail: "Ubuntu 24.04 is reachable and healthy.",
        evidence: "Status contract resolves distro and runtime details.",
      },
      {
        label: "Payload presence",
        state: "ready",
        detail: "Hermes, Docker, and desktop resources are present.",
        evidence: "Synthetic healthy fixture only; no mutation performed.",
      },
      {
        label: "Read-only shell",
        state: "ready",
        detail: "UI is limited to diagnostics, views, and future placeholders.",
        evidence: "No privileged controls surfaced.",
      },
    ],
    events: [
      {
        id: "evt-301",
        type: "operation_started",
        phase: "status",
        timestamp: "00:00",
        message: "Status requested for healthy machine.",
      },
      {
        id: "evt-302",
        type: "status",
        phase: "summary",
        timestamp: "00:02",
        message: "All read-only checks passed.",
      },
      {
        id: "evt-303",
        type: "operation_completed",
        phase: "status",
        timestamp: "00:03",
        message: "Healthy snapshot rendered for UI validation.",
      },
    ],
    tools: [
      {
        name: "Hermes gateway",
        state: "ready",
        evidence: "Healthy heartbeat and session present in fixture.",
        note: "View remains read-only even when healthy.",
      },
      {
        name: "ClawPanel desktop payload",
        state: "ready",
        evidence: "Host-side asset path resolved in fixture.",
        note: "Future launch actions remain disabled.",
      },
    ],
    settings: [
      {
        label: "Navigation shell",
        value: "Ready",
        mutability: "read-only",
        note: "All M2 views can be reviewed from this baseline.",
      },
      {
        label: "Privileged operations",
        value: "Out of scope",
        mutability: "future",
        note: "M2 does not expose mutation even when the system is healthy.",
      },
    ],
    logs: [
      {
        label: "status.json",
        lines: [
          "{",
          '  "status": "ready",',
          '  "gateway": "healthy",',
          '  "mutated": false',
          "}",
        ],
      },
    ],
    videoAutomation: {
      state: "degraded",
      binding: "127.0.0.1 only (future)",
      note: "Healthy core state should still communicate that video automation is deferred.",
      gates: ["Requires optional M6 service", "Requires explicit user opt-in"],
    },
    blockers: ["Video automation deferred until M6"],
    nextSteps: [
      "Use the healthy path to review polish and layout density.",
      "Validate that deferrals remain explicit in Settings and Video Automation.",
    ],
  },
};

export const m1Fixtures = fixtures;

export const m1FixtureOptions = Object.values(fixtures).map((fixture) => ({
  id: fixture.id,
  label: fixture.label,
  availability: fixture.availability,
  headline: fixture.headline,
}));
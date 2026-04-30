import { useMemo, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import "./App.css";
import type {
  BackendMode,
  BackendProbe,
  DesktopSnapshot,
  FixtureId,
  ViewId,
} from "./types";

const views: Array<{ id: ViewId; label: string }> = [
  { id: "welcome", label: "Welcome" },
  { id: "preflight", label: "Preflight" },
  { id: "dashboard", label: "Dashboard" },
  { id: "logs", label: "Logs" },
  { id: "settings", label: "Settings" },
  { id: "tools", label: "Tools" },
  { id: "videoAutomation", label: "Video Automation" },
];

const snapshots: Record<FixtureId, DesktopSnapshot> = {
  "no-wsl": {
    id: "no-wsl",
    label: "No WSL distro",
    headline: "The workstation is missing the Ubuntu 24.04 WSL base.",
    summary:
      "Read-only preflight can explain the blocker, but no provisioning action is exposed from this shell.",
    availability: "missing",
    sections: [
      {
        label: "WSL feature",
        state: "missing",
        detail: "Ubuntu-24.04 is not installed.",
        evidence: "Error code: WSL_MISSING",
      },
      {
        label: "Payload",
        state: "missing",
        detail: "No Agent payload is present because the distro is unavailable.",
      },
    ],
    events: [
      {
        id: "nw-1",
        type: "operation_started",
        phase: "preflight",
        timestamp: "2026-04-30T12:00:00Z",
        message: "Read-only preflight started.",
      },
      {
        id: "nw-2",
        type: "error",
        phase: "preflight",
        timestamp: "2026-04-30T12:00:01Z",
        message: "WSL distro is not installed.",
      },
      {
        id: "nw-3",
        type: "operation_completed",
        phase: "preflight",
        timestamp: "2026-04-30T12:00:01Z",
        message: "Preflight completed with typed blockers.",
      },
    ],
    tools: [
      {
        name: "Hermes gateway",
        state: "missing",
        evidence: "No WSL payload",
        note: "Unavailable until Ubuntu and the payload exist.",
      },
    ],
    settings: [
      {
        label: "Backend mode",
        value: "Mock",
        mutability: "read-only",
        note: "Real integration requires the M1 JSON contract.",
      },
    ],
    logs: [
      {
        label: "Preflight summary",
        lines: [
          "state=blocked",
          "error_codes=[WSL_MISSING]",
          "recommended_action=.\\scripts\\Install-AgentSystem.ps1",
        ],
      },
    ],
    videoAutomation: {
      state: "missing",
      binding: "127.0.0.1 only",
      note: "Video automation is gated behind later milestones.",
      gates: ["M6 optional service", "local-only binding"],
    },
    blockers: ["WSL distro is not installed."],
    nextSteps: [
      "Run the privileged installer outside the desktop shell.",
      "Return to the read-only shell to confirm preflight clears.",
    ],
  },
  "payload-missing": {
    id: "payload-missing",
    label: "WSL present, payload missing",
    headline: "Ubuntu exists, but the Agent payload has not been copied into WSL.",
    summary:
      "The desktop can render typed status and point to the installer, without parsing human CLI text.",
    availability: "degraded",
    sections: [
      {
        label: "WSL distro",
        state: "ready",
        detail: "Ubuntu-24.04 is installed and reachable.",
      },
      {
        label: "Payload",
        state: "missing",
        detail: "agent-system-status is absent from /usr/local/bin.",
        evidence: "Error code: PAYLOAD_NOT_INSTALLED",
      },
    ],
    events: [
      {
        id: "pm-1",
        type: "status",
        phase: "status",
        timestamp: "2026-04-30T12:05:00Z",
        message: "WSL distro detected.",
      },
      {
        id: "pm-2",
        type: "warning",
        phase: "payload",
        timestamp: "2026-04-30T12:05:01Z",
        message: "Payload is not installed yet.",
      },
    ],
    tools: [
      {
        name: "Docker daemon",
        state: "missing",
        evidence: "Payload missing",
        note: "Docker health is not probed until the payload exists.",
      },
    ],
    settings: [
      {
        label: "Read-only contract",
        value: "JSON",
        mutability: "read-only",
        note: "Desktop wiring only accepts structured data.",
      },
    ],
    logs: [
      {
        label: "Backend guidance",
        lines: [
          "WSL distro exists.",
          "Payload is not installed.",
          "Install command is typed and non-interactive from the UI.",
        ],
      },
    ],
    videoAutomation: {
      state: "missing",
      binding: "127.0.0.1 only",
      note: "Feature remains disabled until the core install path is stable.",
      gates: ["M4 stable core path", "M6 opt-in service"],
    },
    blockers: ["Payload has not been installed into WSL."],
    nextSteps: [
      "Run .\\scripts\\Install-AgentSystem.ps1 as an elevated step outside the shell.",
    ],
  },
  "partial-install": {
    id: "partial-install",
    label: "Payload installed, Docker degraded",
    headline: "Read-only status works, but Docker is not yet healthy.",
    summary:
      "This mirrors the M1 synthetic state where the payload exists but a follow-up recovery action is still needed.",
    availability: "degraded",
    sections: [
      {
        label: "Payload",
        state: "ready",
        detail: "The status script is available in WSL.",
      },
      {
        label: "Docker daemon",
        state: "degraded",
        detail: "Docker is installed but not responding.",
        evidence: "Error code: DOCKER_DAEMON_FAILED",
      },
      {
        label: "Hermes gateway",
        state: "degraded",
        detail: "Hermes is installed, but the tmux session is stopped.",
      },
    ],
    events: [
      {
        id: "pi-1",
        type: "operation_started",
        phase: "status",
        timestamp: "2026-04-30T12:10:00Z",
        message: "Status probe started.",
      },
      {
        id: "pi-2",
        type: "warning",
        phase: "docker",
        timestamp: "2026-04-30T12:10:01Z",
        message: "Docker daemon is not reachable.",
      },
      {
        id: "pi-3",
        type: "operation_completed",
        phase: "status",
        timestamp: "2026-04-30T12:10:02Z",
        message: "Status probe completed with warnings.",
      },
    ],
    tools: [
      {
        name: "Hermes gateway",
        state: "degraded",
        evidence: "tmux session missing",
        note: "Recovery remains a future privileged operation.",
      },
      {
        name: "ClawPanel",
        state: "degraded",
        evidence: "Installer state not yet surfaced",
        note: "Later milestones will promote this to first-run provisioning.",
      },
    ],
    settings: [
      {
        label: "Output mode",
        value: "json",
        mutability: "read-only",
        note: "Text-mode CLI remains preserved for terminal users.",
      },
    ],
    logs: [
      {
        label: "Status reducer",
        lines: [
          "payload=ready",
          "docker=warning",
          "hermes=warning",
          "reboot_required=false",
        ],
      },
    ],
    videoAutomation: {
      state: "degraded",
      binding: "127.0.0.1 only",
      note: "UI space is reserved, but the service is not enabled by default.",
      gates: ["Optional CapCut Mate profile", "user opt-in"],
    },
    blockers: ["Docker daemon is not reachable."],
    nextSteps: [
      "Use the future repair flow to restart Docker or refresh local resources.",
    ],
  },
  healthy: {
    id: "healthy",
    label: "Healthy read-only state",
    headline: "The desktop shell can render a healthy typed snapshot.",
    summary:
      "This is the M2 target for real read-only status and preflight once the backend contract is stable.",
    availability: "ready",
    sections: [
      {
        label: "WSL distro",
        state: "ready",
        detail: "Ubuntu-24.04 is installed.",
      },
      {
        label: "Payload",
        state: "ready",
        detail: "Read-only status/preflight commands are present.",
      },
      {
        label: "Docker daemon",
        state: "ready",
        detail: "Docker is running inside WSL.",
      },
    ],
    events: [
      {
        id: "ok-1",
        type: "operation_started",
        phase: "preflight",
        timestamp: "2026-04-30T12:15:00Z",
        message: "Preflight started.",
      },
      {
        id: "ok-2",
        type: "status",
        phase: "preflight",
        timestamp: "2026-04-30T12:15:01Z",
        message: "All read-only checks passed.",
      },
      {
        id: "ok-3",
        type: "operation_completed",
        phase: "preflight",
        timestamp: "2026-04-30T12:15:02Z",
        message: "Preflight completed successfully.",
      },
    ],
    tools: [
      {
        name: "Hermes gateway",
        state: "ready",
        evidence: "tmux session running",
        note: "Mutating controls remain out of scope for M2.",
      },
      {
        name: "Video automation",
        state: "degraded",
        evidence: "disabled by default",
        note: "Space is reserved for later milestones only.",
      },
    ],
    settings: [
      {
        label: "Desktop shell",
        value: "Read-only",
        mutability: "read-only",
        note: "No privileged helper or shell passthrough is exposed.",
      },
    ],
    logs: [
      {
        label: "Health snapshot",
        lines: [
          "state=ready",
          "docker=ready",
          "hermes_gateway=ready",
          "next_action=.\\bin\\agent-system.ps1 start",
        ],
      },
    ],
    videoAutomation: {
      state: "degraded",
      binding: "127.0.0.1 only",
      note: "Placeholder only; no service is enabled by default.",
      gates: ["M6 optional service", "explicit user enablement"],
    },
    blockers: [],
    nextSteps: [
      "Confirm the real backend status matches the healthy fixture.",
      "Move on to the M2b privilege-boundary proof before shipping an installer.",
    ],
  },
};

function parseBackendProbe(raw: string | null): BackendProbe | null {
  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw) as BackendProbe;
  } catch {
    return null;
  }
}

function App() {
  const [activeView, setActiveView] = useState<ViewId>("welcome");
  const [fixtureId, setFixtureId] = useState<FixtureId>("no-wsl");
  const [backendMode, setBackendMode] = useState<BackendMode>("mock");
  const [backendAction, setBackendAction] = useState<"preflight" | "status">(
    "preflight",
  );
  const [realProbe, setRealProbe] = useState<BackendProbe | null>(null);
  const [probeError, setProbeError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const snapshot = snapshots[fixtureId];
  const visibleEvents = useMemo(() => snapshot.events.slice(0, 5), [snapshot]);

  const runRealProbe = async () => {
    setLoading(true);
    setProbeError(null);
    try {
      const raw = await invoke<string>("probe_backend_action", {
        action: backendAction,
      });
      setRealProbe(parseBackendProbe(raw) ?? (raw as unknown as BackendProbe));
    } catch (error) {
      setRealProbe(null);
      setProbeError(String(error));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="shell">
      <aside className="sidebar">
        <div>
          <p className="eyebrow">Hermes Dockyard</p>
          <h1>Desktop shell</h1>
          <p className="lede">
            M2 read-only scaffold for preflight, status, logs, and future tools.
          </p>
        </div>

        <nav className="nav">
          {views.map((view) => (
            <button
              key={view.id}
              className={view.id === activeView ? "nav-button active" : "nav-button"}
              onClick={() => setActiveView(view.id)}
              type="button"
            >
              {view.label}
            </button>
          ))}
        </nav>

        <section className="panel compact">
          <label className="field">
            <span>Backend mode</span>
            <select
              value={backendMode}
              onChange={(event) => setBackendMode(event.target.value as BackendMode)}
            >
              <option value="mock">Mock fixtures</option>
              <option value="real">Real read-only probe</option>
            </select>
          </label>

          <label className="field">
            <span>Fixture</span>
            <select
              value={fixtureId}
              onChange={(event) => setFixtureId(event.target.value as FixtureId)}
              disabled={backendMode === "real"}
            >
              {Object.values(snapshots).map((fixture) => (
                <option key={fixture.id} value={fixture.id}>
                  {fixture.label}
                </option>
              ))}
            </select>
          </label>
        </section>
      </aside>

      <main className="content">
        <section className="hero panel">
          <div>
            <p className="eyebrow">{snapshot.label}</p>
            <h2>{snapshot.headline}</h2>
            <p>{snapshot.summary}</p>
          </div>
          <span className={`status-pill ${snapshot.availability}`}>
            {snapshot.availability}
          </span>
        </section>

        {activeView === "welcome" && (
          <section className="grid two-up">
            <article className="panel">
              <h3>What this shell proves</h3>
              <ul className="stack-list">
                <li>React + TypeScript UI is wired for seven core views.</li>
                <li>Only allowlisted read-only backend actions are callable.</li>
                <li>Mock fixtures cover no-WSL, payload-missing, degraded, and healthy states.</li>
              </ul>
            </article>
            <article className="panel">
              <h3>Next gates</h3>
              <ul className="stack-list">
                {snapshot.nextSteps.map((step) => (
                  <li key={step}>{step}</li>
                ))}
              </ul>
            </article>
          </section>
        )}

        {activeView === "preflight" && (
          <section className="grid two-up">
            <article className="panel">
              <div className="section-header">
                <h3>Preflight / status contract</h3>
                <span className="muted">JSON only</span>
              </div>
              {backendMode === "mock" ? (
                <ul className="stack-list">
                  {snapshot.sections.map((section) => (
                    <li key={section.label}>
                      <strong>{section.label}</strong> — {section.detail}
                      {section.evidence ? <div className="muted">{section.evidence}</div> : null}
                    </li>
                  ))}
                </ul>
              ) : (
                <div className="stack">
                  <div className="row">
                    <label className="field grow">
                      <span>Action</span>
                      <select
                        value={backendAction}
                        onChange={(event) =>
                          setBackendAction(event.target.value as "preflight" | "status")
                        }
                      >
                        <option value="preflight">preflight</option>
                        <option value="status">status</option>
                      </select>
                    </label>
                    <button type="button" onClick={runRealProbe} disabled={loading}>
                      {loading ? "Running…" : "Run probe"}
                    </button>
                  </div>
                  {probeError ? <p className="error-text">{probeError}</p> : null}
                  {realProbe ? (
                    <div className="code-block">
                      <pre>{JSON.stringify(realProbe, null, 2)}</pre>
                    </div>
                  ) : (
                    <p className="muted">
                      Real mode only invokes the read-only allowlist exposed by the Rust bridge.
                    </p>
                  )}
                </div>
              )}
            </article>

            <article className="panel">
              <h3>Recent events</h3>
              <ul className="event-list">
                {visibleEvents.map((event) => (
                  <li key={event.id}>
                    <span className={`event-type ${event.type}`}>{event.type}</span>
                    <div>
                      <strong>{event.phase}</strong>
                      <p>{event.message}</p>
                      <span className="muted">{event.timestamp}</span>
                    </div>
                  </li>
                ))}
              </ul>
            </article>
          </section>
        )}

        {activeView === "dashboard" && (
          <section className="grid three-up">
            {snapshot.sections.map((section) => (
              <article key={section.label} className="panel">
                <div className="section-header">
                  <h3>{section.label}</h3>
                  <span className={`status-pill ${section.state}`}>{section.state}</span>
                </div>
                <p>{section.detail}</p>
                {section.evidence ? <p className="muted">{section.evidence}</p> : null}
              </article>
            ))}
          </section>
        )}

        {activeView === "logs" && (
          <section className="grid two-up">
            {snapshot.logs.map((log) => (
              <article key={log.label} className="panel">
                <h3>{log.label}</h3>
                <div className="code-block">
                  <pre>{log.lines.join("\n")}</pre>
                </div>
              </article>
            ))}
            <article className="panel">
              <h3>Blockers</h3>
              {snapshot.blockers.length > 0 ? (
                <ul className="stack-list">
                  {snapshot.blockers.map((blocker) => (
                    <li key={blocker}>{blocker}</li>
                  ))}
                </ul>
              ) : (
                <p className="muted">No blockers in this fixture.</p>
              )}
            </article>
          </section>
        )}

        {activeView === "settings" && (
          <section className="grid two-up">
            {snapshot.settings.map((setting) => (
              <article key={setting.label} className="panel">
                <div className="section-header">
                  <h3>{setting.label}</h3>
                  <span className="muted">{setting.mutability}</span>
                </div>
                <p>{setting.value}</p>
                <p className="muted">{setting.note}</p>
              </article>
            ))}
          </section>
        )}

        {activeView === "tools" && (
          <section className="grid two-up">
            {snapshot.tools.map((tool) => (
              <article key={tool.name} className="panel">
                <div className="section-header">
                  <h3>{tool.name}</h3>
                  <span className={`status-pill ${tool.state}`}>{tool.state}</span>
                </div>
                <p>{tool.note}</p>
                <p className="muted">{tool.evidence}</p>
              </article>
            ))}
          </section>
        )}

        {activeView === "videoAutomation" && (
          <section className="grid two-up">
            <article className="panel">
              <div className="section-header">
                <h3>Video automation</h3>
                <span className={`status-pill ${snapshot.videoAutomation.state}`}>
                  {snapshot.videoAutomation.state}
                </span>
              </div>
              <p>{snapshot.videoAutomation.note}</p>
              <p className="muted">Binding: {snapshot.videoAutomation.binding}</p>
            </article>
            <article className="panel">
              <h3>Release gates</h3>
              <ul className="stack-list">
                {snapshot.videoAutomation.gates.map((gate) => (
                  <li key={gate}>{gate}</li>
                ))}
              </ul>
            </article>
          </section>
        )}
      </main>
    </div>
  );
}

export default App;

import { invoke } from "@tauri-apps/api/core";
import { useEffect, useMemo, useState } from "react";
import "./App.css";
import { ProbePanel } from "./components/ProbePanel";
import { m1FixtureOptions, m1Fixtures } from "./data/m1Fixtures";
import type { BackendMode, BackendProbe, FixtureId, ViewId } from "./types";
import { DashboardView } from "./views/DashboardView";
import { LogsView } from "./views/LogsView";
import { PreflightView } from "./views/PreflightView";
import { SettingsView } from "./views/SettingsView";
import { ToolsView } from "./views/ToolsView";
import { VideoAutomationView } from "./views/VideoAutomationView";
import { WelcomeView } from "./views/WelcomeView";

const navItems: Array<{ id: ViewId; label: string }> = [
  { id: "welcome", label: "Welcome" },
  { id: "preflight", label: "Preflight" },
  { id: "dashboard", label: "Dashboard" },
  { id: "logs", label: "Logs" },
  { id: "settings", label: "Settings" },
  { id: "tools", label: "Tools" },
  { id: "videoAutomation", label: "Video Automation" },
];

function App() {
  const [activeView, setActiveView] = useState<ViewId>("welcome");
  const [backendMode, setBackendMode] = useState<BackendMode>("mock");
  const [activeFixtureId, setActiveFixtureId] = useState<FixtureId>("no-wsl");
  const [probe, setProbe] = useState<BackendProbe | null>(null);
  const [probePending, setProbePending] = useState(false);

  const snapshot = useMemo(() => m1Fixtures[activeFixtureId], [activeFixtureId]);

  async function runProbe(action: "preflight" | "status") {
    setProbePending(true);
    try {
      const result = await invoke<BackendProbe>("probe_backend_action", { action });
      setProbe(result);
    } catch (error) {
      setProbe({
        action,
        available: false,
        note: `Probe invocation failed: ${String(error)}`,
        command: "",
      });
    } finally {
      setProbePending(false);
    }
  }

  useEffect(() => {
    if (backendMode === "real" && probe === null) {
      void runProbe("status");
    }
  }, [backendMode, probe]);

  const view = (() => {
    switch (activeView) {
      case "welcome":
        return <WelcomeView snapshot={snapshot} />;
      case "preflight":
        return <PreflightView snapshot={snapshot} backendMode={backendMode} probe={probe} />;
      case "dashboard":
        return <DashboardView snapshot={snapshot} probe={probe} />;
      case "logs":
        return <LogsView snapshot={snapshot} probe={probe} />;
      case "settings":
        return <SettingsView snapshot={snapshot} backendMode={backendMode} />;
      case "tools":
        return <ToolsView snapshot={snapshot} />;
      case "videoAutomation":
        return <VideoAutomationView snapshot={snapshot} />;
      default:
        return <ProbePanel probe={probe} />;
    }
  })();

  return (
    <main className="shell">
      <aside className="sidebar">
        <div className="brand">
          <p className="brand__eyebrow">Hermes Dockyard / Agent System</p>
          <h1>Desktop M2 Read-Only Shell</h1>
          <p className="brand__summary">
            Tauri v2 + React scaffold for preflight, status, logs, and future tool surfaces.
          </p>
        </div>

        <nav className="nav-list" aria-label="Primary desktop views">
          {navItems.map((item) => (
            <button
              key={item.id}
              className={`nav-list__button ${item.id === activeView ? "is-active" : ""}`}
              type="button"
              onClick={() => setActiveView(item.id)}
            >
              {item.label}
            </button>
          ))}
        </nav>

        <section className="sidebar-panel">
          <h2>Backend source</h2>
          <div className="mode-toggle">
            <button
              type="button"
              className={backendMode === "mock" ? "is-active" : ""}
              onClick={() => {
                setBackendMode("mock");
                setProbe(null);
              }}
            >
              Mock
            </button>
            <button
              type="button"
              className={backendMode === "real" ? "is-active" : ""}
              onClick={() => {
                setBackendMode("real");
                setProbe(null);
              }}
            >
              Real
            </button>
          </div>
          <p className="sidebar-panel__copy">
            Real mode is limited to fixed allowlisted read-only probes and will gracefully degrade
            until M1 JSON output is available.
          </p>
        </section>

        <section className="sidebar-panel">
          <h2>M1 fixture</h2>
          <select
            value={activeFixtureId}
            onChange={(event) => setActiveFixtureId(event.currentTarget.value as FixtureId)}
          >
            {m1FixtureOptions.map((option) => (
              <option key={option.id} value={option.id}>
                {option.label}
              </option>
            ))}
          </select>
          <p className="sidebar-panel__copy">{snapshot.headline}</p>
        </section>

        <section className="sidebar-panel">
          <h2>Probe controls</h2>
          <div className="action-stack">
            <button type="button" onClick={() => void runProbe("status")} disabled={probePending}>
              {probePending ? "Running¡­" : "Run status"}
            </button>
            <button type="button" onClick={() => void runProbe("preflight")} disabled={probePending}>
              {probePending ? "Running¡­" : "Run preflight"}
            </button>
          </div>
          <p className="sidebar-panel__copy">
            Commands remain read-only and are intentionally scoped to `status` and `preflight`.
          </p>
        </section>
      </aside>

      <section className="content">
        <header className="content-header">
          <div>
            <p className="content-header__eyebrow">{snapshot.label}</p>
            <h2>{navItems.find((item) => item.id === activeView)?.label}</h2>
          </div>
          <div className="content-header__badges">
            <span className={`status-pill status-pill--${snapshot.availability}`}>
              {snapshot.availability}
            </span>
            <span className={`status-pill ${backendMode === "mock" ? "status-pill--ready" : "status-pill--degraded"}`}>
              {backendMode === "mock" ? "mock backend" : "real read-only probe"}
            </span>
          </div>
        </header>

        {view}
      </section>
    </main>
  );
}

export default App;
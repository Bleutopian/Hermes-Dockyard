import type { BackendMode, DesktopSnapshot } from "../types";
import { SectionCard } from "../components/SectionCard";

interface SettingsViewProps {
  snapshot: DesktopSnapshot;
  backendMode: BackendMode;
}

export function SettingsView({ snapshot, backendMode }: SettingsViewProps) {
  return (
    <div className="view-grid">
      <SectionCard
        title="Desktop shell settings"
        state="ready"
        subtitle="Settings are intentionally descriptive while the product is still in M2."
      >
        <div className="settings-grid">
          {snapshot.settings.map((setting) => (
            <article key={setting.label} className="settings-card">
              <header>
                <h3>{setting.label}</h3>
                <span
                  className={`status-pill status-pill--${
                    setting.mutability === "read-only" ? "ready" : "degraded"
                  }`}
                >
                  {setting.mutability}
                </span>
              </header>
              <p>{setting.value}</p>
              <small>{setting.note}</small>
            </article>
          ))}
        </div>
      </SectionCard>

      <SectionCard
        title="Runtime mode"
        state={backendMode === "mock" ? "ready" : "degraded"}
        subtitle="Real mode remains intentionally narrow."
      >
        <ul className="bullet-list">
          <li>Current mode: {backendMode === "mock" ? "Mock fixtures" : "Real read-only probe"}</li>
          <li>Privileged helper boundary is not exposed from Settings.</li>
          <li>Future mutation controls should remain fixed, allowlisted, and audited.</li>
        </ul>
      </SectionCard>
    </div>
  );
}
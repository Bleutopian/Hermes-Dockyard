import type { BackendMode, BackendProbe, DesktopSnapshot } from "../types";
import { ProbePanel } from "../components/ProbePanel";
import { SectionCard } from "../components/SectionCard";

interface PreflightViewProps {
  snapshot: DesktopSnapshot;
  backendMode: BackendMode;
  probe: BackendProbe | null;
}

export function PreflightView({ snapshot, backendMode, probe }: PreflightViewProps) {
  return (
    <div className="view-grid">
      <SectionCard
        title="Preflight contract preview"
        state={snapshot.availability}
        subtitle="The UI is prepared for typed JSON output without parsing human CLI text."
      >
        <div className="state-list">
          {snapshot.sections.map((section) => (
            <article key={section.label} className="state-row">
              <div>
                <h3>{section.label}</h3>
                <p>{section.detail}</p>
              </div>
              <div className="state-row__meta">
                <span className={`status-pill status-pill--${section.state}`}>{section.state}</span>
                {section.evidence ? <small>{section.evidence}</small> : null}
              </div>
            </article>
          ))}
        </div>
      </SectionCard>

      {backendMode === "real" ? (
        <ProbePanel probe={probe} />
      ) : (
        <SectionCard
          title="Real integration placeholder"
          state="degraded"
          subtitle="Switch to Real mode to run the fixed allowlisted read-only probe."
        >
          <p>
            Mock mode keeps the experience deterministic while Lane A finishes the M1 JSON
            contract. Once available, the same view will render the backend response directly.
          </p>
        </SectionCard>
      )}
    </div>
  );
}
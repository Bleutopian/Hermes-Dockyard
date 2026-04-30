import type { BackendProbe, DesktopSnapshot } from "../types";
import { EventTimeline } from "../components/EventTimeline";
import { SectionCard } from "../components/SectionCard";

interface DashboardViewProps {
  snapshot: DesktopSnapshot;
  probe: BackendProbe | null;
}

export function DashboardView({ snapshot, probe }: DashboardViewProps) {
  return (
    <div className="view-grid">
      <SectionCard title="System summary" state={snapshot.availability} subtitle={snapshot.headline}>
        <div className="metric-grid">
          {snapshot.sections.map((section) => (
            <article key={section.label} className="metric-card">
              <span className={`status-pill status-pill--${section.state}`}>{section.state}</span>
              <h3>{section.label}</h3>
              <p>{section.detail}</p>
              {section.evidence ? <small>{section.evidence}</small> : null}
            </article>
          ))}
        </div>
      </SectionCard>

      <SectionCard title="Recent contract events" subtitle="M1 event types mirrored into the desktop shell.">
        <EventTimeline events={snapshot.events} />
      </SectionCard>

      <SectionCard
        title="Integration posture"
        state={probe?.available ? "ready" : "degraded"}
        subtitle="Real backend probing is placeholder-grade until the backend JSON contract lands."
      >
        <ul className="bullet-list">
          <li>Only read-only actions are exposed (`status`, `preflight`).</li>
          <li>No arbitrary shell execution or privileged helper calls are present.</li>
          <li>Mock fixture overlays stay available for layout and state review.</li>
        </ul>
      </SectionCard>
    </div>
  );
}
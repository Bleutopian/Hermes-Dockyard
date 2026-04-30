import type { DesktopSnapshot } from "../types";
import { SectionCard } from "../components/SectionCard";

interface ToolsViewProps {
  snapshot: DesktopSnapshot;
}

export function ToolsView({ snapshot }: ToolsViewProps) {
  return (
    <div className="view-grid">
      <SectionCard
        title="Host tool discovery"
        state={snapshot.availability}
        subtitle="Evidence-first read-only placeholders for future bridge and app detection."
      >
        <div className="metric-grid">
          {snapshot.tools.map((tool) => (
            <article key={tool.name} className="metric-card">
              <span className={`status-pill status-pill--${tool.state}`}>{tool.state}</span>
              <h3>{tool.name}</h3>
              <p>{tool.evidence}</p>
              <small>{tool.note}</small>
            </article>
          ))}
        </div>
      </SectionCard>

      <SectionCard
        title="Boundary notes"
        state="ready"
        subtitle="The Tools view prepares space for safe discovery without crossing the privilege boundary."
      >
        <ul className="bullet-list">
          <li>Discovery evidence is displayed, but no launch/control path exists yet.</li>
          <li>Future bridge work should stay local-only and opt-in.</li>
          <li>Read-only status can still explain absent or degraded tools clearly.</li>
        </ul>
      </SectionCard>
    </div>
  );
}
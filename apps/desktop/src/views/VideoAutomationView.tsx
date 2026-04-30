import type { DesktopSnapshot } from "../types";
import { SectionCard } from "../components/SectionCard";

interface VideoAutomationViewProps {
  snapshot: DesktopSnapshot;
}

export function VideoAutomationView({ snapshot }: VideoAutomationViewProps) {
  const { videoAutomation } = snapshot;

  return (
    <div className="view-grid">
      <SectionCard
        title="Video Automation"
        state={videoAutomation.state}
        subtitle="Optional lane preview only ¡ª never required for the core M2 shell."
      >
        <dl className="definition-grid">
          <div>
            <dt>Service posture</dt>
            <dd>{videoAutomation.note}</dd>
          </div>
          <div>
            <dt>Binding target</dt>
            <dd className="mono">{videoAutomation.binding}</dd>
          </div>
        </dl>

        <ul className="bullet-list">
          {videoAutomation.gates.map((gate) => (
            <li key={gate}>{gate}</li>
          ))}
        </ul>
      </SectionCard>

      <SectionCard
        title="Why it stays deferred"
        state="ready"
        subtitle="The core desktop shell should not depend on CapCut Mate or any editor integration."
      >
        <ul className="bullet-list">
          <li>Core install and preflight need to work before any automation service exists.</li>
          <li>Local-only binding and explicit opt-in remain non-negotiable.</li>
          <li>M2 focuses on safe, observable read-only flows.</li>
        </ul>
      </SectionCard>
    </div>
  );
}
import type { DesktopSnapshot } from "../types";
import { SectionCard } from "../components/SectionCard";

interface WelcomeViewProps {
  snapshot: DesktopSnapshot;
}

export function WelcomeView({ snapshot }: WelcomeViewProps) {
  return (
    <div className="view-grid">
      <SectionCard title="Hermes Dockyard desktop shell" state={snapshot.availability} subtitle={snapshot.headline}>
        <p>{snapshot.summary}</p>
        <ul className="bullet-list">
          <li>Tauri v2 + React + TypeScript scaffold is in place.</li>
          <li>All navigation targets for M2 are wired and browseable.</li>
          <li>Read-only integration is constrained to status and preflight placeholders.</li>
        </ul>
      </SectionCard>

      <SectionCard title="Fixture-driven review" subtitle="Use the active fixture selector to exercise the main M1 states.">
        <ul className="bullet-list">
          {snapshot.nextSteps.map((step) => (
            <li key={step}>{step}</li>
          ))}
        </ul>
      </SectionCard>

      <SectionCard title="Current blockers" subtitle="These remain visible even in the read-only shell.">
        <ul className="bullet-list">
          {snapshot.blockers.map((blocker) => (
            <li key={blocker}>{blocker}</li>
          ))}
        </ul>
      </SectionCard>
    </div>
  );
}
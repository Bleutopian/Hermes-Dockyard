import type { BackendProbe, DesktopSnapshot } from "../types";
import { ProbePanel } from "../components/ProbePanel";
import { SectionCard } from "../components/SectionCard";

interface LogsViewProps {
  snapshot: DesktopSnapshot;
  probe: BackendProbe | null;
}

export function LogsView({ snapshot, probe }: LogsViewProps) {
  return (
    <div className="view-grid">
      {snapshot.logs.map((stream) => (
        <SectionCard key={stream.label} title={stream.label} subtitle="Mock stream rendered from M1 fixture data.">
          <div className="terminal-block">
            <pre>{stream.lines.join("\n")}</pre>
          </div>
        </SectionCard>
      ))}

      <ProbePanel probe={probe} title="Latest read-only probe output" />
    </div>
  );
}
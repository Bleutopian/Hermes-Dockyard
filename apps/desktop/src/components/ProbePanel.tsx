import type { BackendProbe } from "../types";
import { SectionCard } from "./SectionCard";

interface ProbePanelProps {
  probe: BackendProbe | null;
  title?: string;
}

export function ProbePanel({ probe, title = "Real read-only backend probe" }: ProbePanelProps) {
  if (!probe) {
    return (
      <SectionCard
        title={title}
        state="degraded"
        subtitle="No probe has been run yet. Use the status or preflight action to exercise the placeholder bridge."
      >
        <p>
          The M2 shell wires fixed allowlisted `status` and `preflight` commands, but it does not
          surface any mutating operations.
        </p>
      </SectionCard>
    );
  }

  return (
    <SectionCard title={title} state={probe.available ? "ready" : "degraded"} subtitle={probe.note}>
      <dl className="definition-grid">
        <div>
          <dt>Action</dt>
          <dd>{probe.action}</dd>
        </div>
        <div>
          <dt>Exit code</dt>
          <dd>{probe.exitCode ?? "n/a"}</dd>
        </div>
        <div>
          <dt>Command</dt>
          <dd className="mono">{probe.command || "Not available"}</dd>
        </div>
        <div>
          <dt>Script path</dt>
          <dd className="mono">{probe.scriptPath ?? "Not discovered"}</dd>
        </div>
      </dl>

      {probe.stdout ? (
        <div className="terminal-block">
          <h3>stdout</h3>
          <pre>{probe.stdout}</pre>
        </div>
      ) : null}

      {probe.stderr ? (
        <div className="terminal-block terminal-block--error">
          <h3>stderr</h3>
          <pre>{probe.stderr}</pre>
        </div>
      ) : null}
    </SectionCard>
  );
}
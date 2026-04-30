export type ViewId =
  | "welcome"
  | "preflight"
  | "dashboard"
  | "logs"
  | "settings"
  | "tools"
  | "videoAutomation";

export type BackendMode = "mock" | "real";

export type FixtureId =
  | "no-wsl"
  | "payload-missing"
  | "partial-install"
  | "healthy";

export type AvailabilityState = "missing" | "degraded" | "ready";

export interface StateSection {
  label: string;
  state: AvailabilityState;
  detail: string;
  evidence?: string;
}

export interface EventEntry {
  id: string;
  type:
    | "operation_started"
    | "progress"
    | "status"
    | "warning"
    | "error"
    | "reboot_required"
    | "operation_completed";
  phase: string;
  timestamp: string;
  message: string;
}

export interface ToolEntry {
  name: string;
  state: AvailabilityState;
  evidence: string;
  note: string;
}

export interface SettingEntry {
  label: string;
  value: string;
  mutability: "read-only" | "future";
  note: string;
}

export interface LogStream {
  label: string;
  lines: string[];
}

export interface VideoAutomationState {
  state: AvailabilityState;
  binding: string;
  note: string;
  gates: string[];
}

export interface DesktopSnapshot {
  id: FixtureId;
  label: string;
  headline: string;
  summary: string;
  availability: AvailabilityState;
  sections: StateSection[];
  events: EventEntry[];
  tools: ToolEntry[];
  settings: SettingEntry[];
  logs: LogStream[];
  videoAutomation: VideoAutomationState;
  blockers: string[];
  nextSteps: string[];
}

export interface BackendProbe {
  action: "preflight" | "status" | string;
  available: boolean;
  note: string;
  command: string;
  scriptPath?: string | null;
  exitCode?: number | null;
  stdout?: string | null;
  stderr?: string | null;
}
import type { PropsWithChildren } from "react";
import type { AvailabilityState } from "../types";

interface SectionCardProps extends PropsWithChildren {
  title: string;
  state?: AvailabilityState;
  subtitle?: string;
}

export function SectionCard({
  title,
  state,
  subtitle,
  children,
}: SectionCardProps) {
  return (
    <section className="panel section-card">
      <header className="section-card__header">
        <div>
          <h2>{title}</h2>
          {subtitle ? <p>{subtitle}</p> : null}
        </div>
        {state ? <span className={`status-pill status-pill--${state}`}>{state}</span> : null}
      </header>
      <div className="section-card__body">{children}</div>
    </section>
  );
}
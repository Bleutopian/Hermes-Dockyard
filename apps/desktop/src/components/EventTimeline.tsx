import type { EventEntry } from "../types";

interface EventTimelineProps {
  events: EventEntry[];
}

export function EventTimeline({ events }: EventTimelineProps) {
  return (
    <ol className="event-timeline">
      {events.map((event) => (
        <li key={event.id} className={`event-timeline__item event-timeline__item--${event.type}`}>
          <div className="event-timeline__meta">
            <span>{event.timestamp}</span>
            <span>{event.phase}</span>
          </div>
          <div>
            <strong>{event.type}</strong>
            <p>{event.message}</p>
          </div>
        </li>
      ))}
    </ol>
  );
}
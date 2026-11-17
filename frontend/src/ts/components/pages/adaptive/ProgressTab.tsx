// oxlint-disable monkeytype-rules/one-component-per-file
import { createMemo, For, JSXElement, Show } from "solid-js";

import { SessionSummary } from "../../../adaptive/model";
import { getProfile, version } from "../../../adaptive/session";
import { Card, Empty } from "./shared";

function LineChart(props: {
  sessions: SessionSummary[];
  value: (s: SessionSummary) => number;
  format: (v: number) => string;
}): JSXElement {
  const w = 600;
  const h = 140;
  const pad = 6;
  const data = createMemo(() => {
    const values = props.sessions.map(props.value);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const span = max - min || 1;
    const x = (i: number): number =>
      pad +
      (values.length <= 1 ? 0.5 : i / (values.length - 1)) * (w - 2 * pad);
    const y = (v: number): number =>
      h - pad - ((v - min) / span) * (h - 2 * pad);
    // smoothed trend: moving average over a fifth of the history
    const win = Math.max(1, Math.round(values.length / 5));
    const smooth = values.map((_, i) => {
      const part = values.slice(Math.max(0, i - win + 1), i + 1);
      return part.reduce((a, b) => a + b, 0) / part.length;
    });
    return {
      min,
      max,
      last: values[values.length - 1] ?? 0,
      points: values.map((v, i) => ({
        x: x(i),
        y: y(v),
        adaptive: props.sessions[i]?.adaptive,
      })),
      path: smooth
        .map(
          (v, i) =>
            `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(v).toFixed(1)}`,
        )
        .join(" "),
    };
  });
  return (
    <div>
      <svg
        viewBox={`0 0 ${w} ${h}`}
        class="h-36 w-full"
        preserveAspectRatio="none"
      >
        {/* oxlint-disable-next-line react/no-unknown-property */}
        <path
          d={data().path}
          fill="none"
          class="stroke-main stroke-2 [vector-effect:non-scaling-stroke]"
        ></path>
        <For each={data().points}>
          {(p) => (
            <circle
              cx={p.x}
              cy={p.y}
              r="2.5"
              class={p.adaptive ? "fill-main" : "fill-sub"}
            ></circle>
          )}
        </For>
      </svg>
      <div class="flex justify-between text-xs text-sub">
        <span>
          min {props.format(data().min)} · max {props.format(data().max)}
        </span>
        <span class="text-text">now {props.format(data().last)}</span>
      </div>
    </div>
  );
}

export function ProgressTab(): JSXElement {
  const sessions = createMemo(() => {
    version();
    return getProfile().sessions;
  });
  const recent = (): SessionSummary[] => [...sessions()].reverse().slice(0, 15);
  const fmtTime = (t: number): string =>
    new Date(t).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });

  return (
    <Show
      when={sessions().length >= 2}
      fallback={
        <Empty text="Progress charts appear after two analyzed tests." />
      }
    >
      <div class="grid gap-6">
        <div class="text-xs text-sub">
          Each dot is one analyzed test (highlighted = training test). The line
          is a moving average.
        </div>
        <div class="grid gap-6 xl:grid-cols-2">
          <Card title="weakness index (lower is better)" icon="fa-chart-line">
            <LineChart
              sessions={sessions()}
              value={(s) => s.wi}
              format={(v) => v.toFixed(1)}
            />
          </Card>
          <Card title="speed" icon="fa-tachometer-alt">
            <LineChart
              sessions={sessions()}
              value={(s) => s.wpm}
              format={(v) => `${Math.round(v)} wpm`}
            />
          </Card>
          <Card title="accuracy" icon="fa-bullseye">
            <LineChart
              sessions={sessions()}
              value={(s) => s.acc}
              format={(v) => `${v.toFixed(1)}%`}
            />
          </Card>
          <Card
            title="rhythm consistency (variation, lower is better)"
            icon="fa-wave-square"
          >
            <LineChart
              sessions={sessions()}
              value={(s) => s.consistency}
              format={(v) => `${Math.round(v * 100)}%`}
            />
          </Card>
          <Card title="error cost" icon="fa-hourglass-half">
            <LineChart
              sessions={sessions().filter((s) => s.errCost > 0)}
              value={(s) => s.errCost}
              format={(v) => `${Math.round(v)} ms`}
            />
          </Card>
          <Card
            title="fatigue (last third vs first third)"
            icon="fa-battery-quarter"
          >
            <LineChart
              sessions={sessions()}
              value={(s) => s.fatigue}
              format={(v) =>
                `${v >= 1 ? "+" : ""}${Math.round((v - 1) * 100)}%`
              }
            />
          </Card>
        </div>
        <Card title="recent tests" icon="fa-history">
          <div class="overflow-x-auto">
            <table class="w-full border-collapse [&>tbody>tr:nth-child(odd)>td]:bg-bg">
              <thead>
                <tr class="text-left text-sub [&>th]:px-3 [&>th]:py-2 [&>th]:font-normal">
                  <th>when</th>
                  <th>mode</th>
                  <th>wpm</th>
                  <th>acc</th>
                  <th>keystrokes</th>
                  <th>weakness index</th>
                  <th>error cost</th>
                  <th>after-error tempo</th>
                  <th>intensity</th>
                </tr>
              </thead>
              <tbody>
                <For each={recent()}>
                  {(s) => (
                    <tr class="[&>td]:px-3 [&>td]:py-2">
                      <td class="whitespace-nowrap text-sub">{fmtTime(s.t)}</td>
                      <td class={s.adaptive ? "text-main" : ""}>{s.mode}</td>
                      <td>{Math.round(s.wpm)}</td>
                      <td>{s.acc.toFixed(1)}%</td>
                      <td>{s.chars}</td>
                      <td>{s.wi.toFixed(1)}</td>
                      <td>
                        {s.errCost > 0 ? `${Math.round(s.errCost)} ms` : "–"}
                      </td>
                      <td>
                        {s.postError >= 1 ? "+" : ""}
                        {Math.round((s.postError - 1) * 100)}%
                      </td>
                      <td>
                        {s.intensity !== undefined
                          ? `${Math.round(s.intensity * 100)}%`
                          : "–"}
                      </td>
                    </tr>
                  )}
                </For>
              </tbody>
            </table>
          </div>
        </Card>
      </div>
    </Show>
  );
}

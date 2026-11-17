// oxlint-disable monkeytype-rules/one-component-per-file
import { createMemo, createSignal, For, JSXElement, Show } from "solid-js";

import { patternLabel } from "../../../adaptive/generate";
import { Scored } from "../../../adaptive/model";
import { getGeometry, version } from "../../../adaptive/session";
import { cn } from "../../../utils/cn";
import { Button } from "../../common/Button";
import { Card, Empty, levelClass, Meter, msToWpm, pct } from "./shared";

type Metric = "weakness" | "errors" | "speed" | "samples";

const fingerOrder = [0, 1, 2, 3, 4, 5, 6, 7];
const motionIds = [
  "alt",
  "roll-in",
  "roll-out",
  "sfb",
  "double",
  "rowjump",
  "stretch",
];
const otherIds = [
  "word-start",
  "capital",
  "punctuation",
  "number",
  "row-0",
  "row-1",
  "row-2",
  "row-3",
  "len-short",
  "len-medium",
  "len-long",
  "len-xlong",
];

function PatternTable(props: {
  title: string;
  icon: string;
  ids: string[];
  byId: Map<string, Scored>;
  wordLevel?: boolean;
}): JSXElement {
  const rows = (): Scored[] =>
    props.ids
      .map((id) => props.byId.get(`c:${id}`))
      .filter((s): s is Scored => s !== undefined);
  return (
    <Card title={props.title} icon={props.icon}>
      <Show when={rows().length > 0} fallback={<Empty text="No data yet." />}>
        <div class="grid grid-cols-[auto_minmax(2.5rem,1fr)_auto_auto_auto] items-center gap-x-3 gap-y-2 text-sm">
          <For each={rows()}>
            {(s) => (
              <>
                <div class={cn("whitespace-nowrap", levelClass[s.level])}>
                  {patternLabel(s.text)}
                </div>
                <Meter value={s.level === "new" ? 0 : s.weakness} />
                <div class="text-right whitespace-nowrap">
                  {pct(s.errorRate)} err
                </div>
                <div class="text-right whitespace-nowrap">
                  {Math.round(msToWpm(s.ms))} wpm
                </div>
                <div class="text-right text-sm whitespace-nowrap text-sub">
                  {s.relLatency >= 1 ? "+" : ""}
                  {Math.round((s.relLatency - 1) * 100)}%
                </div>
              </>
            )}
          </For>
        </div>
      </Show>
    </Card>
  );
}

export function KeyboardTab(props: { scored: Scored[] }): JSXElement {
  const [metric, setMetric] = createSignal<Metric>("weakness");
  const byId = createMemo(() => new Map(props.scored.map((s) => [s.id, s])));
  const geo = createMemo(() => {
    version();
    return getGeometry();
  });
  const maxSamples = createMemo(() =>
    Math.max(
      1,
      ...props.scored.filter((s) => s.type === "k").map((s) => s.samples),
    ),
  );

  const heat = (ch: string): number => {
    const s = byId().get(`k:${ch}`);
    if (s === undefined) return 0;
    switch (metric()) {
      case "weakness":
        return s.level === "new" ? 0 : Math.min(1, s.weakness * 1.6);
      case "errors":
        return Math.min(1, s.errorRate * 8);
      case "speed":
        return Math.min(1, Math.max(0, (s.relLatency - 0.85) * 2));
      default:
        return s.samples / maxSamples();
    }
  };
  const label = (ch: string): string => {
    const s = byId().get(`k:${ch}`);
    if (s === undefined) return "no data";
    return `${pct(s.errorRate)} errors · ${Math.round(msToWpm(s.ms))} wpm · ${s.samples} samples · ${s.level}`;
  };

  return (
    <div class="grid gap-6">
      <Card title={`key heatmap (${geo().name})`} icon="fa-keyboard">
        <div class="mb-4 flex flex-wrap gap-2">
          <For each={["weakness", "errors", "speed", "samples"] as Metric[]}>
            {(m) => (
              <Button
                variant="button"
                active={metric() === m}
                text={m}
                onClick={() => setMetric(m)}
              />
            )}
          </For>
        </div>
        <div class="grid justify-center gap-1.5 overflow-x-auto">
          <For each={geo().rows}>
            {(row, r) => (
              <div
                class="flex gap-1.5"
                style={{
                  "padding-left": `${[0, 1.5, 2.25, 3.5][r()] ?? 0}rem`,
                }}
              >
                <For each={row}>
                  {(ch) => (
                    <div
                      class="grid h-11 w-11 shrink-0 place-items-center rounded text-lg text-text"
                      style={{
                        background: `color-mix(in srgb, var(--${metric() === "samples" ? "main" : "error"}-color) ${Math.round(heat(ch) * 100)}%, var(--bg-color))`,
                      }}
                      aria-label={label(ch)}
                      data-balloon-pos="up"
                    >
                      {ch}
                    </div>
                  )}
                </For>
              </div>
            )}
          </For>
          <div class="flex justify-center pt-1">
            <div
              class="grid h-9 w-72 place-items-center rounded text-sm text-sub"
              style={{
                background: `color-mix(in srgb, var(--${metric() === "samples" ? "main" : "error"}-color) ${Math.round(heat(" ") * 100)}%, var(--bg-color))`,
              }}
              aria-label={label(" ")}
              data-balloon-pos="up"
            >
              space
            </div>
          </div>
        </div>
      </Card>
      <div class="grid gap-6 lg:grid-cols-2 2xl:grid-cols-3">
        <PatternTable
          title="fingers"
          icon="fa-hand-paper"
          ids={fingerOrder.map((f) => `finger-${f}`)}
          byId={byId()}
        />
        <PatternTable
          title="motion patterns"
          icon="fa-exchange-alt"
          ids={motionIds}
          byId={byId()}
        />
        <PatternTable
          title="rows, symbols, word length"
          icon="fa-th"
          ids={otherIds}
          byId={byId()}
        />
      </div>
    </div>
  );
}

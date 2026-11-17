// oxlint-disable monkeytype-rules/one-component-per-file
import { createMemo, createSignal, For, JSXElement, Show } from "solid-js";

import { Scored, UnitType } from "../../../adaptive/model";
import { cn } from "../../../utils/cn";
import { Button } from "../../common/Button";
import { Empty, levelClass, Meter, msToWpm, pct, show } from "./shared";

type SortKey =
  | "weakness"
  | "errorRate"
  | "relLatency"
  | "lostMs"
  | "samples"
  | "trend"
  | "due";

const sorters: Record<SortKey, (s: Scored) => number> = {
  weakness: (s) => (s.level === "new" ? -1 : s.weakness),
  errorRate: (s) => s.errorRate,
  relLatency: (s) => s.relLatency,
  lostMs: (s) => s.lostMs * s.samples,
  samples: (s) => s.samples,
  trend: (s) => s.trend,
  due: (s) => s.components.forgetting,
};

const types: { id: UnitType; label: string }[] = [
  { id: "k", label: "keys" },
  { id: "b", label: "bigrams" },
  { id: "t", label: "trigrams" },
  { id: "s", label: "syllables" },
  { id: "w", label: "words" },
];

function Th(props: {
  label: string;
  help: string;
  sort?: SortKey;
  current: SortKey;
  onSort: (k: SortKey) => void;
}): JSXElement {
  return (
    <th
      class={cn("px-3 py-2 text-left font-normal whitespace-nowrap text-sub", {
        "cursor-pointer hover:text-text": props.sort !== undefined,
        "text-main": props.sort === props.current,
      })}
      aria-label={props.help}
      data-balloon-pos="up"
      data-balloon-length="medium"
      onClick={() => props.sort !== undefined && props.onSort(props.sort)}
    >
      {props.label}
      {props.sort === props.current ? " ▾" : ""}
    </th>
  );
}

export function UnitsTab(props: { scored: Scored[] }): JSXElement {
  const [type, setType] = createSignal<UnitType>("b");
  const [sort, setSort] = createSignal<SortKey>("weakness");
  const [query, setQuery] = createSignal("");
  const [limit, setLimit] = createSignal(40);
  const [hideNew, setHideNew] = createSignal(true);

  const rows = createMemo(() => {
    const q = query().toLowerCase();
    const key = sorters[sort()];
    return props.scored
      .filter(
        (s) =>
          s.type === type() &&
          (!hideNew() || s.level !== "new") &&
          (q === "" || s.text.includes(q)),
      )
      .sort((a, b) => key(b) - key(a));
  });

  return (
    <div class="grid gap-4">
      <div class="flex flex-wrap items-center gap-2">
        <For each={types}>
          {(t) => (
            <Button
              variant="button"
              active={type() === t.id}
              text={t.label}
              onClick={() => {
                setType(t.id);
                setLimit(40);
              }}
            />
          )}
        </For>
        <div class="grow"></div>
        <Button
          variant="button"
          active={hideNew()}
          text="hide low-data"
          balloon={{
            text: "Hide units with too few samples to judge",
            position: "up",
          }}
          onClick={() => setHideNew(!hideNew())}
        />
        <input
          class="w-40"
          placeholder="filter..."
          value={query()}
          onInput={(e) => setQuery(e.currentTarget.value)}
        />
      </div>
      <Show
        when={rows().length > 0}
        fallback={<Empty text="Nothing to show yet." />}
      >
        <div class="overflow-x-auto">
          <table class="w-full border-collapse [&>tbody>tr:nth-child(odd)>td]:bg-sub-alt">
            <thead>
              <tr>
                <Th
                  label="unit"
                  help="The key, sequence or word"
                  current={sort()}
                  onSort={setSort}
                />
                <Th
                  label="level"
                  help="Overall verdict"
                  current={sort()}
                  onSort={setSort}
                />
                <Th
                  label="weakness"
                  help="Combined weakness score (scoring model and weights from settings)"
                  sort="weakness"
                  current={sort()}
                  onSort={setSort}
                />
                <Th
                  label="errors"
                  help="Estimated error rate (shrunk towards your average when data is thin)"
                  sort="errorRate"
                  current={sort()}
                  onSort={setSort}
                />
                <Th
                  label="speed"
                  help="Speed through this unit, as wpm, and relative to your average for this level"
                  sort="relLatency"
                  current={sort()}
                  onSort={setSort}
                />
                <Th
                  label="time lost"
                  help="Estimated total time lost on this unit versus your own average (slowness + errors x correction cost)"
                  sort="lostMs"
                  current={sort()}
                  onSort={setSort}
                />
                <Th
                  label="trend"
                  help="Recent samples versus the longer run. Up = getting worse"
                  sort="trend"
                  current={sort()}
                  onSort={setSort}
                />
                <Th
                  label="review"
                  help="Spaced repetition: how due this unit is, and its memory stability in days"
                  sort="due"
                  current={sort()}
                  onSort={setSort}
                />
                <Th
                  label="samples"
                  help="How often you have typed it"
                  sort="samples"
                  current={sort()}
                  onSort={setSort}
                />
              </tr>
            </thead>
            <tbody>
              <For each={rows().slice(0, limit())}>
                {(s) => (
                  <tr>
                    <td class="px-3 py-2 text-xl whitespace-pre text-text">
                      {show(s.text)}
                    </td>
                    <td class={cn("px-3 py-2", levelClass[s.level])}>
                      {s.level}
                    </td>
                    <td class="min-w-28 px-3 py-2">
                      <Meter value={s.level === "new" ? 0 : s.weakness} />
                    </td>
                    <td class="px-3 py-2">{pct(s.errorRate)}</td>
                    <td class="px-3 py-2 whitespace-nowrap">
                      {Math.round(msToWpm(s.ms))} wpm{" "}
                      <span class="text-sm text-sub">
                        {s.relLatency >= 1 ? "+" : ""}
                        {Math.round((s.relLatency - 1) * 100)}%
                      </span>
                    </td>
                    <td class="px-3 py-2 whitespace-nowrap">
                      {((Math.max(0, s.lostMs) * s.samples) / 1000).toFixed(1)}s{" "}
                      <span class="text-sm text-sub">
                        {Math.round(s.lostMs)}ms each
                      </span>
                    </td>
                    <td
                      class={cn("px-3 py-2", {
                        "text-error": s.trend > 0.15,
                        "text-main": s.trend < -0.15,
                        "text-sub": Math.abs(s.trend) <= 0.15,
                      })}
                    >
                      {s.trend > 0.15
                        ? "▲ worse"
                        : s.trend < -0.15
                          ? "▼ better"
                          : "–"}
                    </td>
                    <td class="px-3 py-2 whitespace-nowrap text-sub">
                      {Math.round((1 - s.recall) * 100)}% due ·{" "}
                      {s.stat.st.toFixed(1)}d
                    </td>
                    <td class="px-3 py-2 text-sub">{s.samples}</td>
                  </tr>
                )}
              </For>
            </tbody>
          </table>
        </div>
        <Show when={rows().length > limit()}>
          <Button
            variant="button"
            text={`show more (${rows().length - limit()} hidden)`}
            onClick={() => setLimit(limit() + 100)}
          />
        </Show>
      </Show>
    </div>
  );
}

import { createMemo, For, JSXElement, Show } from "solid-js";

import { errorBreakdown, errorTypeInfo } from "../../../adaptive/insights";
import { getProfile, version } from "../../../adaptive/session";
import { Card, Empty, Meter, pct, show } from "./shared";

export function ErrorsTab(): JSXElement {
  const profile = createMemo(() => {
    version();
    return getProfile();
  });
  const breakdown = createMemo(() => errorBreakdown(profile()));
  const pairs = createMemo(() =>
    Object.entries(profile().conf)
      .filter(([, count]) => count >= 0.5)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 30),
  );
  const maxPair = (): number => pairs()[0]?.[1] ?? 1;

  return (
    <div class="grid gap-6 xl:grid-cols-2">
      <Card title="what kind of mistakes" icon="fa-bug">
        <Show
          when={breakdown().length > 0}
          fallback={<Empty text="No errors recorded yet." />}
        >
          <div class="grid grid-cols-[auto_1fr_auto] items-center gap-x-4 gap-y-3">
            <For each={breakdown()}>
              {(row) => (
                <>
                  <div>
                    <div class="text-text">{errorTypeInfo[row.type].label}</div>
                    <div class="max-w-72 text-xs text-sub">
                      {errorTypeInfo[row.type].help}
                    </div>
                  </div>
                  <Meter value={row.share / (breakdown()[0]?.share ?? 1)} />
                  <div class="text-right whitespace-nowrap">
                    {pct(row.share, 0)}{" "}
                    <span class="text-sm text-sub">({row.count})</span>
                  </div>
                </>
              )}
            </For>
          </div>
        </Show>
      </Card>
      <Card title="letter confusions (expected → typed)" icon="fa-random">
        <Show
          when={pairs().length > 0}
          fallback={<Empty text="No confusions recorded yet." />}
        >
          <div class="grid grid-cols-2 gap-x-8 gap-y-2 md:grid-cols-3">
            <For each={pairs()}>
              {([pair, count]) => {
                const [exp, typed] = pair.split(">") as [string, string];
                return (
                  <div class="grid grid-cols-[auto_1fr] items-center gap-3">
                    <div class="text-xl whitespace-pre">
                      <span class="text-main">{show(exp)}</span>
                      <span class="text-sub"> → </span>
                      <span class="text-error">{show(typed)}</span>
                    </div>
                    <Meter value={count / maxPair()} />
                  </div>
                );
              }}
            </For>
          </div>
          <div class="mt-4 text-xs text-sub">
            Recency-weighted: old confusions fade as you stop making them.
          </div>
        </Show>
      </Card>
    </div>
  );
}

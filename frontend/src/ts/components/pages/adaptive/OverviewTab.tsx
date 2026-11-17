// oxlint-disable monkeytype-rules/one-component-per-file
import { createMemo, For, JSXElement, Show } from "solid-js";

import {
  selectTargets,
  Target,
  targetLabel,
  typeLabel,
} from "../../../adaptive/generate";
import { buildInsights, potentialGain } from "../../../adaptive/insights";
import { Scored, weaknessIndex } from "../../../adaptive/model";
import {
  activePlan,
  getProfile,
  isTraining,
  settings,
  updateSettings,
  version,
} from "../../../adaptive/session";
import { FocusPreset, presets } from "../../../adaptive/settings";
import { startTraining, stopTraining } from "../../../adaptive/start";
import { FaSolidIcon } from "../../../types/font-awesome";
import { cn } from "../../../utils/cn";
import { Button } from "../../common/Button";
import { Fa } from "../../common/Fa";
import { Card, Empty, StatTile } from "./shared";

function TargetChip(props: { target: Target }): JSXElement {
  return (
    <div class="flex items-baseline gap-2 rounded bg-bg px-3 py-2">
      <span class="text-xl text-main">{targetLabel(props.target)}</span>
      <span class="text-xs text-sub">
        {typeLabel(props.target.type)} · {props.target.reason}
      </span>
    </div>
  );
}

export function OverviewTab(props: { scored: Scored[] }): JSXElement {
  const profile = createMemo(() => {
    version();
    return getProfile();
  });
  const insights = createMemo(() => buildInsights(profile(), props.scored));
  const wi = createMemo(() => weaknessIndex(props.scored));
  const wiDelta = createMemo(() => {
    const s = profile().sessions;
    if (s.length < 6) return null;
    const then = s[Math.max(0, s.length - 11)]?.wi ?? 0;
    return wi() - then;
  });
  const gain = createMemo(() => potentialGain(props.scored));
  const preview = createMemo(() => {
    version();
    // point estimates: a stable preview of what the model currently ranks worst
    return selectTargets(
      profile(),
      { ...settings(), selection: "greedy" },
      Date.now(),
      Math.random,
    ).targets;
  });
  const counts = createMemo(() => {
    const out = { critical: 0, weak: 0, mastered: 0, tracked: 0 };
    for (const s of props.scored) {
      if (s.type === "c") continue;
      out.tracked++;
      if (s.level === "critical") out.critical++;
      else if (s.level === "weak") out.weak++;
      else if (s.level === "mastered" || s.level === "good") out.mastered++;
    }
    return out;
  });
  const intensity = (): number =>
    settings().autoDifficulty ? profile().g.intensity : settings().intensity;

  return (
    <div class="grid gap-6">
      <div class="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-6">
        <StatTile
          label="tests analyzed"
          value={String(profile().g.tests)}
          sub={`${profile().g.chars.toLocaleString()} keystrokes`}
        />
        <StatTile
          label="weakness index"
          value={wi().toFixed(1)}
          sub={
            wiDelta() === null
              ? "lower is better"
              : `${(wiDelta() as number) <= 0 ? "▼" : "▲"} ${Math.abs(wiDelta() as number).toFixed(1)} vs 10 tests ago`
          }
          help="Frequency-weighted average weakness of everything tracked, 0 to 100."
        />
        <StatTile
          label="potential gain"
          value={`${Math.round(gain() * 100)}%`}
          sub="time lost to weak bigrams"
          help="Share of typing time spent on bigrams being slower or more error-prone than your own average. Roughly the speed-up from fixing them."
        />
        <StatTile
          label="error cost"
          value={`${Math.round(profile().g.errCost)} ms`}
          sub="per mistake"
          help="Average time from making a mistake to being back on track (noticing, deleting, retyping)."
        />
        <StatTile
          label="weak spots"
          value={String(counts().critical + counts().weak)}
          sub={`${counts().critical} critical · ${counts().tracked} tracked`}
        />
        <StatTile
          label="intensity"
          value={`${Math.round(intensity() * 100)}%`}
          sub={settings().autoDifficulty ? "auto-adjusted" : "manual"}
          help="Share of each training test made of targeted material. Automatic difficulty moves it to keep you near your target accuracy."
        />
      </div>

      <Card title="training" icon="fa-dumbbell">
        <div class="grid gap-4">
          <div class="grid grid-cols-2 gap-2 md:grid-cols-4 xl:grid-cols-7">
            <For
              each={
                Object.entries(presets) as [
                  FocusPreset,
                  (typeof presets)[FocusPreset],
                ][]
              }
            >
              {([id, def]) => (
                <Button
                  variant="button"
                  active={settings().preset === id}
                  text={def.label}
                  balloon={{
                    text: def.description,
                    position: "up",
                    length: "medium",
                  }}
                  onClick={() => updateSettings({ ...settings(), preset: id })}
                />
              )}
            </For>
          </div>
          <div class="text-sm text-sub">
            {presets[settings().preset].description}
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <Button
              variant="button"
              class="px-6 py-3 text-xl"
              fa={{ icon: "fa-play" }}
              text={isTraining() ? "new training test" : "start training"}
              onClick={() => void startTraining()}
            />
            <Show when={isTraining()}>
              <Button
                variant="button"
                fa={{ icon: "fa-stop" }}
                text="end training"
                onClick={() => void stopTraining()}
              />
            </Show>
            <span class="text-sm text-sub">
              {settings().lengthMode === "time"
                ? `${settings().seconds}s`
                : `${settings().wordCount} words`}{" "}
              · {settings().structure} · {settings().selection} ·{" "}
              {settings().continuous ? "continuous" : "single test"}
            </span>
          </div>
        </div>
      </Card>

      <Show when={activePlan()}>
        {(plan) => (
          <Card title="current training test" icon="fa-bullseye">
            <div class="mb-3 text-sm text-sub">
              {plan().mix.targeted} targeted · {plan().mix.pseudo} pseudo-words
              · {plan().mix.drill} drills · {plan().mix.filler} filler ·
              intensity {Math.round(plan().intensity * 100)}%
            </div>
            <div class="flex flex-wrap gap-2">
              <For each={plan().targets}>
                {(t) => <TargetChip target={t} />}
              </For>
            </div>
          </Card>
        )}
      </Show>

      <div class="grid gap-6 xl:grid-cols-2">
        <Card title="what the model would target next" icon="fa-crosshairs">
          <Show
            when={preview().length > 0 && profile().g.chars >= 100}
            fallback={
              <Empty text="No data yet. Type a few normal tests: analysis runs in the background." />
            }
          >
            <div class="flex flex-wrap gap-2">
              <For each={preview()}>{(t) => <TargetChip target={t} />}</For>
            </div>
          </Show>
        </Card>
        <Card title="insights" icon="fa-lightbulb">
          <Show
            when={insights().length > 0}
            fallback={
              <Empty text="Insights appear once there is enough data." />
            }
          >
            <div class="grid gap-3">
              <For each={insights()}>
                {(insight) => (
                  <div class="grid grid-cols-[auto_1fr_auto] items-start gap-3">
                    <Fa
                      icon={insight.icon as FaSolidIcon}
                      fixedWidth
                      class="pt-1 text-main"
                    />
                    <div>
                      <div class="text-text">{insight.title}</div>
                      <div class="text-sm text-sub">{insight.text}</div>
                    </div>
                    <Show when={insight.preset}>
                      <Button
                        variant="text"
                        class={cn("text-sm")}
                        fa={{ icon: "fa-play" }}
                        text={insight.preset}
                        balloon={{ text: "train this now", position: "left" }}
                        onClick={() =>
                          void startTraining(insight.preset as FocusPreset)
                        }
                      />
                    </Show>
                  </div>
                )}
              </For>
            </div>
          </Show>
        </Card>
      </div>
    </div>
  );
}

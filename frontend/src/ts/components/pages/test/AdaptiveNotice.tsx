import { For, JSXElement, Show } from "solid-js";

import { targetLabel } from "../../../adaptive/generate";
import { activePlan, settings } from "../../../adaptive/session";
import { presets } from "../../../adaptive/settings";
import { stopTraining } from "../../../adaptive/start";
import { isFocusMode } from "../../../states/test";
import { cn } from "../../../utils/cn";
import { Button } from "../../common/Button";
import { Fa } from "../../common/Fa";

/** Shown above the words during adaptive training: what this test targets. */
export function AdaptiveNotice(): JSXElement {
  return (
    <Show when={activePlan()}>
      {(plan) => (
        <div
          class={cn(
            "flex flex-wrap items-center justify-center gap-x-3 gap-y-1 pt-3 text-sm text-sub transition-opacity duration-125",
            { "pointer-events-none opacity-0": isFocusMode() },
          )}
        >
          <span class="text-main">
            <Fa icon="fa-brain" /> adaptive · {presets[settings().preset].label}
          </span>
          <Show
            when={plan().targets.length > 0}
            fallback={<span>collecting data, mostly normal words for now</span>}
          >
            <span>targets</span>
            <For each={plan().targets.slice(0, 10)}>
              {(t) => (
                <span
                  class="rounded bg-sub-alt px-2 py-0.5 whitespace-pre text-text"
                  aria-label={t.reason}
                  data-balloon-pos="down"
                >
                  {targetLabel(t)}
                </span>
              )}
            </For>
            <span>· {Math.round(plan().intensity * 100)}% intensity</span>
          </Show>
          <Button
            variant="text"
            class="p-0 text-sm"
            fa={{ icon: "fa-times" }}
            text="exit"
            onClick={() => void stopTraining()}
          />
          <Button
            variant="text"
            class="p-0 text-sm"
            fa={{ icon: "fa-chart-bar" }}
            text="details"
            to="/adaptive"
          />
        </div>
      )}
    </Show>
  );
}

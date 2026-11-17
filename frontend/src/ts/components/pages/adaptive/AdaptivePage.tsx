import { createSignal, For, JSXElement, Match, Show, Switch } from "solid-js";

import { isTraining, settings } from "../../../adaptive/session";
import { FaSolidIcon } from "../../../types/font-awesome";
import { Button } from "../../common/Button";
import { H2 } from "../../common/Headers";
import { ErrorsTab } from "./ErrorsTab";
import { KeyboardTab } from "./KeyboardTab";
import { OverviewTab } from "./OverviewTab";
import { ProgressTab } from "./ProgressTab";
import { SettingsTab } from "./SettingsTab";
import { createScored } from "./shared";
import { UnitsTab } from "./UnitsTab";

type Tab =
  | "overview"
  | "units"
  | "keyboard"
  | "errors"
  | "progress"
  | "settings";

const tabs: { id: Tab; label: string; icon: FaSolidIcon }[] = [
  { id: "overview", label: "overview", icon: "fa-brain" },
  { id: "units", label: "weak spots", icon: "fa-list-ol" },
  { id: "keyboard", label: "keyboard", icon: "fa-keyboard" },
  { id: "errors", label: "errors", icon: "fa-bug" },
  { id: "progress", label: "progress", icon: "fa-chart-line" },
  { id: "settings", label: "settings", icon: "fa-cog" },
];

/** The adaptive trainer: analysis of passively collected data + training control. */
export function AdaptivePage(): JSXElement {
  const [tab, setTab] = createSignal<Tab>("overview");
  const scored = createScored();

  return (
    <div class="content-grid grid content-start gap-6 pb-8">
      <div class="flex flex-wrap items-end justify-between gap-4">
        <H2 class="pb-0" fa={{ icon: "fa-brain" }} text="adaptive trainer" />
        <div class="text-sm text-sub">
          <Show
            when={settings().enabled}
            fallback={<span class="text-error">passive analysis is off</span>}
          >
            passive analysis is on
          </Show>
          <Show when={isTraining()}>
            {" · "}
            <span class="text-main">training in progress</span>
          </Show>
        </div>
      </div>
      <div class="flex flex-wrap gap-2">
        <For each={tabs}>
          {(t) => (
            <Button
              variant="button"
              active={tab() === t.id}
              fa={{ icon: t.icon, fixedWidth: true }}
              text={t.label}
              onClick={() => setTab(t.id)}
            />
          )}
        </For>
      </div>
      <Switch>
        <Match when={tab() === "overview"}>
          <OverviewTab scored={scored()} />
        </Match>
        <Match when={tab() === "units"}>
          <UnitsTab scored={scored()} />
        </Match>
        <Match when={tab() === "keyboard"}>
          <KeyboardTab scored={scored()} />
        </Match>
        <Match when={tab() === "errors"}>
          <ErrorsTab />
        </Match>
        <Match when={tab() === "progress"}>
          <ProgressTab />
        </Match>
        <Match when={tab() === "settings"}>
          <SettingsTab />
        </Match>
      </Switch>
    </div>
  );
}

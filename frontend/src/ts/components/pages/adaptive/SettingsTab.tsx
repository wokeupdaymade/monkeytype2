// oxlint-disable monkeytype-rules/one-component-per-file
import { createSignal, For, JSXElement, Match, Show, Switch } from "solid-js";

import {
  exportData,
  getProfile,
  importData,
  listProfiles,
  profileId,
  resetProfile,
  resetSettings,
  settings,
  updateSettings,
  version,
} from "../../../adaptive/session";
import {
  defaultSettings,
  getPath,
  SettingField,
  settingGroups,
  setPath,
} from "../../../adaptive/settings";
import {
  showErrorNotification,
  showSuccessNotification,
} from "../../../states/notifications";
import { FaSolidIcon } from "../../../types/font-awesome";
import { cn } from "../../../utils/cn";
import { Button } from "../../common/Button";
import { Fa } from "../../common/Fa";
import { Card } from "./shared";

function set(path: string, value: unknown): void {
  updateSettings(setPath(settings(), path, value));
}

function Field(props: { field: SettingField }): JSXElement {
  const value = (): unknown => getPath(settings(), props.field.path);
  const changed = (): boolean =>
    value() !== getPath(defaultSettings, props.field.path);
  return (
    <div class="grid grid-cols-1 items-center gap-x-6 gap-y-2 py-2 md:grid-cols-[1fr_auto]">
      <div>
        <div class="flex items-center gap-2 text-text">
          {props.field.label}
          <Show when={changed()}>
            <button
              type="button"
              class="cursor-pointer text-xs text-sub hover:text-text"
              aria-label="reset to default"
              data-balloon-pos="right"
              onClick={() =>
                set(
                  props.field.path,
                  getPath(defaultSettings, props.field.path),
                )
              }
            >
              <Fa icon="fa-undo" />
            </button>
          </Show>
        </div>
        <div class="text-sm text-sub">{props.field.help}</div>
      </div>
      <Switch>
        <Match when={props.field.kind === "toggle"}>
          <div class="flex gap-2">
            <Button
              variant="button"
              class="w-16"
              active={value() === false}
              text="off"
              onClick={() => set(props.field.path, false)}
            />
            <Button
              variant="button"
              class="w-16"
              active={value() === true}
              text="on"
              onClick={() => set(props.field.path, true)}
            />
          </div>
        </Match>
        <Match when={props.field.kind === "number" && props.field}>
          {(f) => {
            const field = f();
            const commit = (raw: string): void => {
              const parsed = Number(raw);
              if (!Number.isFinite(parsed)) return;
              set(field.path, Math.min(field.max, Math.max(field.min, parsed)));
            };
            return (
              <div class="flex items-center gap-3">
                <input
                  type="range"
                  class="w-40"
                  min={field.min}
                  max={field.max}
                  step={field.step}
                  value={value() as number}
                  onInput={(e) => commit(e.currentTarget.value)}
                />
                <input
                  type="number"
                  class="w-24 text-right"
                  min={field.min}
                  max={field.max}
                  step={field.step}
                  value={value() as number}
                  onChange={(e) => commit(e.currentTarget.value)}
                />
                <span class="w-14 text-sm text-sub">{field.unit ?? ""}</span>
              </div>
            );
          }}
        </Match>
        <Match when={props.field.kind === "select" && props.field}>
          {(f) => (
            <div class="flex flex-wrap justify-end gap-2">
              <For each={f().options}>
                {(opt) => (
                  <Button
                    variant="button"
                    active={value() === opt.value}
                    text={opt.label}
                    onClick={() => set(props.field.path, opt.value)}
                  />
                )}
              </For>
            </div>
          )}
        </Match>
        <Match when={props.field.kind === "text"}>
          <input
            class="w-56"
            value={value() as string}
            onChange={(e) =>
              set(props.field.path, e.currentTarget.value.trim() || "auto")
            }
          />
        </Match>
      </Switch>
    </div>
  );
}

export function SettingsTab(): JSXElement {
  const [importText, setImportText] = createSignal("");
  const [confirmReset, setConfirmReset] = createSignal(false);
  const [query, setQuery] = createSignal("");

  const download = (): void => {
    const blob = new Blob([exportData()], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `adaptive-trainer-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };
  const matches = (f: SettingField): boolean => {
    const q = query().toLowerCase();
    return q === "" || f.label.includes(q) || f.help.toLowerCase().includes(q);
  };
  const stats = (): string => {
    version();
    const p = getProfile();
    return `profile "${profileId()}": ${Object.keys(p.units).length} tracked units, ${p.sessions.length} sessions`;
  };

  return (
    <div class="grid gap-6">
      <div class="flex flex-wrap items-center gap-3">
        <input
          class="w-64"
          placeholder="search settings..."
          value={query()}
          onInput={(e) => setQuery(e.currentTarget.value)}
        />
        <div class="grow"></div>
        <Button
          variant="button"
          fa={{ icon: "fa-undo" }}
          text="reset all settings"
          onClick={() => {
            resetSettings();
            showSuccessNotification("Adaptive trainer settings reset");
          }}
        />
      </div>
      <For each={settingGroups}>
        {(group) => (
          <Show when={group.fields.some(matches)}>
            <section>
              <h3 class="flex items-center gap-2 text-2xl text-sub">
                <Fa icon={group.icon as FaSolidIcon} fixedWidth />
                {group.title}
              </h3>
              <div class="mb-2 text-sm text-sub">{group.description}</div>
              <div class="grid divide-y divide-sub-alt">
                <For each={group.fields.filter(matches)}>
                  {(field) => <Field field={field} />}
                </For>
              </div>
            </section>
          </Show>
        )}
      </For>

      <Card title="data" icon="fa-database">
        <div class="grid gap-4">
          <div class="text-sm text-sub">
            {stats()}. Everything is stored in this browser only.
            <Show when={listProfiles().length > 1}>
              {" "}
              Other profiles:{" "}
              {listProfiles()
                .filter((p) => p !== profileId())
                .join(", ")}
              .
            </Show>
          </div>
          <div class="flex flex-wrap gap-3">
            <Button
              variant="button"
              fa={{ icon: "fa-download" }}
              text="export"
              onClick={download}
            />
            <Button
              variant="button"
              fa={{ icon: "fa-copy" }}
              text="copy export"
              onClick={() => {
                void navigator.clipboard
                  .writeText(exportData())
                  .then(() => showSuccessNotification("Copied"));
              }}
            />
            <Button
              variant="button"
              danger={confirmReset()}
              fa={{ icon: "fa-trash" }}
              text={
                confirmReset()
                  ? "click again to erase this profile"
                  : "reset profile"
              }
              onClick={() => {
                if (!confirmReset()) {
                  setConfirmReset(true);
                  return;
                }
                resetProfile();
                setConfirmReset(false);
                showSuccessNotification("Adaptive profile erased");
              }}
            />
          </div>
          <textarea
            class={cn("h-24 w-full text-sm")}
            placeholder="paste an export here to import it (replaces the current profile and settings)"
            value={importText()}
            onInput={(e) => setImportText(e.currentTarget.value)}
          ></textarea>
          <div>
            <Button
              variant="button"
              disabled={importText().trim() === ""}
              fa={{ icon: "fa-upload" }}
              text="import"
              onClick={() => {
                if (importData(importText())) {
                  setImportText("");
                  showSuccessNotification("Adaptive profile imported");
                } else {
                  showErrorNotification(
                    "That is not a valid adaptive trainer export",
                  );
                }
              }}
            />
          </div>
        </div>
      </Card>
    </div>
  );
}

// oxlint-disable monkeytype-rules/one-component-per-file
import { Accessor, createMemo, JSXElement, Show } from "solid-js";

import { Level, Scored, scoreAll } from "../../../adaptive/model";
import { getProfile, settings, version } from "../../../adaptive/session";
import { FaSolidIcon } from "../../../types/font-awesome";
import { cn } from "../../../utils/cn";
import { Fa } from "../../common/Fa";

/** Every unit scored with point estimates; recomputed when the profile changes. */
export function createScored(): Accessor<Scored[]> {
  const scored = createMemo(() => {
    version();
    return scoreAll(getProfile(), settings(), { now: Date.now() });
  });
  return scored;
}

export const levelClass: Record<Level, string> = {
  new: "text-sub",
  critical: "text-error",
  weak: "text-error",
  fair: "text-text",
  good: "text-main",
  mastered: "text-main",
};

export function Card(props: {
  title?: string;
  icon?: string;
  class?: string;
  children: JSXElement;
}): JSXElement {
  return (
    <div class={cn("rounded bg-sub-alt p-4", props.class)}>
      <Show when={props.title}>
        <div class="mb-3 flex items-center gap-2 text-sub">
          <Show when={props.icon}>
            <Fa icon={props.icon as FaSolidIcon} fixedWidth />
          </Show>
          {props.title}
        </div>
      </Show>
      {props.children}
    </div>
  );
}

export function StatTile(props: {
  label: string;
  value: string;
  sub?: string;
  help?: string;
}): JSXElement {
  return (
    <div
      class="rounded bg-sub-alt p-4"
      aria-label={props.help}
      data-balloon-pos="up"
      data-balloon-length="large"
    >
      <div class="text-sm text-sub">{props.label}</div>
      <div class="text-3xl leading-tight text-main">{props.value}</div>
      <Show when={props.sub}>
        <div class="text-xs text-sub">{props.sub}</div>
      </Show>
    </div>
  );
}

/** A 0..1 meter. Heat blends from the sub colour to the error colour. */
export function Meter(props: { value: number; class?: string }): JSXElement {
  const pct = (): number =>
    Math.round(Math.min(1, Math.max(0, props.value)) * 100);
  return (
    <div
      class={cn("h-[0.5em] w-full overflow-hidden rounded bg-bg", props.class)}
    >
      <div
        class="h-full rounded"
        style={{
          width: `${pct()}%`,
          background: `color-mix(in srgb, var(--error-color) ${pct()}%, var(--main-color))`,
        }}
      ></div>
    </div>
  );
}

export function Empty(props: { text: string }): JSXElement {
  return <div class="p-8 text-center text-sub">{props.text}</div>;
}

export function show(text: string): string {
  return text.replace(/ /g, "␣");
}

export function pct(value: number, digits = 1): string {
  return `${(value * 100).toFixed(digits)}%`;
}

/** ms per keystroke as words per minute (5 chars per word). */
export function msToWpm(ms: number): number {
  return ms > 0 ? 12000 / ms : 0;
}

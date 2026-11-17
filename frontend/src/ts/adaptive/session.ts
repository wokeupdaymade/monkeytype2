// Glue between the adaptive engine and monkeytype: storage, passive capture
// of finished tests, starting / continuing / leaving training sessions and
// passive blending. Must not import test-logic (it imports this module).

import { createEffect, createRoot, createSignal, on } from "solid-js";
import { CustomTextSettings } from "@monkeytype/schemas/results";
import { Mode } from "@monkeytype/schemas/shared";

import { setConfig } from "../config/setters";
import { Config } from "../config/store";
import { configEvent } from "../events/config";
import { setCustomTextIndicator } from "../states/core";
import {
  showErrorNotification,
  showNoticeNotification,
} from "../states/notifications";
import { getLastEventLog, getLastResult } from "../states/test";
import * as CustomText from "../test/custom-text";
import { cachedFetchJson } from "../utils/json-data";
import { extract, ingest } from "./analyze";
import { generate, PassiveBlender, Plan, targetLabel } from "./generate";
import { buildGeometry, Geometry, qwertyGeometry } from "./geometry";
import { newProfile, Profile, typeOf } from "./model";
import {
  AdaptiveSettings,
  defaultSettings,
  presets,
  sanitizeSettings,
} from "./settings";

const settingsKey = "adaptiveSettings";
const profilePrefix = "adaptiveProfile:";

// ------------------------------------------------------------ settings

function loadSettings(): AdaptiveSettings {
  try {
    const raw = localStorage.getItem(settingsKey);
    if (raw !== null) return sanitizeSettings(JSON.parse(raw));
  } catch (e) {
    console.error("adaptive: could not read settings", e);
  }
  return structuredClone(defaultSettings);
}

const [settings, setSettingsSignal] =
  createSignal<AdaptiveSettings>(loadSettings());
export { settings };

export function updateSettings(next: AdaptiveSettings): void {
  const clean = sanitizeSettings(next);
  const scopeChanged = clean.profileScope !== settings().profileScope;
  const layoutChanged = clean.layout !== settings().layout;
  setSettingsSignal(clean);
  try {
    localStorage.setItem(settingsKey, JSON.stringify(clean));
  } catch (e) {
    console.error("adaptive: could not save settings", e);
  }
  if (scopeChanged) loadedProfileId = null;
  if (layoutChanged) void loadGeometry();
  bumpVersion();
}

export function resetSettings(): void {
  updateSettings(structuredClone(defaultSettings));
}

// ------------------------------------------------------------ geometry

let geometry: Geometry = qwertyGeometry;

function layoutName(): string {
  const wanted = settings().layout.trim().toLowerCase();
  if (wanted !== "" && wanted !== "auto") return wanted;
  return Config.layout === "default" ? "qwerty" : Config.layout;
}

async function loadGeometry(): Promise<void> {
  const name = layoutName();
  if (geometry.name === name) return;
  try {
    const layout = await cachedFetchJson<{
      type?: string;
      keys: Record<string, string[][]>;
    }>(`/layouts/${name}.json`);
    geometry = buildGeometry(name, layout);
  } catch {
    geometry = qwertyGeometry;
  }
  bumpVersion();
}

export function getGeometry(): Geometry {
  return geometry;
}

// ------------------------------------------------------------ profile

let profile: Profile = newProfile(Date.now());
let loadedProfileId: string | null = null;

/** Bumped whenever the profile or anything derived from it changes. */
const [version, setVersion] = createSignal(0);
export { version };
function bumpVersion(): void {
  setVersion((v) => v + 1);
}

export function profileId(): string {
  const scope = settings().profileScope;
  const parts: string[] = [];
  if (scope.includes("language")) parts.push(Config.language);
  if (scope.includes("layout")) parts.push(layoutName());
  return parts.length === 0 ? "global" : parts.join("|");
}

function isProfile(value: unknown): value is Profile {
  const p = value as Profile | null;
  return (
    typeof p === "object" &&
    p?.v === 1 &&
    typeof p.units === "object" &&
    Array.isArray(p.sessions) &&
    typeof p.g === "object"
  );
}

export function getProfile(): Profile {
  const id = profileId();
  if (loadedProfileId !== id) {
    loadedProfileId = id;
    profile = newProfile(Date.now(), settings().intensity);
    try {
      const raw = localStorage.getItem(profilePrefix + id);
      if (raw !== null) {
        const parsed: unknown = JSON.parse(raw);
        if (isProfile(parsed)) profile = parsed;
      }
    } catch (e) {
      console.error("adaptive: could not read profile", e);
    }
  }
  return profile;
}

function round(value: number): number {
  return Math.round(value * 1000) / 1000;
}

function saveProfile(): void {
  if (loadedProfileId === null) return;
  try {
    // 3 decimals is plenty and roughly halves the stored size
    const json = JSON.stringify(profile, (_key, value: unknown) =>
      typeof value === "number" ? round(value) : value,
    );
    localStorage.setItem(profilePrefix + loadedProfileId, json);
  } catch (e) {
    console.error("adaptive: could not save profile", e);
    showErrorNotification(
      "Adaptive trainer could not save its profile (storage full?). Lower 'max tracked units' in its settings.",
    );
  }
}

export function resetProfile(): void {
  getProfile();
  profile = newProfile(Date.now(), settings().intensity);
  saveProfile();
  bumpVersion();
}

export function exportData(): string {
  return JSON.stringify(
    { adaptiveExport: 1, settings: settings(), profile: getProfile() },
    null,
    1,
  );
}

export function importData(json: string): boolean {
  try {
    const data = JSON.parse(json) as {
      settings?: unknown;
      profile?: unknown;
    };
    if (!isProfile(data.profile)) return false;
    if (data.settings !== undefined) {
      updateSettings(sanitizeSettings(data.settings));
    }
    getProfile();
    profile = data.profile;
    saveProfile();
    bumpVersion();
    return true;
  } catch {
    return false;
  }
}

export function listProfiles(): string[] {
  const out: string[] = [];
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i);
    if (key?.startsWith(profilePrefix)) {
      out.push(key.slice(profilePrefix.length));
    }
  }
  return out;
}

// ------------------------------------------------------------ word pool

async function loadPool(): Promise<string[]> {
  const wanted = settings().wordPool.trim().toLowerCase();
  const name = wanted === "" || wanted === "test" ? Config.language : wanted;
  try {
    const lang = await cachedFetchJson<{ words: string[] }>(
      `/languages/${name}.json`,
    );
    return lang.words;
  } catch {
    if (name !== Config.language) {
      showNoticeNotification(
        `Adaptive trainer: word pool "${name}" not found, using ${Config.language}.`,
      );
      const lang = await cachedFetchJson<{ words: string[] }>(
        `/languages/${Config.language}.json`,
      );
      return lang.words;
    }
    throw new Error("could not load word pool");
  }
}

// ------------------------------------------------------------ sessions

type Before = {
  mode: Mode;
  punctuation: boolean;
  numbers: boolean;
  customText: CustomTextSettings;
};

let before: Before | null = null;
let ownModeChange = false;
let freshPlan = false;
let lastPlanAnalyzed = true;

const [activePlan, setActivePlan] = createSignal<Plan | null>(null);
/** The plan of the running training session, null when not training. */
export { activePlan };

export function isTraining(): boolean {
  return activePlan() !== null;
}

async function buildPlan(): Promise<Plan> {
  const cfg = settings();
  await loadGeometry();
  const pool = await loadPool();
  const p = getProfile();
  let count = cfg.wordCount;
  if (cfg.lengthMode === "time") {
    // enough words that even a fast typist does not loop
    const wpm = Math.max(60, p.g.wpm * 1.5);
    count = Math.ceil((cfg.seconds / 60) * wpm) + 10;
  }
  return generate({
    profile: p,
    cfg,
    pool,
    geo: geometry,
    now: Date.now(),
    count,
  });
}

function applyPlan(plan: Plan): void {
  const cfg = settings();
  CustomText.setPipeDelimiter(false);
  CustomText.setText(plan.words);
  CustomText.setMode("repeat");
  if (cfg.lengthMode === "time") {
    CustomText.setLimitMode("time");
    CustomText.setLimitValue(cfg.seconds);
  } else {
    CustomText.setLimitMode("word");
    CustomText.setLimitValue(plan.words.length);
  }
  setCustomTextIndicator({
    name: `adaptive: ${presets[cfg.preset].label}`,
    isLong: false,
  });
  setActivePlan(plan);
  lastPlanAnalyzed = false;
}

/**
 * Prepares a training test (custom text + mode). The caller restarts the
 * test or navigates to the test page afterwards.
 */
export async function prepareTraining(): Promise<boolean> {
  let plan: Plan;
  try {
    plan = await buildPlan();
  } catch (e) {
    console.error(e);
    showErrorNotification("Adaptive trainer could not generate a test.");
    return false;
  }
  if (plan.words.length === 0) {
    showNoticeNotification(
      "Adaptive trainer: no usable words in the pool (check the word length limits).",
    );
    return false;
  }
  before ??= {
    mode: Config.mode,
    punctuation: Config.punctuation,
    numbers: Config.numbers,
    customText: structuredClone(CustomText.getData()),
  };
  applyPlan(plan);
  ownModeChange = true;
  setConfig("mode", "custom", { nosave: true });
  ownModeChange = false;
  freshPlan = true;
  if (!plan.informed) {
    showNoticeNotification(
      "Adaptive trainer has little data yet, so this test is mostly normal words. It sharpens as you type.",
      { durationMs: 5000 },
    );
  }
  return true;
}

function restoreBefore(restoreMode: boolean): void {
  if (before === null) return;
  const b = before;
  before = null;
  CustomText.setText(b.customText.text);
  CustomText.setMode(b.customText.mode);
  CustomText.setLimitMode(b.customText.limit.mode);
  CustomText.setLimitValue(b.customText.limit.value);
  CustomText.setPipeDelimiter(b.customText.pipeDelimiter);
  setCustomTextIndicator(undefined);
  if (!restoreMode) return;
  ownModeChange = true;
  setConfig("punctuation", b.punctuation);
  setConfig("numbers", b.numbers);
  setConfig("mode", b.mode);
  ownModeChange = false;
}

/** Leave training and go back to the mode that was active before it. */
export function endTraining(): void {
  if (!isTraining()) return;
  setActivePlan(null);
  restoreBefore(true);
}

/**
 * Called by restartTest before it resets the test. While training, a restart
 * either builds the next adaptive test or returns to the previous mode.
 */
export async function beforeRestart(options: {
  withSameWordset?: boolean;
}): Promise<void> {
  if (!isTraining()) return;
  if (freshPlan) {
    freshPlan = false;
    return;
  }
  if (options.withSameWordset === true) return;
  if (!settings().continuous) {
    showNoticeNotification("Leaving adaptive training.");
    endTraining();
    return;
  }
  try {
    const plan = await buildPlan();
    if (plan.words.length > 0) applyPlan(plan);
  } catch (e) {
    console.error("adaptive: could not build next test", e);
  }
}

// ------------------------------------------------------------ passive blend

const blender = new PassiveBlender();

/** Hook for the word generator in normal time / words tests. */
export function blendWord(wordset: string[], candidate: string): string {
  const cfg = settings();
  if (cfg.passiveBlend <= 0 || !cfg.enabled) return candidate;
  if (Config.mode !== "time" && Config.mode !== "words") return candidate;
  if (Config.funbox.length > 0) return candidate;
  return (
    blender.pick(wordset, getProfile(), cfg, geometry, version(), Date.now()) ??
    candidate
  );
}

// ------------------------------------------------------------ capture

function shouldAnalyze(
  mode: string,
  funbox: unknown,
  training: boolean,
): boolean {
  const cfg = settings();
  if (!cfg.enabled) return false;
  if (training) return cfg.analyzeAdaptiveTests;
  if (Array.isArray(funbox) && funbox.length > 0 && !cfg.analyzeFunboxTests) {
    return false;
  }
  switch (mode) {
    case "time":
      return cfg.analyzeTime;
    case "words":
      return cfg.analyzeWords;
    case "quote":
      return cfg.analyzeQuote;
    case "custom":
      return cfg.analyzeCustom;
    default:
      return false;
  }
}

function analyzeFinishedTest(): void {
  const log = getLastEventLog();
  const result = getLastResult();
  if (log === null || result === null) return;
  const training = isTraining() && !lastPlanAnalyzed;
  if (!shouldAnalyze(log.context.mode, result.funbox, training)) return;
  if (log.context.hasKorean) return;
  const cfg = settings();
  if (result.acc < cfg.minTestAccuracy) return;

  const ex = extract(log, cfg, geometry);
  if (ex.chars < cfg.minTestChars) return;

  const p = getProfile();
  const report = ingest(p, ex, cfg, Date.now(), {
    wpm: result.wpm,
    acc: result.acc,
    mode: training ? "adaptive" : log.context.mode,
    adaptive: training,
    intensity: training ? activePlan()?.intensity : undefined,
  });
  if (training) lastPlanAnalyzed = true;
  saveProfile();
  bumpVersion();

  if (cfg.notifyAfterTest && report.weakest.length > 0) {
    const list = report.weakest
      .slice(0, 4)
      .map((u) => targetLabel({ type: typeOf(u.id), id: u.id }))
      .join("  ");
    showNoticeNotification(`Weak spots in this test: ${list}`, {
      durationMs: 4000,
      customTitle: "Adaptive trainer",
    });
  }
}

let initialized = false;

/** Start listening for finished tests. Called once at boot. */
export function initAdaptive(): void {
  if (initialized) return;
  initialized = true;
  void loadGeometry();
  createRoot(() => {
    createEffect(
      on(
        getLastEventLog,
        () => {
          try {
            analyzeFinishedTest();
          } catch (e) {
            console.error("adaptive: analysis failed", e);
          }
        },
        { defer: true },
      ),
    );
  });
  configEvent.subscribe(({ key }) => {
    if (key === "mode" && !ownModeChange && isTraining()) {
      // the user picked another mode: training is over. Give them their own
      // custom text back, but keep the mode they just chose
      setActivePlan(null);
      restoreBefore(false);
    }
    if (key === "layout") void loadGeometry();
    if (key === "language" && settings().profileScope.includes("language")) {
      bumpVersion();
    }
  });
}

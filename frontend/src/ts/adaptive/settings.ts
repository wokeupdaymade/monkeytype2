// Adaptive trainer settings: defaults, presets and the schema the settings UI
// is rendered from. Pure module (no DOM / Solid) so the engine stays testable.

export type FocusPreset =
  | "smart"
  | "accuracy"
  | "speed"
  | "consistency"
  | "keys"
  | "bigrams"
  | "trigrams"
  | "syllables"
  | "words"
  | "fingers"
  | "confusions"
  | "review"
  | "explore"
  | "custom";

export type ComponentWeights = {
  accuracy: number;
  speed: number;
  consistency: number;
  hesitation: number;
  trend: number;
  forgetting: number;
  exploration: number;
};

export type TypeWeights = {
  key: number;
  bigram: number;
  trigram: number;
  syllable: number;
  word: number;
  category: number;
};

export type TriState = "off" | "auto" | "on";

export type AdaptiveSettings = {
  // --- passive analysis
  enabled: boolean;
  analyzeTime: boolean;
  analyzeWords: boolean;
  analyzeQuote: boolean;
  analyzeCustom: boolean;
  analyzeAdaptiveTests: boolean;
  analyzeFunboxTests: boolean;
  minTestChars: number;
  minTestAccuracy: number;
  maxPauseMs: number;
  hesitationFactor: number;
  notifyAfterTest: boolean;
  // --- tracking
  trackBigrams: boolean;
  trackTrigrams: boolean;
  trackSyllables: boolean;
  trackWords: boolean;
  trackSpaceNgrams: boolean;
  profileScope: "global" | "language" | "layout" | "language+layout";
  layout: string;
  maxUnits: number;
  maxSessions: number;
  // --- model
  halfLife: number;
  priorStrength: number;
  minSamples: number;
  trendFast: number;
  trendSlow: number;
  initialStability: number;
  stabilityGrowth: number;
  stabilityShrink: number;
  // --- scoring
  scoringModel: "composite" | "impact" | "hybrid";
  preset: FocusPreset;
  weights: ComponentWeights;
  typeWeights: TypeWeights;
  frequencyBias: number;
  // --- target selection
  selection: "greedy" | "softmax" | "thompson" | "ucb";
  temperature: number;
  focusCount: number;
  broadFactor: number;
  // --- generation
  structure: "interleaved" | "blocked" | "progressive";
  blockSize: number;
  lengthMode: "words" | "time";
  wordCount: number;
  seconds: number;
  wordPool: string;
  poolSize: number;
  minWordLength: number;
  maxWordLength: number;
  repeatWindow: number;
  pseudoWordRatio: number;
  drillRatio: number;
  confusionBonus: number;
  capitalization: TriState;
  capitalizationRate: number;
  punctuation: TriState;
  punctuationRate: number;
  numbers: TriState;
  numbersRate: number;
  // --- difficulty
  autoDifficulty: boolean;
  intensity: number;
  targetAccuracy: number;
  difficultyGain: number;
  minIntensity: number;
  maxIntensity: number;
  // --- session
  continuous: boolean;
  passiveBlend: number;
};

export const defaultSettings: AdaptiveSettings = {
  enabled: true,
  analyzeTime: true,
  analyzeWords: true,
  analyzeQuote: true,
  analyzeCustom: true,
  analyzeAdaptiveTests: true,
  analyzeFunboxTests: false,
  minTestChars: 40,
  minTestAccuracy: 60,
  maxPauseMs: 1500,
  hesitationFactor: 2.5,
  notifyAfterTest: false,
  trackBigrams: true,
  trackTrigrams: true,
  trackSyllables: true,
  trackWords: true,
  trackSpaceNgrams: true,
  profileScope: "global",
  layout: "auto",
  maxUnits: 12000,
  maxSessions: 400,
  halfLife: 60,
  priorStrength: 8,
  minSamples: 6,
  trendFast: 8,
  trendSlow: 40,
  initialStability: 1,
  stabilityGrowth: 2,
  stabilityShrink: 0.5,
  scoringModel: "hybrid",
  preset: "smart",
  weights: {
    accuracy: 1,
    speed: 1,
    consistency: 0.4,
    hesitation: 0.4,
    trend: 0.3,
    forgetting: 0.4,
    exploration: 0.15,
  },
  typeWeights: {
    key: 0.8,
    bigram: 1,
    trigram: 0.9,
    syllable: 0.7,
    word: 0.8,
    category: 0.4,
  },
  frequencyBias: 0.3,
  selection: "thompson",
  temperature: 0.25,
  focusCount: 8,
  broadFactor: 0.35,
  structure: "interleaved",
  blockSize: 4,
  lengthMode: "words",
  wordCount: 50,
  seconds: 60,
  wordPool: "test",
  poolSize: 5000,
  minWordLength: 1,
  maxWordLength: 20,
  repeatWindow: 6,
  pseudoWordRatio: 0.1,
  drillRatio: 0,
  confusionBonus: 0.5,
  capitalization: "off",
  capitalizationRate: 0.15,
  punctuation: "off",
  punctuationRate: 0.15,
  numbers: "off",
  numbersRate: 0.08,
  autoDifficulty: true,
  intensity: 0.6,
  targetAccuracy: 95,
  difficultyGain: 2,
  minIntensity: 0.2,
  maxIntensity: 0.95,
  continuous: true,
  passiveBlend: 0,
};

type PresetDef = {
  label: string;
  description: string;
  weights?: Partial<ComponentWeights>;
  typeWeights?: Partial<TypeWeights>;
};

const zeroTypes: TypeWeights = {
  key: 0,
  bigram: 0,
  trigram: 0,
  syllable: 0,
  word: 0,
  category: 0,
};

export const presets: Record<FocusPreset, PresetDef> = {
  smart: {
    label: "smart mix",
    description: "Balanced: whatever currently costs you the most.",
  },
  accuracy: {
    label: "accuracy",
    description: "Sequences you mistype most often.",
    weights: { accuracy: 1.6, speed: 0.2, hesitation: 0.2, consistency: 0.2 },
  },
  speed: {
    label: "speed",
    description: "Sequences you type correctly but slowly.",
    weights: { accuracy: 0.2, speed: 1.6, hesitation: 0.6 },
  },
  consistency: {
    label: "consistency",
    description: "Sequences with erratic timing and hesitations.",
    weights: { accuracy: 0.2, speed: 0.3, consistency: 1.5, hesitation: 1.2 },
  },
  keys: {
    label: "keys",
    description: "Individual weak keys.",
    typeWeights: { ...zeroTypes, key: 1 },
  },
  bigrams: {
    label: "bigrams",
    description: "Weak two-letter transitions.",
    typeWeights: { ...zeroTypes, bigram: 1 },
  },
  trigrams: {
    label: "trigrams",
    description: "Weak three-letter sequences.",
    typeWeights: { ...zeroTypes, trigram: 1 },
  },
  syllables: {
    label: "syllables",
    description: "Weak syllables and letter chunks.",
    typeWeights: { ...zeroTypes, syllable: 1 },
  },
  words: {
    label: "words",
    description: "Whole words you fumble or slow down on.",
    typeWeights: { ...zeroTypes, word: 1 },
  },
  fingers: {
    label: "fingers",
    description: "Weak fingers and motion patterns (same-finger, rolls...).",
    typeWeights: { ...zeroTypes, category: 1, bigram: 0.3 },
  },
  confusions: {
    label: "confusions",
    description: "Letters you substitute for each other.",
    weights: { accuracy: 1.5, speed: 0.1 },
    typeWeights: { ...zeroTypes, key: 1, bigram: 0.5 },
  },
  review: {
    label: "review",
    description: "Spaced repetition of past weaknesses that are due.",
    weights: {
      accuracy: 0.3,
      speed: 0.3,
      forgetting: 2,
      consistency: 0,
      hesitation: 0,
      trend: 0,
      exploration: 0,
    },
  },
  explore: {
    label: "explore",
    description: "Sequences with too little data to judge yet.",
    weights: {
      accuracy: 0.2,
      speed: 0.2,
      exploration: 2,
      consistency: 0,
      hesitation: 0,
      trend: 0,
      forgetting: 0,
    },
  },
  custom: {
    label: "custom",
    description: "Uses the weights from the settings tab as they are.",
  },
};

export function effectiveWeights(s: AdaptiveSettings): {
  weights: ComponentWeights;
  typeWeights: TypeWeights;
} {
  const p = presets[s.preset];
  if (s.preset === "custom" || s.preset === "smart") {
    return { weights: s.weights, typeWeights: s.typeWeights };
  }
  return {
    weights: { ...s.weights, ...p.weights },
    typeWeights: { ...s.typeWeights, ...p.typeWeights },
  };
}

// ---- settings UI schema

export type SettingField =
  | {
      kind: "toggle";
      path: string;
      label: string;
      help: string;
    }
  | {
      kind: "number";
      path: string;
      label: string;
      help: string;
      min: number;
      max: number;
      step: number;
      unit?: string;
    }
  | {
      kind: "select";
      path: string;
      label: string;
      help: string;
      options: { value: string; label: string }[];
    }
  | {
      kind: "text";
      path: string;
      label: string;
      help: string;
    };

export type SettingGroup = {
  title: string;
  icon: string;
  description: string;
  fields: SettingField[];
};

const tri = [
  { value: "off", label: "off" },
  { value: "auto", label: "auto" },
  { value: "on", label: "on" },
];

const t = (path: string, label: string, help: string): SettingField => ({
  kind: "toggle",
  path,
  label,
  help,
});
const n = (
  path: string,
  label: string,
  help: string,
  min: number,
  max: number,
  step: number,
  unit?: string,
): SettingField => ({
  kind: "number",
  path,
  label,
  help,
  min,
  max,
  step,
  unit,
});

export const settingGroups: SettingGroup[] = [
  {
    title: "passive analysis",
    icon: "fa-eye",
    description:
      "What gets recorded while you type normal tests. Nothing leaves your browser.",
    fields: [
      t("enabled", "analyze tests", "Master switch for passive analysis."),
      t("analyzeTime", "time mode", "Analyze tests in time mode."),
      t("analyzeWords", "words mode", "Analyze tests in words mode."),
      t("analyzeQuote", "quote mode", "Analyze quote tests."),
      t("analyzeCustom", "custom mode", "Analyze custom text tests."),
      t(
        "analyzeAdaptiveTests",
        "adaptive tests",
        "Feed training tests back into the model (recommended: this is how it sees you improve).",
      ),
      t(
        "analyzeFunboxTests",
        "funbox tests",
        "Analyze tests typed with a funbox active.",
      ),
      n(
        "minTestChars",
        "minimum characters",
        "Ignore tests shorter than this.",
        0,
        500,
        5,
      ),
      n(
        "minTestAccuracy",
        "minimum accuracy",
        "Ignore tests below this accuracy (key mashing, giving up).",
        0,
        100,
        1,
        "%",
      ),
      n(
        "maxPauseMs",
        "pause cutoff",
        "Gaps longer than this are treated as breaks, not as slow typing.",
        300,
        10000,
        50,
        "ms",
      ),
      n(
        "hesitationFactor",
        "hesitation factor",
        "A keystroke counts as a hesitation when it takes this many times your median interval.",
        1.2,
        6,
        0.1,
        "×",
      ),
      t(
        "notifyAfterTest",
        "notify after test",
        "Show a short notification with the weak spots found in each test.",
      ),
    ],
  },
  {
    title: "tracking",
    icon: "fa-layer-group",
    description: "Which levels of detail the model keeps statistics for.",
    fields: [
      t("trackBigrams", "bigrams", "Two-character transitions."),
      t("trackTrigrams", "trigrams", "Three-character sequences."),
      t("trackSyllables", "syllables", "Syllables / letter chunks of words."),
      t("trackWords", "words", "Whole words."),
      t(
        "trackSpaceNgrams",
        "word boundaries",
        "Include the space in n-grams (word starts and endings).",
      ),
      {
        kind: "select",
        path: "profileScope",
        label: "profile scope",
        help: "Keep one profile, or separate ones per language and/or keyboard layout.",
        options: [
          { value: "global", label: "one profile" },
          { value: "language", label: "per language" },
          { value: "layout", label: "per layout" },
          { value: "language+layout", label: "per language + layout" },
        ],
      },
      {
        kind: "text",
        path: "layout",
        label: "keyboard layout",
        help: "Used for finger / hand / row analysis. 'auto' follows the layout setting (qwerty when that is default). Otherwise any layout name, e.g. colemak_dh, dvorak, workman.",
      },
      n(
        "maxUnits",
        "max tracked units",
        "Upper bound on stored statistics; the least seen, oldest ones are pruned.",
        1000,
        60000,
        500,
      ),
      n(
        "maxSessions",
        "session history",
        "How many analyzed tests to keep in the progress history.",
        20,
        5000,
        10,
      ),
    ],
  },
  {
    title: "statistical model",
    icon: "fa-square-root-alt",
    description:
      "How observations are turned into estimates. Defaults are sensible; change only if you know what you want.",
    fields: [
      n(
        "halfLife",
        "memory half-life",
        "After this many new samples of a unit, old samples count half. Lower adapts faster, higher is more stable.",
        5,
        1000,
        5,
        "samples",
      ),
      n(
        "priorStrength",
        "prior strength",
        "Bayesian shrinkage: how many pseudo-samples at your average pull each estimate towards it. Stops rare units with one error from looking terrible.",
        0,
        100,
        1,
      ),
      n(
        "minSamples",
        "confidence samples",
        "Number of samples at which a unit's estimate is trusted halfway.",
        1,
        100,
        1,
      ),
      n(
        "trendFast",
        "trend fast window",
        "Fast moving average for trend detection.",
        2,
        100,
        1,
        "samples",
      ),
      n(
        "trendSlow",
        "trend slow window",
        "Slow moving average for trend detection.",
        5,
        500,
        5,
        "samples",
      ),
      n(
        "initialStability",
        "initial memory stability",
        "Spaced repetition: days until a freshly practised unit is half due again.",
        0.1,
        30,
        0.1,
        "days",
      ),
      n(
        "stabilityGrowth",
        "stability growth",
        "Multiplier applied to a unit's stability after a clean session.",
        1,
        5,
        0.1,
        "×",
      ),
      n(
        "stabilityShrink",
        "stability shrink",
        "Multiplier applied to a unit's stability after a session with errors.",
        0.1,
        1,
        0.05,
        "×",
      ),
    ],
  },
  {
    title: "weakness scoring",
    icon: "fa-balance-scale",
    description:
      "What counts as a weakness. Presets on the overview tab override the component and level weights, except 'smart mix' and 'custom', which use these.",
    fields: [
      {
        kind: "select",
        path: "scoringModel",
        label: "scoring model",
        help: "composite: weighted mix of the components below. impact: estimated milliseconds lost per occurrence (slowness + error rate × your measured correction cost). hybrid: average of both.",
        options: [
          { value: "composite", label: "composite" },
          { value: "impact", label: "impact (time lost)" },
          { value: "hybrid", label: "hybrid" },
        ],
      },
      n(
        "weights.accuracy",
        "accuracy weight",
        "Error rate above your average.",
        0,
        3,
        0.05,
      ),
      n(
        "weights.speed",
        "speed weight",
        "Latency above your average.",
        0,
        3,
        0.05,
      ),
      n(
        "weights.consistency",
        "consistency weight",
        "Timing variance above your average.",
        0,
        3,
        0.05,
      ),
      n(
        "weights.hesitation",
        "hesitation weight",
        "Frequency of long stalls.",
        0,
        3,
        0.05,
      ),
      n(
        "weights.trend",
        "trend weight",
        "Units that are currently getting worse.",
        0,
        3,
        0.05,
      ),
      n(
        "weights.forgetting",
        "forgetting weight",
        "Past weaknesses that have not been practised for a while.",
        0,
        3,
        0.05,
      ),
      n(
        "weights.exploration",
        "exploration weight",
        "Bonus for units with little data.",
        0,
        3,
        0.05,
      ),
      n("typeWeights.key", "keys level", "Weight of single keys.", 0, 2, 0.05),
      n(
        "typeWeights.bigram",
        "bigrams level",
        "Weight of bigrams.",
        0,
        2,
        0.05,
      ),
      n(
        "typeWeights.trigram",
        "trigrams level",
        "Weight of trigrams.",
        0,
        2,
        0.05,
      ),
      n(
        "typeWeights.syllable",
        "syllables level",
        "Weight of syllables.",
        0,
        2,
        0.05,
      ),
      n(
        "typeWeights.word",
        "words level",
        "Weight of whole words.",
        0,
        2,
        0.05,
      ),
      n(
        "typeWeights.category",
        "patterns level",
        "Weight of fingers and motion patterns.",
        0,
        2,
        0.05,
      ),
      n(
        "frequencyBias",
        "frequency bias",
        "0 ignores how common a unit is; 1 strongly prefers weaknesses you meet often.",
        0,
        1,
        0.05,
      ),
    ],
  },
  {
    title: "target selection",
    icon: "fa-crosshairs",
    description: "How each training test picks what to focus on.",
    fields: [
      {
        kind: "select",
        path: "selection",
        label: "selection algorithm",
        help: "greedy: always the worst units. softmax: random, weighted by score. thompson: samples each unit's plausible true weakness from its posterior, so uncertain units get tested. ucb: optimistic upper confidence bound.",
        options: [
          { value: "greedy", label: "greedy" },
          { value: "softmax", label: "softmax" },
          { value: "thompson", label: "thompson sampling" },
          { value: "ucb", label: "upper confidence bound" },
        ],
      },
      n(
        "temperature",
        "temperature",
        "Randomness of softmax selection and of word sampling. Lower is more focused.",
        0.02,
        2,
        0.01,
      ),
      n(
        "focusCount",
        "focus targets",
        "How many weaknesses one test concentrates on.",
        1,
        40,
        1,
      ),
      n(
        "broadFactor",
        "breadth",
        "How much a word's overall weakness counts besides the focus targets.",
        0,
        2,
        0.05,
      ),
    ],
  },
  {
    title: "test generation",
    icon: "fa-magic",
    description: "The shape of generated training tests.",
    fields: [
      {
        kind: "select",
        path: "structure",
        label: "structure",
        help: "interleaved: targets mixed randomly (best retention). blocked: one target at a time in groups. progressive: blocked first, then interleaved.",
        options: [
          { value: "interleaved", label: "interleaved" },
          { value: "blocked", label: "blocked" },
          { value: "progressive", label: "progressive" },
        ],
      },
      n(
        "blockSize",
        "block size",
        "Words per target in blocked sections.",
        2,
        12,
        1,
      ),
      {
        kind: "select",
        path: "lengthMode",
        label: "length mode",
        help: "End the test after a number of words or after a time.",
        options: [
          { value: "words", label: "words" },
          { value: "time", label: "time" },
        ],
      },
      n("wordCount", "word count", "Length in words mode.", 5, 500, 5),
      n("seconds", "duration", "Length in time mode.", 10, 600, 5, "s"),
      {
        kind: "text",
        path: "wordPool",
        label: "word pool",
        help: "'test' uses the current test language. Or any language name for a bigger vocabulary, e.g. english_1k, english_5k, english_10k.",
      },
      n(
        "poolSize",
        "pool size",
        "Use only the first N words of the pool (most frequent first in ordered lists).",
        100,
        50000,
        100,
      ),
      n("minWordLength", "min word length", "Shortest word to use.", 1, 10, 1),
      n("maxWordLength", "max word length", "Longest word to use.", 3, 30, 1),
      n(
        "repeatWindow",
        "repeat window",
        "A word cannot reappear within this many words.",
        0,
        50,
        1,
      ),
      n(
        "pseudoWordRatio",
        "pseudo-words",
        "Share of targeted words replaced by generated pronounceable non-words packed with your weak n-grams.",
        0,
        1,
        0.05,
      ),
      n(
        "drillRatio",
        "raw drills",
        "Share of targeted words replaced by bare n-gram repetitions (e.g. 'ththth').",
        0,
        1,
        0.05,
      ),
      n(
        "confusionBonus",
        "confusion bonus",
        "Extra preference for words containing both letters of a pair you confuse.",
        0,
        2,
        0.05,
      ),
      {
        kind: "select",
        path: "capitalization",
        label: "capitalization",
        help: "auto adds capitals only when the model sees capitals as a weakness.",
        options: tri,
      },
      n(
        "capitalizationRate",
        "capitalization rate",
        "Share of words capitalized.",
        0,
        1,
        0.01,
      ),
      {
        kind: "select",
        path: "punctuation",
        label: "punctuation",
        help: "auto adds punctuation only when it is a measured weakness.",
        options: tri,
      },
      n(
        "punctuationRate",
        "punctuation rate",
        "Share of words punctuated.",
        0,
        1,
        0.01,
      ),
      {
        kind: "select",
        path: "numbers",
        label: "numbers",
        help: "auto adds numbers only when they are a measured weakness.",
        options: tri,
      },
      n(
        "numbersRate",
        "numbers rate",
        "Share of tokens that are numbers.",
        0,
        1,
        0.01,
      ),
    ],
  },
  {
    title: "difficulty",
    icon: "fa-sliders-h",
    description:
      "How concentrated the weak material is. Too easy teaches nothing, too hard builds bad habits.",
    fields: [
      t(
        "autoDifficulty",
        "automatic difficulty",
        "Adjust intensity after every training test to keep you near the target accuracy.",
      ),
      n(
        "intensity",
        "manual intensity",
        "Share of targeted words when automatic difficulty is off.",
        0,
        1,
        0.05,
      ),
      n(
        "targetAccuracy",
        "target accuracy",
        "Accuracy the controller steers training tests towards.",
        80,
        100,
        0.5,
        "%",
      ),
      n(
        "difficultyGain",
        "controller gain",
        "How aggressively intensity reacts to missing the target.",
        0.1,
        10,
        0.1,
      ),
      n(
        "minIntensity",
        "minimum intensity",
        "Lower bound for automatic intensity.",
        0,
        1,
        0.05,
      ),
      n(
        "maxIntensity",
        "maximum intensity",
        "Upper bound for automatic intensity.",
        0,
        1,
        0.05,
      ),
    ],
  },
  {
    title: "session behaviour",
    icon: "fa-sync-alt",
    description: "How training fits into normal typing.",
    fields: [
      t(
        "continuous",
        "continuous training",
        "Restarting during training generates a fresh adaptive test. When off, restarting returns to your previous mode.",
      ),
      n(
        "passiveBlend",
        "passive blend",
        "Share of words in NORMAL time / words tests that are quietly swapped for words rich in your weak spots. 0 leaves normal tests untouched.",
        0,
        1,
        0.05,
      ),
    ],
  },
];

export function getPath(obj: unknown, path: string): unknown {
  let cur = obj as Record<string, unknown> | undefined;
  for (const part of path.split(".")) {
    if (cur === undefined || cur === null) return undefined;
    cur = cur[part] as Record<string, unknown> | undefined;
  }
  return cur;
}

export function setPath<T extends object>(
  obj: T,
  path: string,
  value: unknown,
): T {
  const parts = path.split(".");
  const clone = structuredClone(obj) as Record<string, unknown>;
  let cur = clone;
  for (let i = 0; i < parts.length - 1; i++) {
    cur = cur[parts[i] as string] as Record<string, unknown>;
  }
  cur[parts[parts.length - 1] as string] = value;
  return clone as T;
}

/** Merge stored settings over the defaults, dropping unknown / mistyped keys. */
export function sanitizeSettings(raw: unknown): AdaptiveSettings {
  const merge = (def: unknown, val: unknown): unknown => {
    if (typeof def === "object" && def !== null) {
      const out: Record<string, unknown> = {};
      const v = (typeof val === "object" && val !== null ? val : {}) as Record<
        string,
        unknown
      >;
      for (const [k, d] of Object.entries(def)) out[k] = merge(d, v[k]);
      return out;
    }
    if (typeof val !== typeof def) return def;
    if (typeof val === "number" && !Number.isFinite(val)) return def;
    return val;
  };
  const s = merge(defaultSettings, raw) as AdaptiveSettings;
  if (!(s.preset in presets)) s.preset = "smart";
  return s;
}

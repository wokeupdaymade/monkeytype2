// Test generation: picks focus targets from the scored profile and builds a
// word sequence that concentrates on them.

import { Geometry, pairClasses, syllableSpans } from "./geometry";
import {
  Profile,
  Rng,
  Scored,
  scoreAll,
  textOf,
  typeLabels,
  typeOf,
  UnitType,
} from "./model";
import { AdaptiveSettings, effectiveWeights } from "./settings";

export type Target = {
  id: string;
  type: UnitType;
  text: string;
  score: number;
  weakness: number;
  reason: string;
};

export type Plan = {
  words: string[];
  targets: Target[];
  intensity: number;
  /** how many words of each origin ended up in the test */
  mix: { targeted: number; filler: number; pseudo: number; drill: number };
  /** false when the profile has too little data and the test is plain words */
  informed: boolean;
};

const lengthBucket = (len: number): string =>
  len <= 3 ? "short" : len <= 6 ? "medium" : len <= 9 ? "long" : "xlong";

const digitRe = /\p{N}/u;
const punctRe = /[^\p{L}\p{N}\s]/u;

/** Every unit id a word exercises (same naming as the analyzer). */
export function unitsOfWord(
  word: string,
  cfg: AdaptiveSettings,
  geo: Geometry,
): string[] {
  const out = new Set<string>();
  const w = word.toLowerCase();
  const padded = cfg.trackSpaceNgrams ? ` ${w} ` : w;
  for (let i = 0; i < w.length; i++) {
    const c = w[i] as string;
    out.add(`k:${c}`);
    const info = geo.keys.get(word[i] as string) ?? geo.keys.get(c);
    if (info !== undefined) {
      out.add(`c:finger-${info.finger}`);
      if (info.finger !== 8) out.add(`c:row-${info.row}`);
    }
    if (word[i] !== c) out.add("c:capital");
    else if (digitRe.test(c)) out.add("c:number");
    else if (punctRe.test(c)) out.add("c:punctuation");
    if (i > 0) {
      for (const cls of pairClasses(w[i - 1] as string, c, geo)) {
        out.add(`c:${cls}`);
      }
    }
  }
  if (cfg.trackBigrams) {
    for (let i = 0; i + 2 <= padded.length; i++) {
      out.add(`b:${padded.slice(i, i + 2)}`);
    }
  }
  if (cfg.trackTrigrams) {
    for (let i = 0; i + 3 <= padded.length; i++) {
      out.add(`t:${padded.slice(i, i + 3)}`);
    }
  }
  if (cfg.trackSyllables) {
    const spans = syllableSpans(w);
    if (spans.length > 1) {
      for (const [a, b] of spans) {
        if (b - a >= 2 && b - a <= 6) out.add(`s:${w.slice(a, b)}`);
      }
    }
  }
  if (cfg.trackWords && w.length >= 2) out.add(`w:${w}`);
  out.add(`c:len-${lengthBucket(w.length)}`);
  return [...out];
}

function describe(s: Scored): string {
  const c = s.components;
  const parts: [number, string][] = [
    [c.accuracy, `${(s.errorRate * 100).toFixed(1)}% errors`],
    [c.speed, `${Math.round((s.relLatency - 1) * 100)}% slower`],
    [c.consistency, "erratic timing"],
    [c.hesitation, "hesitations"],
    [c.trend, "getting worse"],
    [c.forgetting, "due for review"],
  ];
  parts.sort((a, b) => b[0] - a[0]);
  const top = parts.filter((p) => p[0] > 0.08).slice(0, 2);
  if (top.length === 0) {
    return s.level === "new" ? "not enough data yet" : "exploring";
  }
  return top.map((p) => p[1]).join(", ");
}

function weightedPick<T>(
  items: T[],
  weight: (item: T) => number,
  rng: Rng,
): T | undefined {
  let total = 0;
  for (const it of items) total += Math.max(0, weight(it));
  if (total <= 0) return items[Math.floor(rng() * items.length)];
  let r = rng() * total;
  for (const it of items) {
    r -= Math.max(0, weight(it));
    if (r <= 0) return it;
  }
  return items[items.length - 1];
}

/** Choose what this test concentrates on. */
export function selectTargets(
  profile: Profile,
  cfg: AdaptiveSettings,
  now: number,
  rng: Rng,
): { targets: Target[]; scored: Scored[] } {
  const draw =
    cfg.selection === "thompson"
      ? "thompson"
      : cfg.selection === "ucb"
        ? "ucb"
        : "mean";
  const eff = effectiveWeights(cfg);
  const scored = scoreAll(profile, cfg, { now, draw, rng, ...eff }).filter(
    (s) => s.score > 0,
  );
  // length classes and the space bar cannot be targeted by choosing words
  const eligible = scored.filter(
    (s) =>
      !s.id.startsWith("c:len-") &&
      s.id !== "c:word-start" &&
      s.id !== "c:finger-8" &&
      s.id !== "k: ",
  );
  eligible.sort((a, b) => b.score - a.score);

  let chosen: Scored[];
  if (cfg.selection === "softmax") {
    const candidates = eligible.slice(0, Math.max(cfg.focusCount * 8, 40));
    const max = candidates[0]?.score ?? 1;
    chosen = [];
    const left = [...candidates];
    while (chosen.length < cfg.focusCount && left.length > 0) {
      const pick = weightedPick(
        left,
        (s) =>
          Math.exp((s.score - max) / Math.max(0.02, cfg.temperature * max)),
        rng,
      ) as Scored;
      chosen.push(pick);
      left.splice(left.indexOf(pick), 1);
    }
    chosen.sort((a, b) => b.score - a.score);
  } else {
    chosen = eligible.slice(0, cfg.focusCount);
  }

  return {
    scored,
    targets: chosen.map((s) => ({
      id: s.id,
      type: s.type,
      text: s.text,
      score: s.score,
      weakness: s.weakness,
      reason: describe(s),
    })),
  };
}

type MarkovModel = Map<string, { next: string[]; count: number[] }>;

function buildMarkov(words: string[]): MarkovModel {
  const model: MarkovModel = new Map();
  for (const word of words) {
    const w = `^^${word.toLowerCase()}$`;
    for (let i = 2; i < w.length; i++) {
      const ctx = w.slice(i - 2, i);
      const ch = w[i] as string;
      let node = model.get(ctx);
      if (node === undefined) {
        node = { next: [], count: [] };
        model.set(ctx, node);
      }
      const idx = node.next.indexOf(ch);
      if (idx === -1) {
        node.next.push(ch);
        node.count.push(1);
      } else {
        node.count[idx] = (node.count[idx] ?? 0) + 1;
      }
    }
  }
  return model;
}

/**
 * A pronounceable non-word from a character trigram model of the pool, with
 * transitions that produce weak n-grams boosted.
 */
function pseudoWord(
  model: MarkovModel,
  boost: Map<string, number>,
  rng: Rng,
  minLen: number,
  maxLen: number,
): string | null {
  for (let attempt = 0; attempt < 12; attempt++) {
    let out = "";
    let ctx = "^^";
    for (let i = 0; i < maxLen + 1; i++) {
      const node = model.get(ctx);
      if (node === undefined) break;
      const prev1 = ctx[1] === "^" ? " " : (ctx[1] as string);
      const prev2 = ctx.startsWith("^") ? " " : (ctx[0] as string);
      const idx = weightedPick(
        node.next.map((_, j) => j),
        (j) => {
          const ch = node.next[j] as string;
          let weight = node.count[j] as number;
          if (ch === "$") {
            return out.length < minLen
              ? 0
              : weight * (out.length / maxLen + 0.3);
          }
          const b = boost.get(`b:${prev1}${ch}`) ?? 0;
          const t = boost.get(`t:${prev2}${prev1}${ch}`) ?? 0;
          const k = boost.get(`k:${ch}`) ?? 0;
          weight *= 1 + 12 * b + 16 * t + 4 * k;
          return weight;
        },
        rng,
      );
      if (idx === undefined) break;
      const ch = node.next[idx] as string;
      if (ch === "$") break;
      out += ch;
      ctx = (ctx[1] as string) + ch;
    }
    if (out.length >= minLen && out.length <= maxLen) return out;
  }
  return null;
}

function drillToken(target: Target, rng: Rng): string | null {
  if (target.type !== "b" && target.type !== "t" && target.type !== "s") {
    return null;
  }
  const g = target.text.replace(/ /g, "");
  if (g.length < 2) return null;
  const reps = g.length >= 4 ? 2 : 2 + Math.floor(rng() * 2);
  return g.repeat(reps);
}

function shuffle<T>(arr: T[], rng: Rng): T[] {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [arr[i], arr[j]] = [arr[j] as T, arr[i] as T];
  }
  return arr;
}

export type PoolIndex = {
  words: string[];
  units: string[][];
};

export function indexPool(
  pool: string[],
  cfg: AdaptiveSettings,
  geo: Geometry,
): PoolIndex {
  const seen = new Set<string>();
  const words: string[] = [];
  for (const w of pool) {
    if (words.length >= cfg.poolSize) break;
    if (w.includes(" ") || seen.has(w)) continue;
    if (w.length < cfg.minWordLength || w.length > cfg.maxWordLength) continue;
    seen.add(w);
    words.push(w);
  }
  return { words, units: words.map((w) => unitsOfWord(w, cfg, geo)) };
}

/** Score every pool word against the focus targets and the general weakness map. */
export function scoreWords(
  index: PoolIndex,
  targets: Target[],
  scored: Scored[],
  profile: Profile,
  cfg: AdaptiveSettings,
): Float64Array {
  const focus = new Map<string, number>();
  const maxScore = targets[0]?.score ?? 1;
  for (const t of targets) focus.set(t.id, t.score / (maxScore || 1));
  const general = new Map<string, number>();
  for (const s of scored) general.set(s.id, s.score);

  // letters the typist swaps: words holding both are good discrimination practice
  const pairs = Object.entries(profile.conf)
    .filter(([, count]) => count >= 1.5)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 6)
    .map(([pair]) => pair.split(">") as [string, string]);

  const out = new Float64Array(index.words.length);
  for (let i = 0; i < index.words.length; i++) {
    const units = index.units[i] as string[];
    const word = index.words[i] as string;
    let f = 0;
    let g = 0;
    let gn = 0;
    for (const u of units) {
      const fw = focus.get(u);
      if (fw !== undefined) f += fw;
      const gs = general.get(u);
      if (gs !== undefined && typeOf(u) !== "c") {
        g += gs;
        gn++;
      }
    }
    let score = f / Math.sqrt(Math.max(2, word.length) / 4);
    if (gn > 0) score += cfg.broadFactor * (g / gn) * 2;
    if (cfg.confusionBonus > 0) {
      for (const [a, b] of pairs) {
        if (word.includes(a) && word.includes(b)) {
          score += cfg.confusionBonus * 0.5;
          break;
        }
      }
    }
    out[i] = score;
  }
  return out;
}

function categoryActive(
  mode: "off" | "auto" | "on",
  id: string,
  scored: Scored[],
): boolean {
  if (mode === "on") return true;
  if (mode === "off") return false;
  const s = scored.find((x) => x.id === id);
  return s !== undefined && s.level !== "new" && s.weakness >= 0.14;
}

const punctuationMarks = [",", ".", ",", ".", ";", "?", "!", ":"];

export type GenerateInput = {
  profile: Profile;
  cfg: AdaptiveSettings;
  pool: string[];
  geo: Geometry;
  now: number;
  rng?: Rng;
  /** overrides the word count (time mode needs enough words to fill the time) */
  count?: number;
};

export function generate(input: GenerateInput): Plan {
  const { profile, cfg, geo, now } = input;
  const rng = input.rng ?? Math.random;
  const count = input.count ?? cfg.wordCount;
  const index = indexPool(input.pool, cfg, geo);
  const intensity = cfg.autoDifficulty ? profile.g.intensity : cfg.intensity;
  const { targets, scored } = selectTargets(profile, cfg, now, rng);
  const informed = targets.length > 0 && profile.g.chars >= 100;

  if (index.words.length === 0) {
    return {
      words: [],
      targets: [],
      intensity,
      mix: { targeted: 0, filler: 0, pseudo: 0, drill: 0 },
      informed: false,
    };
  }

  const wordScores = scoreWords(index, targets, scored, profile, cfg);

  // candidate list: the best scoring slice of the pool
  const order = Array.from(index.words.keys()).sort(
    (a, b) => (wordScores[b] as number) - (wordScores[a] as number),
  );
  const topN = Math.max(
    30,
    Math.min(order.length, Math.round(order.length * 0.15)),
  );
  const top = order.slice(0, topN);
  const best = wordScores[top[0] as number] ?? 1;
  const temp = Math.max(0.02, cfg.temperature) * (best || 1);
  const sampleWeight = (i: number): number =>
    Math.exp(((wordScores[i] as number) - best) / temp);

  const nTargeted = informed ? Math.round(count * intensity) : 0;
  const nPseudo = informed ? Math.round(nTargeted * cfg.pseudoWordRatio) : 0;
  const nDrill = informed ? Math.round(nTargeted * cfg.drillRatio) : 0;
  const nReal = Math.max(0, nTargeted - nPseudo - nDrill);

  type Token = {
    word: string;
    kind: "targeted" | "filler" | "pseudo" | "drill";
    block?: number;
  };
  const tokens: Token[] = [];

  // --- real words rich in targets
  const blockedShare =
    cfg.structure === "blocked" ? 1 : cfg.structure === "progressive" ? 0.5 : 0;
  const nBlocked = Math.round(nReal * blockedShare);
  const blocked: Token[] = [];
  if (nBlocked > 0 && targets.length > 0) {
    let block = 0;
    while (blocked.length < nBlocked) {
      const target = targets[block % targets.length] as Target;
      const holders = top.filter((i) =>
        (index.units[i] as string[]).includes(target.id),
      );
      const source = holders.length >= 2 ? holders : top;
      for (let j = 0; j < cfg.blockSize && blocked.length < nBlocked; j++) {
        const i = weightedPick(source, sampleWeight, rng) as number;
        blocked.push({
          word: index.words[i] as string,
          kind: "targeted",
          block,
        });
      }
      block++;
      if (block > 500) break;
    }
  }
  for (let j = 0; j < nReal - blocked.length; j++) {
    const i = weightedPick(top, sampleWeight, rng) as number;
    tokens.push({ word: index.words[i] as string, kind: "targeted" });
  }

  // --- pseudo-words from the biased character model
  if (nPseudo > 0) {
    const boost = new Map<string, number>();
    const maxScore = targets[0]?.score ?? 1;
    for (const t of targets) boost.set(t.id, t.score / (maxScore || 1));
    const model = buildMarkov(index.words);
    for (let j = 0; j < nPseudo; j++) {
      const w = pseudoWord(
        model,
        boost,
        rng,
        Math.max(3, cfg.minWordLength),
        Math.min(9, cfg.maxWordLength),
      );
      if (w !== null) tokens.push({ word: w, kind: "pseudo" });
    }
  }

  // --- bare n-gram repetitions
  if (nDrill > 0) {
    const drillable = targets.filter(
      (t) => t.type === "b" || t.type === "t" || t.type === "s",
    );
    for (let j = 0; j < nDrill && drillable.length > 0; j++) {
      const w = drillToken(drillable[j % drillable.length] as Target, rng);
      if (w !== null) tokens.push({ word: w, kind: "drill" });
    }
  }

  // --- filler: ordinary words, so the test still reads like typing
  const fillerCount = Math.max(0, count - tokens.length - blocked.length);
  for (let j = 0; j < fillerCount; j++) {
    const i = Math.floor(rng() * index.words.length);
    tokens.push({ word: index.words[i] as string, kind: "filler" });
  }

  shuffle(tokens, rng);
  // blocked groups go first (progressive: blocked warm-up, then interleaved)
  let sequence: Token[] = [...blocked, ...tokens].slice(0, count);

  // --- no immediate repeats
  if (cfg.repeatWindow > 0) {
    const fixed: Token[] = [];
    for (const tok of sequence) {
      const recent = new Set(fixed.slice(-cfg.repeatWindow).map((x) => x.word));
      if (tok.block === undefined && recent.has(tok.word)) {
        let replaced = false;
        for (let tries = 0; tries < 8; tries++) {
          const src = tok.kind === "targeted" ? top : order;
          const i =
            tok.kind === "targeted"
              ? (weightedPick(src, sampleWeight, rng) as number)
              : (src[Math.floor(rng() * src.length)] as number);
          const w = index.words[i] as string;
          if (!recent.has(w)) {
            fixed.push({
              word: w,
              kind: tok.kind === "targeted" ? "targeted" : "filler",
            });
            replaced = true;
            break;
          }
        }
        if (!replaced) fixed.push(tok);
      } else {
        fixed.push(tok);
      }
    }
    sequence = fixed;
  }

  // --- surface form: capitals, punctuation, numbers
  const caps = categoryActive(cfg.capitalization, "c:capital", scored);
  const punct = categoryActive(cfg.punctuation, "c:punctuation", scored);
  const nums = categoryActive(cfg.numbers, "c:number", scored);
  const words = sequence.map((tok) => {
    let w = tok.word;
    if (tok.kind === "drill") return w;
    if (nums && rng() < cfg.numbersRate) {
      return String(
        Math.floor(rng() * Math.pow(10, 1 + Math.floor(rng() * 4))),
      );
    }
    if (caps && rng() < cfg.capitalizationRate) {
      w = w.charAt(0).toUpperCase() + w.slice(1);
    }
    if (punct && rng() < cfg.punctuationRate) {
      w += punctuationMarks[
        Math.floor(rng() * punctuationMarks.length)
      ] as string;
    }
    return w;
  });

  const mix = { targeted: 0, filler: 0, pseudo: 0, drill: 0 };
  for (const tok of sequence) mix[tok.kind]++;

  return { words, targets: informed ? targets : [], intensity, mix, informed };
}

/**
 * Passive blending: given the word the normal generator picked, maybe swap
 * it for one from the same wordset that exercises weak units.
 */
export class PassiveBlender {
  private key: string[] | null = null;
  private stamp = -1;
  private candidates: string[] = [];
  private weights: number[] = [];

  pick(
    wordset: string[],
    profile: Profile,
    cfg: AdaptiveSettings,
    geo: Geometry,
    profileStamp: number,
    now: number,
    rng: Rng = Math.random,
  ): string | null {
    if (cfg.passiveBlend <= 0 || rng() >= cfg.passiveBlend) return null;
    if (profile.g.chars < 300) return null;
    if (this.key !== wordset || this.stamp !== profileStamp) {
      this.key = wordset;
      this.stamp = profileStamp;
      const index = indexPool(wordset, { ...cfg, poolSize: 20000 }, geo);
      // point estimates here: passive tests should drift, not jump around
      const { targets, scored } = selectTargets(
        profile,
        {
          ...cfg,
          selection: "greedy",
          focusCount: Math.max(cfg.focusCount, 12),
        },
        now,
        rng,
      );
      const scores = scoreWords(index, targets, scored, profile, cfg);
      const order = Array.from(index.words.keys()).sort(
        (a, b) => (scores[b] as number) - (scores[a] as number),
      );
      const top = order.slice(0, Math.max(20, Math.round(order.length * 0.12)));
      this.candidates = top.map((i) => index.words[i] as string);
      this.weights = top.map((i) => scores[i] as number);
    }
    if (this.candidates.length === 0) return null;
    const idx = weightedPick(
      this.candidates.map((_, i) => i),
      (i) => this.weights[i] as number,
      rng,
    );
    return idx === undefined ? null : (this.candidates[idx] as string);
  }
}

export function targetLabel(t: { type: UnitType; id: string }): string {
  if (t.type === "c") return patternLabel(textOf(t.id));
  return textOf(t.id).replace(/ /g, "␣");
}

const patternNames: Record<string, string> = {
  sfb: "same-finger bigrams",
  double: "double letters",
  alt: "hand alternation",
  "roll-in": "inward rolls",
  "roll-out": "outward rolls",
  rowjump: "row jumps",
  stretch: "index stretches",
  capital: "capitals",
  number: "numbers",
  punctuation: "punctuation",
  "word-start": "word starts",
  "len-short": "short words (1-3)",
  "len-medium": "medium words (4-6)",
  "len-long": "long words (7-9)",
  "len-xlong": "very long words (10+)",
  "row-0": "number row",
  "row-1": "top row",
  "row-2": "home row",
  "row-3": "bottom row",
};
const fingers = [
  "left pinky",
  "left ring",
  "left middle",
  "left index",
  "right index",
  "right middle",
  "right ring",
  "right pinky",
  "thumb",
];

export function patternLabel(name: string): string {
  if (name.startsWith("finger-")) {
    return fingers[Number(name.slice(7))] ?? name;
  }
  return patternNames[name] ?? name;
}

export function typeLabel(t: UnitType): string {
  return typeLabels[t];
}

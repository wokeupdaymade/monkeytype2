// The statistical model: per-unit statistics, how observations update them,
// and how a unit's weakness is scored.
//
// A "unit" is anything we keep statistics for. Its id carries the level:
//   k:<char>      single key
//   b:<2 chars>   bigram          t:<3 chars>  trigram
//   s:<chunk>     syllable        w:<word>     whole word
//   c:<name>      category (finger, motion pattern, capitals, word length...)

import {
  AdaptiveSettings,
  ComponentWeights,
  effectiveWeights,
  TypeWeights,
} from "./settings";

export type Stat = {
  /** decayed number of accuracy samples */
  n: number;
  /** decayed number of errors */
  e: number;
  /** lifetime samples */
  c: number;
  /** decayed number of timing samples */
  tn: number;
  /** decayed mean ms per keystroke */
  tm: number;
  /** decayed variance of ms */
  tv: number;
  /** decayed mean latency relative to the test's median keystroke */
  rm: number;
  /** decayed hesitation count */
  h: number;
  /** fast / slow moving average of errors, for the trend */
  ef: number;
  es: number;
  /** fast / slow moving average of relative latency */
  rf: number;
  rs: number;
  /** memory stability in days (spaced repetition) */
  st: number;
  /** last seen (ms epoch) */
  ls: number;
  /** peak weakness seen, slowly decaying: what "forgetting" brings back */
  pk: number;
};

export type SessionSummary = {
  t: number;
  wpm: number;
  acc: number;
  chars: number;
  mode: string;
  adaptive: boolean;
  /** frequency weighted mean weakness after this session, 0..100 */
  wi: number;
  medianDt: number;
  errCost: number;
  fatigue: number;
  postError: number;
  consistency: number;
  intensity?: number;
};

export const errorTypes = [
  "substitution",
  "adjacent",
  "mirror",
  "case",
  "omission",
  "insertion",
  "doubling",
  "transposition",
  "early-space",
  "missed-space",
  "other",
] as const;
export type ErrorType = (typeof errorTypes)[number];

export type Profile = {
  v: 1;
  created: number;
  units: Record<string, Stat>;
  /** substitution pairs "expected>typed" -> decayed count */
  conf: Record<string, number>;
  errTypes: Partial<Record<ErrorType, number>>;
  sessions: SessionSummary[];
  /** running estimates about the typist as a whole */
  g: {
    tests: number;
    chars: number;
    medianDt: number;
    errCost: number;
    wpm: number;
    intensity: number;
  };
};

export function newProfile(now: number, intensity = 0.6): Profile {
  return {
    v: 1,
    created: now,
    units: {},
    conf: {},
    errTypes: {},
    sessions: [],
    g: { tests: 0, chars: 0, medianDt: 0, errCost: 0, wpm: 0, intensity },
  };
}

export function newStat(now: number, stability: number): Stat {
  return {
    n: 0,
    e: 0,
    c: 0,
    tn: 0,
    tm: 0,
    tv: 0,
    rm: 1,
    h: 0,
    ef: 0,
    es: 0,
    rf: 1,
    rs: 1,
    st: stability,
    ls: now,
    pk: 0,
  };
}

export function observeAccuracy(
  s: Stat,
  err: 0 | 1,
  cfg: AdaptiveSettings,
  now: number,
): void {
  const lam = Math.pow(0.5, 1 / cfg.halfLife);
  s.n = s.n * lam + 1;
  s.e = s.e * lam + err;
  if (s.c === 0) {
    s.ef = err;
    s.es = err;
  } else {
    s.ef += (2 / (cfg.trendFast + 1)) * (err - s.ef);
    s.es += (2 / (cfg.trendSlow + 1)) * (err - s.es);
  }
  s.c++;
  s.ls = now;
}

export function observeTime(
  s: Stat,
  ms: number,
  rel: number,
  hesitated: boolean,
  cfg: AdaptiveSettings,
): void {
  const lam = Math.pow(0.5, 1 / cfg.halfLife);
  const first = s.tn === 0;
  s.tn = s.tn * lam + 1;
  s.h = s.h * lam + (hesitated ? 1 : 0);
  const a = 1 / s.tn;
  if (first) {
    s.tm = ms;
    s.tv = 0;
    s.rm = rel;
    s.rf = rel;
    s.rs = rel;
    return;
  }
  const d = ms - s.tm;
  s.tm += a * d;
  s.tv = (1 - a) * (s.tv + a * d * d);
  s.rm += a * (rel - s.rm);
  s.rf += (2 / (cfg.trendFast + 1)) * (rel - s.rf);
  s.rs += (2 / (cfg.trendSlow + 1)) * (rel - s.rs);
}

// ---------------------------------------------------------------- scoring

export type UnitType = "k" | "b" | "t" | "s" | "w" | "c";
export const unitTypes: UnitType[] = ["k", "b", "t", "s", "w", "c"];
export const typeLabels: Record<UnitType, string> = {
  k: "key",
  b: "bigram",
  t: "trigram",
  s: "syllable",
  w: "word",
  c: "pattern",
};
const typeWeightKey: Record<UnitType, keyof TypeWeights> = {
  k: "key",
  b: "bigram",
  t: "trigram",
  s: "syllable",
  w: "word",
  c: "category",
};

export function typeOf(id: string): UnitType {
  return id[0] as UnitType;
}
export function textOf(id: string): string {
  return id.slice(2);
}

export type Baseline = {
  /** mean error rate */
  p: number;
  /** mean relative latency */
  r: number;
  /** mean ms */
  ms: number;
  /** mean coefficient of variation */
  cv: number;
  /** mean hesitation rate */
  h: number;
  /** total lifetime samples and the largest single unit */
  total: number;
  maxC: number;
};

type Accumulator = {
  n: number;
  e: number;
  tn: number;
  r: number;
  ms: number;
  cv: number;
  h: number;
  total: number;
  maxC: number;
};

/**
 * N-grams that begin with the space carry the pause between words, so they
 * are compared with each other, not with n-grams inside words.
 */
export function baselineKey(id: string): string {
  const t = id[0] as string;
  return (t === "b" || t === "t") && id[2] === " " ? `${t}_` : t;
}
const baselineKeys = [...unitTypes, "b_", "t_"];

export type Baselines = Record<string, Baseline>;

export function baselines(profile: Profile): Baselines {
  const acc = new Map<string, Accumulator>();
  for (const t of baselineKeys) {
    acc.set(t, {
      n: 0,
      e: 0,
      tn: 0,
      r: 0,
      ms: 0,
      cv: 0,
      h: 0,
      total: 0,
      maxC: 1,
    });
  }
  for (const id in profile.units) {
    const s = profile.units[id] as Stat;
    const a = acc.get(baselineKey(id));
    if (a === undefined) continue;
    a.n += s.n;
    a.e += s.e;
    a.total += s.c;
    if (s.c > a.maxC) a.maxC = s.c;
    if (s.tn > 0 && s.tm > 0) {
      a.tn += s.tn;
      a.r += s.tn * s.rm;
      a.ms += s.tn * s.tm;
      a.cv += (s.tn * Math.sqrt(s.tv)) / s.tm;
      a.h += s.h;
    }
  }
  const out: Baselines = {};
  for (const t of baselineKeys) {
    const a = acc.get(t) as Accumulator;
    out[t] = {
      p: a.n > 0 ? Math.max(0.002, a.e / a.n) : 0.05,
      r: a.tn > 0 ? a.r / a.tn : 1,
      ms: a.tn > 0 ? a.ms / a.tn : 150,
      cv: a.tn > 0 ? Math.max(0.05, a.cv / a.tn) : 0.4,
      h: a.tn > 0 ? Math.max(0.005, a.h / a.tn) : 0.03,
      total: a.total,
      maxC: a.maxC,
    };
  }
  return out;
}

/** 0 for x <= 0, rising towards 1; reaches 0.5 at x = half. */
function sat(x: number, half: number): number {
  return x <= 0 ? 0 : x / (x + half);
}

export type Level = "new" | "critical" | "weak" | "fair" | "good" | "mastered";

export type Scored = {
  id: string;
  type: UnitType;
  text: string;
  /** final selection score (weights, frequency and exploration applied) */
  score: number;
  /** weakness alone, 0..1, comparable across units */
  weakness: number;
  level: Level;
  components: {
    accuracy: number;
    speed: number;
    consistency: number;
    hesitation: number;
    trend: number;
    forgetting: number;
    exploration: number;
    impact: number;
  };
  /** shrunk estimates, for display */
  errorRate: number;
  ms: number;
  relLatency: number;
  /** estimated ms lost per occurrence */
  lostMs: number;
  samples: number;
  confidence: number;
  /** negative = improving, positive = getting worse */
  trend: number;
  recall: number;
  stat: Stat;
};

export type Rng = () => number;

function gaussian(rng: Rng): number {
  let u = 0;
  while (u === 0) u = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rng());
}

// Marsaglia-Tsang
function gamma(shape: number, rng: Rng): number {
  if (shape < 1) {
    return gamma(shape + 1, rng) * Math.pow(Math.max(rng(), 1e-12), 1 / shape);
  }
  const d = shape - 1 / 3;
  const c = 1 / Math.sqrt(9 * d);
  for (;;) {
    let x = 0;
    let v = 0;
    do {
      x = gaussian(rng);
      v = 1 + c * x;
    } while (v <= 0);
    v = v * v * v;
    const u = rng();
    if (u < 1 - 0.0331 * x * x * x * x) return d * v;
    if (Math.log(u) < 0.5 * x * x + d * (1 - v + Math.log(v))) return d * v;
  }
}

export function sampleBeta(a: number, b: number, rng: Rng): number {
  const x = gamma(Math.max(a, 1e-3), rng);
  const y = gamma(Math.max(b, 1e-3), rng);
  return x + y === 0 ? 0.5 : x / (x + y);
}

export type ScoreOptions = {
  now: number;
  /** how estimates are drawn: point estimate, posterior sample or optimistic bound */
  draw?: "mean" | "thompson" | "ucb";
  rng?: Rng;
  weights?: ComponentWeights;
  typeWeights?: TypeWeights;
};

const dayMs = 86400000;

export function scoreUnit(
  id: string,
  s: Stat,
  base: Baseline,
  profile: Profile,
  cfg: AdaptiveSettings,
  opts: ScoreOptions,
): Scored {
  const type = typeOf(id);
  const eff =
    opts.weights !== undefined && opts.typeWeights !== undefined
      ? { weights: opts.weights, typeWeights: opts.typeWeights }
      : effectiveWeights(cfg);
  const w = eff.weights;
  const k = cfg.priorStrength;
  const rng = opts.rng ?? Math.random;
  const draw = opts.draw ?? "mean";

  // --- accuracy: beta posterior around the typist's own average for this level
  const alpha = s.e + k * base.p;
  const beta = Math.max(1e-3, s.n - s.e) + k * (1 - base.p);
  let p = alpha / (alpha + beta);
  const pMean = p;
  if (draw === "thompson") p = sampleBeta(alpha, beta, rng);
  else if (draw === "ucb") p += Math.sqrt((p * (1 - p)) / (alpha + beta + 1));

  // --- speed: relative latency shrunk towards the level average
  const hasTime = s.tn > 0 && s.tm > 0;
  const tn = hasTime ? s.tn : 0;
  let r = (tn * s.rm + k * base.r) / (tn + k || 1);
  const rMean = r;
  const cvUnit = hasTime ? Math.sqrt(s.tv) / s.tm : base.cv;
  const rSe = (Math.max(cvUnit, base.cv) * r) / Math.sqrt(tn + k + 1);
  if (draw === "thompson") r += gaussian(rng) * rSe;
  else if (draw === "ucb") r += rSe;
  const ms = (tn * s.tm + k * base.ms) / (tn + k || 1);

  const conf = s.n / (s.n + cfg.minSamples);
  const tconf = tn / (tn + cfg.minSamples);

  const accuracy = sat(p / base.p - 1, 1.5);
  const speed = sat(r / base.r - 1, 0.35);
  const consistency = tconf * sat(cvUnit / base.cv - 1, 0.8);
  const hRate = (s.h + k * base.h) / (tn + k || 1);
  const hesitation = sat(hRate / base.h - 1, 2);
  const errTrend = s.ef - s.es;
  const spdTrend = s.rs > 0 ? (s.rf - s.rs) / s.rs : 0;
  const trendRaw = errTrend * 4 + spdTrend * 2;
  const trend = conf * Math.min(1, Math.max(0, trendRaw));
  const days = Math.max(0, (opts.now - s.ls) / dayMs);
  const recall = Math.pow(2, -days / Math.max(0.05, s.st));
  const forgetting = (1 - recall) * s.pk;
  const exploration = Math.min(
    1,
    Math.sqrt((2 * Math.log(base.total + 2)) / (s.c + 1)) / 3,
  );

  // --- impact: estimated ms lost every time this unit comes up
  const errCost = profile.g.errCost > 0 ? profile.g.errCost : base.ms * 4;
  const lostDraw = Math.max(0, (r / base.r - 1) * base.ms) + p * errCost;
  const lostBase = base.p * errCost;
  const impact = sat(lostDraw / Math.max(1, lostBase) - 1, 2);
  const lostMs =
    Math.max(0, (rMean / base.r - 1) * base.ms) + pMean * errCost - lostBase;

  // A unit that is terrible on one dimension is a real weakness even when it
  // is fine on the others, so the strongest component dominates and the
  // weighted mean only nudges.
  const blend = (parts: [number, number][]): number => {
    let wMax = 0;
    let wSum = 0;
    for (const [weight] of parts) {
      wMax = Math.max(wMax, weight);
      wSum += weight;
    }
    if (wMax <= 0) return 0;
    let peak = 0;
    let sum = 0;
    for (const [weight, value] of parts) {
      peak = Math.max(peak, (weight / wMax) * value);
      sum += weight * value;
    }
    return 0.65 * peak + 0.35 * (sum / wSum);
  };
  const shared: [number, number][] = [
    [w.consistency, consistency],
    [w.hesitation, hesitation],
    [w.trend, trend],
    [w.forgetting, forgetting],
  ];
  const composite = blend([
    [w.accuracy, accuracy],
    [w.speed, speed],
    ...shared,
  ]);
  // impact folds accuracy and speed into one "time lost" figure
  const impactMix = blend([[Math.max(w.accuracy, w.speed), impact], ...shared]);
  const model =
    cfg.scoringModel === "composite"
      ? composite
      : cfg.scoringModel === "impact"
        ? impactMix
        : (composite + impactMix) / 2;

  const freq = Math.pow(
    Math.min(1, (s.c + 1) / (base.maxC + 1)),
    cfg.frequencyBias * 0.5,
  );
  const tw = eff.typeWeights[typeWeightKey[type]];
  const score = tw * (model * freq + w.exploration * exploration * 0.5);

  // level from point estimates only, so it does not flicker with sampling
  const wk = s.c < cfg.minSamples ? 0 : model;
  const level: Level =
    s.c < cfg.minSamples
      ? "new"
      : wk >= 0.45
        ? "critical"
        : wk >= 0.28
          ? "weak"
          : wk >= 0.14
            ? "fair"
            : wk >= 0.05
              ? "good"
              : "mastered";

  return {
    id,
    type,
    text: textOf(id),
    score,
    weakness: model,
    level,
    components: {
      accuracy,
      speed,
      consistency,
      hesitation,
      trend,
      forgetting,
      exploration,
      impact,
    },
    errorRate: pMean,
    ms,
    relLatency: rMean / base.r,
    lostMs,
    samples: s.c,
    confidence: Math.max(conf, tconf),
    trend: trendRaw,
    recall,
    stat: s,
  };
}

export function scoreAll(
  profile: Profile,
  cfg: AdaptiveSettings,
  opts: ScoreOptions,
): Scored[] {
  const base = baselines(profile);
  const out: Scored[] = [];
  for (const id in profile.units) {
    const b = base[baselineKey(id)];
    if (b === undefined) continue;
    out.push(scoreUnit(id, profile.units[id] as Stat, b, profile, cfg, opts));
  }
  return out;
}

/** Frequency weighted mean weakness of the whole profile, 0..100. Lower is better. */
export function weaknessIndex(scored: Scored[]): number {
  let num = 0;
  let den = 0;
  for (const s of scored) {
    if (s.type === "c" || s.level === "new") continue;
    num += s.weakness * s.samples;
    den += s.samples;
  }
  return den > 0 ? (100 * num) / den : 0;
}

/** Drop the least valuable units when the profile grows past the limit. */
export function prune(profile: Profile, max: number, now: number): void {
  const ids = Object.keys(profile.units);
  if (ids.length <= max) return;
  const value = (id: string): number => {
    const s = profile.units[id] as Stat;
    if (typeOf(id) === "k" || typeOf(id) === "c") return Infinity;
    const ageDays = (now - s.ls) / dayMs;
    return s.c / (1 + ageDays / 30) + s.pk * 20;
  };
  ids.sort((a, b) => value(a) - value(b));
  // prune 10% below the limit so this does not run after every test
  const remove = ids.length - Math.floor(max * 0.9);
  for (let i = 0; i < remove; i++) {
    // oxlint-disable-next-line typescript/no-dynamic-delete
    delete profile.units[ids[i] as string];
  }
  const pairs = Object.keys(profile.conf);
  if (pairs.length > 600) {
    pairs.sort(
      (a, b) => (profile.conf[a] as number) - (profile.conf[b] as number),
    );
    for (const key of pairs.slice(0, pairs.length - 400)) {
      // oxlint-disable-next-line typescript/no-dynamic-delete
      delete profile.conf[key];
    }
  }
}

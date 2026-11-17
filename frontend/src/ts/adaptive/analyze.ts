// Passive analysis: turns the event log of one finished test into
// observations and folds them into the profile.

import {
  Geometry,
  isAdjacent,
  isMirror,
  pairClasses,
  syllableSpans,
} from "./geometry";
import {
  baselineKey,
  baselines,
  ErrorType,
  newStat,
  observeAccuracy,
  observeTime,
  Profile,
  prune,
  scoreAll,
  scoreUnit,
  SessionSummary,
  Stat,
  weaknessIndex,
} from "./model";
import { AdaptiveSettings } from "./settings";

/** The subset of monkeytype's EventLog the analyzer reads. */
export type LogLike = {
  events: {
    type: string;
    testMs: number;
    data: Record<string, unknown>;
  }[];
  context: { targetWords: string[] };
};

type Stroke = {
  w: number;
  pos: number;
  /** expected char ("" when typed past the end of the word) */
  exp: string;
  typed: string;
  ok: boolean;
  /** first time this position of this word was attempted */
  first: boolean;
  ms: number;
  dt: number;
  /** the keystroke before it was the correct previous character */
  contig: boolean;
  /** dt is a usable timing sample */
  timed: boolean;
  commit: boolean;
};

type WordTrace = {
  target: string;
  strokes: Stroke[];
  firstPass: string;
  hadDelete: boolean;
  committed: boolean;
  commitOk: boolean;
};

export type Observation = {
  id: string;
  err?: 0 | 1;
  ms?: number;
  rel?: number;
  hes?: boolean;
};

export type Extraction = {
  obs: Observation[];
  errTypes: Partial<Record<ErrorType, number>>;
  confusions: Record<string, number>;
  chars: number;
  errors: number;
  medianDt: number;
  /** ms lost per error to noticing, deleting and retyping */
  errCost: number;
  /** relative latency of the last third of the test vs the first third */
  fatigue: number;
  /** relative latency right after recovering from an error */
  postError: number;
  /** coefficient of variation of keystroke intervals */
  cv: number;
};

function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 === 1
    ? (sorted[mid] as number)
    : ((sorted[mid - 1] as number) + (sorted[mid] as number)) / 2;
}

function mean(values: number[]): number {
  return values.length === 0
    ? 0
    : values.reduce((a, b) => a + b, 0) / values.length;
}

function lengthBucket(len: number): string {
  return len <= 3 ? "short" : len <= 6 ? "medium" : len <= 9 ? "long" : "xlong";
}

const punctRe = /[^\p{L}\p{N}\s]/u;
const digitRe = /\p{N}/u;

function classifyFirstError(
  trace: WordTrace,
  nextTarget: string | undefined,
  geo: Geometry,
): { type: ErrorType; exp?: string; typed?: string } | null {
  const fp = trace.firstPass;
  const target = trace.target;
  let p = 0;
  while (p < fp.length && fp[p] === target[p]) p++;
  if (p >= fp.length) {
    // first pass was a clean prefix: the only possible mistake is the commit
    if (trace.committed && !trace.hadDelete && fp.length < target.length) {
      return { type: "early-space" };
    }
    return null;
  }
  const typed = fp[p] as string;
  const exp = target[p];
  const next = fp[p + 1];
  if (exp === undefined) {
    if (typed === nextTarget?.[0]) {
      return { type: "missed-space" };
    }
    return { type: "insertion", typed };
  }
  if (typed === target[p + 1] && next === exp) return { type: "transposition" };
  if (
    typed === target[p + 1] &&
    (next === undefined || next === target[p + 2])
  ) {
    return { type: "omission", exp };
  }
  if (p > 0 && typed === target[p - 1] && target[p - 1] !== exp) {
    return { type: "doubling", typed };
  }
  if (next === exp) return { type: "insertion", typed };
  if (typed.toLowerCase() === exp.toLowerCase()) {
    return { type: "case", exp, typed };
  }
  if (isAdjacent(exp, typed, geo)) return { type: "adjacent", exp, typed };
  if (isMirror(exp, typed, geo)) return { type: "mirror", exp, typed };
  if (typed === " ") return { type: "other" };
  return { type: "substitution", exp, typed };
}

export function extract(
  log: LogLike,
  cfg: AdaptiveSettings,
  geo: Geometry,
): Extraction {
  const targets = log.context.targetWords.map((w) => w.replace(/[ \n]$/, ""));
  const traces = new Map<number, WordTrace>();
  const inputs = new Map<number, string>();
  const attempted = new Map<number, number>();
  const strokes: (Stroke | null)[] = [];
  let lastMs: number | null = null;
  let prev: { w: number; pos: number; ok: boolean } | null = null;
  let recoveryMs = 0;
  let testEnd = 0;

  const traceOf = (w: number): WordTrace => {
    let tr = traces.get(w);
    if (tr === undefined) {
      tr = {
        target: targets[w] as string,
        strokes: [],
        firstPass: "",
        hadDelete: false,
        committed: false,
        commitOk: false,
      };
      traces.set(w, tr);
    }
    return tr;
  };

  for (const ev of log.events) {
    if (ev.type !== "input") continue;
    const d = ev.data;
    if (d["automatic"] === true) continue;
    const w = d["wordIndex"] as number;
    if (targets[w] === undefined) continue;
    const target = targets[w];
    const tr = traceOf(w);
    const cur = inputs.get(w) ?? "";
    const dt = lastMs === null ? NaN : ev.testMs - lastMs;
    lastMs = ev.testMs;
    testEnd = ev.testMs;
    const inputType = d["inputType"] as string;

    if (inputType.startsWith("delete")) {
      tr.hadDelete = true;
      if (typeof d["inputValue"] === "string") {
        inputs.set(w, d["inputValue"]);
      } else {
        inputs.set(w, cur.slice(0, -1));
      }
      if (Number.isFinite(dt) && dt < cfg.maxPauseMs) recoveryMs += dt;
      prev = null;
      strokes.push(null);
      continue;
    }

    const ch = d["data"];
    if (
      d["inputStopped"] === true ||
      typeof ch !== "string" ||
      ch.length !== 1
    ) {
      // composition / blocked input: keep the reconstruction in sync, skip stats
      if (typeof ch === "string" && d["inputStopped"] !== true) {
        inputs.set(w, cur + ch);
      }
      prev = null;
      strokes.push(null);
      continue;
    }

    if (d["commitsWord"] === true && (ch === " " || ch === "\n")) {
      // the space itself is right when pressed at the end of the word, whatever
      // was typed before it; pressed early it is a miss of the skipped letter
      const early = cur.length < target.length;
      const ok = !early;
      const pos = early ? cur.length : target.length;
      const s: Stroke = {
        w,
        pos,
        exp: early ? (target[pos] as string) : " ",
        typed: " ",
        ok,
        first: early ? pos > (attempted.get(w) ?? -1) : true,
        ms: ev.testMs,
        dt,
        contig: prev?.w === w && prev.pos === pos - 1 && prev.ok,
        timed: false,
        commit: true,
      };
      tr.committed = true;
      tr.commitOk = cur === target;
      tr.strokes.push(s);
      strokes.push(s);
      prev = { w: w + 1, pos: -1, ok };
      continue;
    }

    const pos = cur.length;
    const exp = target[pos] ?? "";
    const ok = ch === exp;
    const first = pos > (attempted.get(w) ?? -1);
    if (first) attempted.set(w, pos);
    const s: Stroke = {
      w,
      pos,
      exp,
      typed: ch,
      ok,
      first,
      ms: ev.testMs,
      dt,
      contig: prev?.w === w && prev.pos === pos - 1 && prev.ok,
      timed: false,
      commit: false,
    };
    if (!tr.hadDelete) tr.firstPass += ch;
    if ((!first || !ok) && Number.isFinite(dt) && dt < cfg.maxPauseMs) {
      recoveryMs += dt;
    }
    inputs.set(w, cur + ch);
    tr.strokes.push(s);
    strokes.push(s);
    prev = { w, pos, ok };
  }

  // --- timing validity + the test's own tempo
  const valid: number[] = [];
  for (const s of strokes) {
    if (s === null) continue;
    s.timed =
      s.first &&
      s.ok &&
      s.contig &&
      Number.isFinite(s.dt) &&
      s.dt > 0 &&
      s.dt <= cfg.maxPauseMs;
    if (s.timed) valid.push(s.dt);
  }
  const med = median(valid) || 150;
  const hesMs = med * cfg.hesitationFactor;

  const obs: Observation[] = [];
  const acc = (id: string, err: boolean): void => {
    obs.push({ id, err: err ? 1 : 0 });
  };
  const time = (id: string, ms: number): void => {
    obs.push({ id, ms, rel: ms / med, hes: ms > hesMs });
  };
  const lower = (s: string): string => s.toLowerCase();
  const usable = (text: string): boolean =>
    cfg.trackSpaceNgrams || !text.includes(" ");

  let chars = 0;
  let errors = 0;

  // --- per keystroke: keys, n-grams, fingers, motion patterns
  for (let i = 0; i < strokes.length; i++) {
    const s = strokes[i];
    if (s === null || s === undefined || !s.first) continue;
    const target = targets[s.w] as string;
    chars++;
    if (!s.ok) errors++;
    if (s.exp === "") {
      // typed past the end of the word: a missed space
      acc("k: ", true);
      continue;
    }
    const c = lower(s.exp);
    const p1 =
      s.pos > 0 ? lower(target[s.pos - 1] as string) : s.w > 0 ? " " : "";
    const p2 =
      s.pos > 1
        ? lower(target[s.pos - 2] as string)
        : s.pos === 1 && s.w > 0
          ? " "
          : "";
    const before = strokes[i - 1];
    const before2 = strokes[i - 2];
    const ctx1 = s.contig;
    const ctx2 = ctx1 && before?.contig === true;

    acc(`k:${c}`, !s.ok);
    if (s.timed) time(`k:${c}`, s.dt);

    const info = geo.keys.get(s.exp) ?? geo.keys.get(c);
    if (info !== undefined) {
      acc(`c:finger-${info.finger}`, !s.ok);
      if (s.timed) time(`c:finger-${info.finger}`, s.dt);
      if (info.finger !== 8) {
        acc(`c:row-${info.row}`, !s.ok);
        if (s.timed) time(`c:row-${info.row}`, s.dt);
      }
    }
    if (s.exp !== c) {
      acc("c:capital", !s.ok);
      if (s.timed) time("c:capital", s.dt);
    } else if (digitRe.test(c)) {
      acc("c:number", !s.ok);
      if (s.timed) time("c:number", s.dt);
    } else if (c !== " " && punctRe.test(c)) {
      acc("c:punctuation", !s.ok);
      if (s.timed) time("c:punctuation", s.dt);
    }
    if (s.pos === 0 && s.w > 0) {
      acc("c:word-start", !s.ok);
      if (s.timed) time("c:word-start", s.dt);
    }

    if (p1 !== "" && ctx1) {
      const bg = p1 + c;
      if (cfg.trackBigrams && usable(bg)) {
        acc(`b:${bg}`, !s.ok);
        if (s.timed) time(`b:${bg}`, s.dt);
      }
      for (const cls of pairClasses(p1, c, geo)) {
        acc(`c:${cls}`, !s.ok);
        if (s.timed) time(`c:${cls}`, s.dt);
      }
      if (cfg.trackTrigrams && p2 !== "" && ctx2) {
        const tg = p2 + bg;
        if (usable(tg)) {
          acc(`t:${tg}`, !s.ok);
          if (
            s.timed &&
            before !== null &&
            before !== undefined &&
            before.timed &&
            before2 !== undefined
          ) {
            time(`t:${tg}`, (s.dt + before.dt) / 2);
          }
        }
      }
    }
  }

  // --- per word: words, syllables, length classes, error taxonomy
  const errTypes: Partial<Record<ErrorType, number>> = {};
  const confusions: Record<string, number> = {};
  const postErrorRel: number[] = [];

  for (const [w, tr] of traces) {
    const target = tr.target;
    if (target.length === 0) continue;
    const firsts: (Stroke | undefined)[] = [];
    for (const s of tr.strokes) {
      if (s.first && !s.commit && s.pos < target.length) firsts[s.pos] = s;
    }
    const complete =
      firsts.filter((s) => s !== undefined).length === target.length;
    const anyError =
      tr.strokes.some((s) => s.first && !s.ok) ||
      (tr.committed && !tr.commitOk);
    const clean = complete && !anyError && !tr.hadDelete;
    const key = lower(target);

    if (complete || tr.committed) {
      if (cfg.trackWords && target.length >= 2 && !key.includes(" ")) {
        acc(`w:${key}`, anyError);
        if (clean) {
          const inner = firsts.slice(1) as Stroke[];
          if (inner.length > 0 && inner.every((s) => s.timed)) {
            time(`w:${key}`, mean(inner.map((s) => s.dt)));
          }
        }
      }
      const bucket = `c:len-${lengthBucket(target.length)}`;
      acc(bucket, anyError);
      if (clean) {
        const inner = (firsts.slice(1) as Stroke[]).filter((s) => s.timed);
        if (inner.length > 0) time(bucket, mean(inner.map((s) => s.dt)));
      }
    }

    if (cfg.trackSyllables) {
      const spans = syllableSpans(key);
      if (spans.length > 1) {
        for (const [a, b] of spans) {
          if (b - a < 2 || b - a > 6) continue;
          const part = firsts.slice(a, b);
          if (part.some((s) => s === undefined)) continue;
          const ss = part as Stroke[];
          const id = `s:${key.slice(a, b)}`;
          acc(
            id,
            ss.some((s) => !s.ok),
          );
          const timedPart = a === 0 ? ss.slice(1) : ss;
          if (timedPart.length > 0 && timedPart.every((s) => s.timed)) {
            time(id, mean(timedPart.map((s) => s.dt)));
          }
        }
      }
    }

    if (anyError) {
      const cls = classifyFirstError(tr, targets[w + 1], geo);
      if (cls !== null) {
        errTypes[cls.type] = (errTypes[cls.type] ?? 0) + 1;
        if (cls.exp !== undefined && cls.typed !== undefined) {
          const pair = `${lower(cls.exp)}>${lower(cls.typed)}`;
          if (cls.type !== "case") {
            confusions[pair] = (confusions[pair] ?? 0) + 1;
          }
        }
      }
    }
  }

  // --- post-error slowdown: tempo of the clean keystrokes right after a recovery
  let sinceError = Infinity;
  for (const s of strokes) {
    if (s === null) {
      sinceError = 0;
      continue;
    }
    if (!s.ok) {
      sinceError = 0;
      continue;
    }
    if (s.timed && sinceError < 4) postErrorRel.push(s.dt / med);
    sinceError++;
  }

  // --- fatigue: tempo in the last third vs the first third
  const firstThird: number[] = [];
  const lastThird: number[] = [];
  for (const s of strokes) {
    if (s === null || !s.timed) continue;
    if (s.ms < testEnd / 3) firstThird.push(s.dt);
    else if (s.ms > (2 * testEnd) / 3) lastThird.push(s.dt);
  }
  const fatigue =
    firstThird.length >= 8 && lastThird.length >= 8
      ? mean(lastThird) / mean(firstThird)
      : 1;

  const m = mean(valid);
  const sd = Math.sqrt(mean(valid.map((v) => (v - m) * (v - m))));

  return {
    obs,
    errTypes,
    confusions,
    chars,
    errors,
    medianDt: med,
    errCost: errors > 0 ? recoveryMs / errors : 0,
    fatigue,
    postError: postErrorRel.length >= 3 ? mean(postErrorRel) : 1,
    cv: m > 0 ? sd / m : 0,
  };
}

export type TestMeta = {
  wpm: number;
  acc: number;
  mode: string;
  adaptive: boolean;
  intensity?: number;
};

export type IngestReport = {
  summary: SessionSummary;
  /** the units this test showed as weakest, for the after-test note */
  weakest: { id: string; weakness: number }[];
};

function ema(old: number, value: number, a: number): number {
  return old === 0 ? value : old + a * (value - old);
}

/** Fold one analyzed test into the profile (mutates it). */
export function ingest(
  profile: Profile,
  ex: Extraction,
  cfg: AdaptiveSettings,
  now: number,
  meta: TestMeta,
): IngestReport {
  // per touched unit: did it have an error, and when was it last seen before
  const touched = new Map<string, { error: boolean; prevSeen: number }>();
  for (const o of ex.obs) {
    let s = profile.units[o.id];
    if (s === undefined) {
      s = newStat(now, cfg.initialStability);
      profile.units[o.id] = s;
    }
    if (o.err !== undefined) {
      let entry = touched.get(o.id);
      if (entry === undefined) {
        entry = { error: false, prevSeen: s.ls };
        touched.set(o.id, entry);
      }
      if (o.err === 1) entry.error = true;
      observeAccuracy(s, o.err, cfg, now);
    }
    if (o.ms !== undefined && o.rel !== undefined) {
      observeTime(s, o.ms, o.rel, o.hes === true, cfg);
    }
  }

  const lam = Math.pow(0.5, 1 / cfg.halfLife);
  for (const key in profile.conf) {
    profile.conf[key] = (profile.conf[key] as number) * lam;
  }
  for (const [pair, count] of Object.entries(ex.confusions)) {
    profile.conf[pair] = (profile.conf[pair] ?? 0) + count;
  }
  for (const [type, count] of Object.entries(ex.errTypes)) {
    const k = type as ErrorType;
    profile.errTypes[k] = (profile.errTypes[k] ?? 0) + count;
  }

  profile.g.tests++;
  profile.g.chars += ex.chars;
  profile.g.medianDt = ema(profile.g.medianDt, ex.medianDt, 0.2);
  if (ex.errCost > 0) {
    profile.g.errCost = ema(profile.g.errCost, ex.errCost, 0.2);
  }
  if (!meta.adaptive) profile.g.wpm = ema(profile.g.wpm, meta.wpm, 0.2);

  // spaced repetition + peak tracking for everything this test touched
  const base = baselines(profile);
  const weakest: { id: string; weakness: number }[] = [];
  for (const [id, entry] of touched) {
    const s = profile.units[id] as Stat;
    if (entry.error) {
      s.st = Math.max(0.1, s.st * cfg.stabilityShrink);
    } else {
      // remembering something after a real gap is what proves the memory is
      // stable: a clean repeat seconds later earns almost nothing
      const gapDays = Math.max(0, (now - entry.prevSeen) / 86400000);
      const earned = Math.min(1, gapDays / Math.max(0.05, s.st));
      s.st = Math.min(365, s.st * (1 + (cfg.stabilityGrowth - 1) * earned));
    }
    const b = base[baselineKey(id)];
    if (b === undefined) continue;
    const sc = scoreUnit(id, s, b, profile, cfg, { now });
    const raw = Math.max(sc.components.accuracy, sc.components.speed);
    s.pk = Math.max(s.pk * 0.97, sc.level === "new" ? 0 : raw);
    if (sc.type !== "c" && sc.level !== "new") {
      weakest.push({ id, weakness: sc.weakness });
    }
  }
  weakest.sort((a, b) => b.weakness - a.weakness);

  prune(profile, cfg.maxUnits, now);

  const wi = weaknessIndex(scoreAll(profile, cfg, { now }));
  const summary: SessionSummary = {
    t: now,
    wpm: meta.wpm,
    acc: meta.acc,
    chars: ex.chars,
    mode: meta.mode,
    adaptive: meta.adaptive,
    wi,
    medianDt: ex.medianDt,
    errCost: ex.errCost,
    fatigue: ex.fatigue,
    postError: ex.postError,
    consistency: ex.cv,
    intensity: meta.intensity,
  };
  profile.sessions.push(summary);
  if (profile.sessions.length > cfg.maxSessions) {
    profile.sessions.splice(0, profile.sessions.length - cfg.maxSessions);
  }

  // difficulty controller: steer training tests towards the target accuracy
  if (meta.adaptive && cfg.autoDifficulty) {
    const delta = ((meta.acc - cfg.targetAccuracy) / 100) * cfg.difficultyGain;
    profile.g.intensity = Math.min(
      cfg.maxIntensity,
      Math.max(cfg.minIntensity, profile.g.intensity + delta),
    );
  }

  return { summary, weakest: weakest.slice(0, 5) };
}

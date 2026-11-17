#!/usr/bin/env bash
# Sets up a personal, local, frontend-only copy of Monkeytype (GPL-3.0)
# with the adaptive trainer added.
# Needs: git, Node 24.x, and pnpm 11.21.0 (npm i -g pnpm@11.21.0)
set -euo pipefail
git clone https://github.com/monkeytypegame/monkeytype.git monkeytype-local
cd monkeytype-local
git checkout -b local 84bbde8d1adf2f8c5b1d214c9c0f68810f109a5e
git apply <<'PATCH'
diff --git a/frontend/__tests__/adaptive/engine.spec.ts b/frontend/__tests__/adaptive/engine.spec.ts
new file mode 100644
index 0000000..0f361eb
--- /dev/null
+++ b/frontend/__tests__/adaptive/engine.spec.ts
@@ -0,0 +1,135 @@
+import { describe, expect, it } from "vitest";
+import { extract, ingest, LogLike } from "../../src/ts/adaptive/analyze";
+import { generate } from "../../src/ts/adaptive/generate";
+import { qwertyGeometry, syllableSpans } from "../../src/ts/adaptive/geometry";
+import { newProfile, scoreAll } from "../../src/ts/adaptive/model";
+import { defaultSettings } from "../../src/ts/adaptive/settings";
+
+function mulberry(seed: number): () => number {
+  let a = seed;
+  return () => {
+    a |= 0;
+    a = (a + 0x6d2b79f5) | 0;
+    let t = Math.imul(a ^ (a >>> 15), 1 | a);
+    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
+    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
+  };
+}
+
+const pool =
+  "the of and to in is you that it he was for on are as with his they at be this have from or one had by word but not what all were we when your can said there use an each which she do how their if will up other about out many then them these so some her would make like him into time has look two more write go see number no way could people my than first water been call who oil its now find long down day did get come made may part quiet quick queen quite equal question require square this that there think thing both month north south earth mother father other together".split(
+    " ",
+  );
+
+/** A typist who is slow on "th" and often hits "w" instead of "q". */
+function simulate(words: string[], rng: () => number): LogLike {
+  const events: LogLike["events"] = [];
+  let ms = 0;
+  const push = (data: Record<string, unknown>): void => {
+    events.push({ type: "input", testMs: ms, data });
+  };
+  words.forEach((word, w) => {
+    let input = "";
+    for (let i = 0; i < word.length; i++) {
+      const ch = word[i] as string;
+      const slow = i > 0 && word[i - 1] === "t" && ch === "h";
+      ms += (slow ? 260 : 110) + rng() * 30;
+      if (ch === "q" && rng() < 0.4) {
+        push({
+          wordIndex: w,
+          inputType: "insertText",
+          data: "w",
+          correct: false,
+        });
+        ms += 300;
+        push({
+          wordIndex: w,
+          inputType: "deleteContentBackward",
+          inputValue: input,
+        });
+        ms += 200;
+      }
+      push({ wordIndex: w, inputType: "insertText", data: ch, correct: true });
+      input += ch;
+    }
+    ms += 120;
+    push({
+      wordIndex: w,
+      inputType: "insertText",
+      data: " ",
+      correct: true,
+      commitsWord: true,
+    });
+  });
+  return { events, context: { targetWords: words.map((w) => `${w} `) } };
+}
+
+describe("adaptive engine", () => {
+  it("splits syllables", () => {
+    const parts = (w: string): string[] =>
+      syllableSpans(w).map(([a, b]) => w.slice(a, b));
+    expect(parts("together").join("")).toBe("together");
+    expect(parts("together").length).toBeGreaterThan(1);
+    expect(parts("the")).toEqual(["the"]);
+  });
+
+  it("finds planted weaknesses and targets them", () => {
+    const rng = mulberry(7);
+    const cfg = { ...defaultSettings, selection: "greedy" as const };
+    const profile = newProfile(0);
+    for (let test = 0; test < 12; test++) {
+      const words = Array.from(
+        { length: 60 },
+        () => pool[Math.floor(rng() * pool.length)] as string,
+      );
+      const ex = extract(simulate(words, rng), cfg, qwertyGeometry);
+      expect(ex.chars).toBeGreaterThan(100);
+      ingest(profile, ex, cfg, test * 1000, {
+        wpm: 80,
+        acc: 96,
+        mode: "words",
+        adaptive: false,
+      });
+    }
+    const scored = scoreAll(profile, cfg, { now: 12000 }).sort(
+      (a, b) => b.score - a.score,
+    );
+    const top = scored.slice(0, 12).map((s) => s.id);
+
+    expect(top).toContain("b:th");
+    expect(top.some((id) => id.includes("q"))).toBe(true);
+    expect(scored.find((s) => s.id === "k:q")?.level).toBe("critical");
+    expect(profile.conf["q>w"]).toBeGreaterThan(1);
+    expect(profile.g.errCost).toBeGreaterThan(200);
+
+    const plan = generate({
+      profile,
+      cfg,
+      pool,
+      geo: qwertyGeometry,
+      now: 12000,
+      rng,
+    });
+
+    expect(plan.words.length).toBe(cfg.wordCount);
+    const hits = plan.words.filter(
+      (w) => w.includes("th") || w.includes("q"),
+    ).length;
+    const baseRate =
+      pool.filter((w) => w.includes("th") || w.includes("q")).length /
+      pool.length;
+    expect(hits / plan.words.length).toBeGreaterThan(baseRate * 1.3);
+  });
+
+  it("generates plain words with an empty profile", () => {
+    const plan = generate({
+      profile: newProfile(0),
+      cfg: defaultSettings,
+      pool,
+      geo: qwertyGeometry,
+      now: 0,
+    });
+    expect(plan.informed).toBe(false);
+    expect(plan.words.length).toBe(defaultSettings.wordCount);
+  });
+});
diff --git a/frontend/__tests__/root/boot.spec.ts b/frontend/__tests__/root/boot.spec.ts
index 5e1851b..8a10d96 100644
--- a/frontend/__tests__/root/boot.spec.ts
+++ b/frontend/__tests__/root/boot.spec.ts
@@ -46,7 +46,8 @@ describe("boot", () => {
 
     // started before awaiting, so the first auth state change shows PSAs
     expect(initConnection).toHaveBeenCalledOnce();
-    expect(Psa.init).toHaveBeenCalledOnce();
+    // LOCAL: PSAs are disabled in this build (no backend)
+    expect(Psa.init).not.toHaveBeenCalled();
     expect(loadFromLocalStorage).toHaveBeenCalledOnce();
     expect(initFirebase).toHaveBeenCalledOnce();
 
@@ -58,7 +59,8 @@ describe("boot", () => {
     await booted;
 
     expect(isAppReady()).toBe(true);
-    expect(MerchBanner.showIfNotClosedBefore).toHaveBeenCalledOnce();
+    // LOCAL: no merch banner in this build
+    expect(MerchBanner.showIfNotClosedBefore).not.toHaveBeenCalled();
     expect(ServerConfiguration.sync).toHaveBeenCalledOnce();
   });
 });
diff --git a/frontend/firebase.json b/frontend/firebase.json
index d7603d4..ad339e4 100644
--- a/frontend/firebase.json
+++ b/frontend/firebase.json
@@ -4,7 +4,7 @@
     "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
     "rewrites": [
       {
-        "source": "/@(test|settings|account|about|login|profile|friends|account-settings|leaderboards){,/**}",
+        "source": "/@(test|settings|account|about|adaptive|login|profile|friends|account-settings|leaderboards){,/**}",
         "destination": "/index.html"
       },
       {
diff --git a/frontend/src/ts/adaptive/analyze.ts b/frontend/src/ts/adaptive/analyze.ts
new file mode 100644
index 0000000..43393dd
--- /dev/null
+++ b/frontend/src/ts/adaptive/analyze.ts
@@ -0,0 +1,640 @@
+// Passive analysis: turns the event log of one finished test into
+// observations and folds them into the profile.
+
+import {
+  Geometry,
+  isAdjacent,
+  isMirror,
+  pairClasses,
+  syllableSpans,
+} from "./geometry";
+import {
+  baselineKey,
+  baselines,
+  ErrorType,
+  newStat,
+  observeAccuracy,
+  observeTime,
+  Profile,
+  prune,
+  scoreAll,
+  scoreUnit,
+  SessionSummary,
+  Stat,
+  weaknessIndex,
+} from "./model";
+import { AdaptiveSettings } from "./settings";
+
+/** The subset of monkeytype's EventLog the analyzer reads. */
+export type LogLike = {
+  events: {
+    type: string;
+    testMs: number;
+    data: Record<string, unknown>;
+  }[];
+  context: { targetWords: string[] };
+};
+
+type Stroke = {
+  w: number;
+  pos: number;
+  /** expected char ("" when typed past the end of the word) */
+  exp: string;
+  typed: string;
+  ok: boolean;
+  /** first time this position of this word was attempted */
+  first: boolean;
+  ms: number;
+  dt: number;
+  /** the keystroke before it was the correct previous character */
+  contig: boolean;
+  /** dt is a usable timing sample */
+  timed: boolean;
+  commit: boolean;
+};
+
+type WordTrace = {
+  target: string;
+  strokes: Stroke[];
+  firstPass: string;
+  hadDelete: boolean;
+  committed: boolean;
+  commitOk: boolean;
+};
+
+export type Observation = {
+  id: string;
+  err?: 0 | 1;
+  ms?: number;
+  rel?: number;
+  hes?: boolean;
+};
+
+export type Extraction = {
+  obs: Observation[];
+  errTypes: Partial<Record<ErrorType, number>>;
+  confusions: Record<string, number>;
+  chars: number;
+  errors: number;
+  medianDt: number;
+  /** ms lost per error to noticing, deleting and retyping */
+  errCost: number;
+  /** relative latency of the last third of the test vs the first third */
+  fatigue: number;
+  /** relative latency right after recovering from an error */
+  postError: number;
+  /** coefficient of variation of keystroke intervals */
+  cv: number;
+};
+
+function median(values: number[]): number {
+  if (values.length === 0) return 0;
+  const sorted = [...values].sort((a, b) => a - b);
+  const mid = sorted.length >> 1;
+  return sorted.length % 2 === 1
+    ? (sorted[mid] as number)
+    : ((sorted[mid - 1] as number) + (sorted[mid] as number)) / 2;
+}
+
+function mean(values: number[]): number {
+  return values.length === 0
+    ? 0
+    : values.reduce((a, b) => a + b, 0) / values.length;
+}
+
+function lengthBucket(len: number): string {
+  return len <= 3 ? "short" : len <= 6 ? "medium" : len <= 9 ? "long" : "xlong";
+}
+
+const punctRe = /[^\p{L}\p{N}\s]/u;
+const digitRe = /\p{N}/u;
+
+function classifyFirstError(
+  trace: WordTrace,
+  nextTarget: string | undefined,
+  geo: Geometry,
+): { type: ErrorType; exp?: string; typed?: string } | null {
+  const fp = trace.firstPass;
+  const target = trace.target;
+  let p = 0;
+  while (p < fp.length && fp[p] === target[p]) p++;
+  if (p >= fp.length) {
+    // first pass was a clean prefix: the only possible mistake is the commit
+    if (trace.committed && !trace.hadDelete && fp.length < target.length) {
+      return { type: "early-space" };
+    }
+    return null;
+  }
+  const typed = fp[p] as string;
+  const exp = target[p];
+  const next = fp[p + 1];
+  if (exp === undefined) {
+    if (typed === nextTarget?.[0]) {
+      return { type: "missed-space" };
+    }
+    return { type: "insertion", typed };
+  }
+  if (typed === target[p + 1] && next === exp) return { type: "transposition" };
+  if (
+    typed === target[p + 1] &&
+    (next === undefined || next === target[p + 2])
+  ) {
+    return { type: "omission", exp };
+  }
+  if (p > 0 && typed === target[p - 1] && target[p - 1] !== exp) {
+    return { type: "doubling", typed };
+  }
+  if (next === exp) return { type: "insertion", typed };
+  if (typed.toLowerCase() === exp.toLowerCase()) {
+    return { type: "case", exp, typed };
+  }
+  if (isAdjacent(exp, typed, geo)) return { type: "adjacent", exp, typed };
+  if (isMirror(exp, typed, geo)) return { type: "mirror", exp, typed };
+  if (typed === " ") return { type: "other" };
+  return { type: "substitution", exp, typed };
+}
+
+export function extract(
+  log: LogLike,
+  cfg: AdaptiveSettings,
+  geo: Geometry,
+): Extraction {
+  const targets = log.context.targetWords.map((w) => w.replace(/[ \n]$/, ""));
+  const traces = new Map<number, WordTrace>();
+  const inputs = new Map<number, string>();
+  const attempted = new Map<number, number>();
+  const strokes: (Stroke | null)[] = [];
+  let lastMs: number | null = null;
+  let prev: { w: number; pos: number; ok: boolean } | null = null;
+  let recoveryMs = 0;
+  let testEnd = 0;
+
+  const traceOf = (w: number): WordTrace => {
+    let tr = traces.get(w);
+    if (tr === undefined) {
+      tr = {
+        target: targets[w] as string,
+        strokes: [],
+        firstPass: "",
+        hadDelete: false,
+        committed: false,
+        commitOk: false,
+      };
+      traces.set(w, tr);
+    }
+    return tr;
+  };
+
+  for (const ev of log.events) {
+    if (ev.type !== "input") continue;
+    const d = ev.data;
+    if (d["automatic"] === true) continue;
+    const w = d["wordIndex"] as number;
+    if (targets[w] === undefined) continue;
+    const target = targets[w];
+    const tr = traceOf(w);
+    const cur = inputs.get(w) ?? "";
+    const dt = lastMs === null ? NaN : ev.testMs - lastMs;
+    lastMs = ev.testMs;
+    testEnd = ev.testMs;
+    const inputType = d["inputType"] as string;
+
+    if (inputType.startsWith("delete")) {
+      tr.hadDelete = true;
+      if (typeof d["inputValue"] === "string") {
+        inputs.set(w, d["inputValue"]);
+      } else {
+        inputs.set(w, cur.slice(0, -1));
+      }
+      if (Number.isFinite(dt) && dt < cfg.maxPauseMs) recoveryMs += dt;
+      prev = null;
+      strokes.push(null);
+      continue;
+    }
+
+    const ch = d["data"];
+    if (
+      d["inputStopped"] === true ||
+      typeof ch !== "string" ||
+      ch.length !== 1
+    ) {
+      // composition / blocked input: keep the reconstruction in sync, skip stats
+      if (typeof ch === "string" && d["inputStopped"] !== true) {
+        inputs.set(w, cur + ch);
+      }
+      prev = null;
+      strokes.push(null);
+      continue;
+    }
+
+    if (d["commitsWord"] === true && (ch === " " || ch === "\n")) {
+      // the space itself is right when pressed at the end of the word, whatever
+      // was typed before it; pressed early it is a miss of the skipped letter
+      const early = cur.length < target.length;
+      const ok = !early;
+      const pos = early ? cur.length : target.length;
+      const s: Stroke = {
+        w,
+        pos,
+        exp: early ? (target[pos] as string) : " ",
+        typed: " ",
+        ok,
+        first: early ? pos > (attempted.get(w) ?? -1) : true,
+        ms: ev.testMs,
+        dt,
+        contig: prev?.w === w && prev.pos === pos - 1 && prev.ok,
+        timed: false,
+        commit: true,
+      };
+      tr.committed = true;
+      tr.commitOk = cur === target;
+      tr.strokes.push(s);
+      strokes.push(s);
+      prev = { w: w + 1, pos: -1, ok };
+      continue;
+    }
+
+    const pos = cur.length;
+    const exp = target[pos] ?? "";
+    const ok = ch === exp;
+    const first = pos > (attempted.get(w) ?? -1);
+    if (first) attempted.set(w, pos);
+    const s: Stroke = {
+      w,
+      pos,
+      exp,
+      typed: ch,
+      ok,
+      first,
+      ms: ev.testMs,
+      dt,
+      contig: prev?.w === w && prev.pos === pos - 1 && prev.ok,
+      timed: false,
+      commit: false,
+    };
+    if (!tr.hadDelete) tr.firstPass += ch;
+    if ((!first || !ok) && Number.isFinite(dt) && dt < cfg.maxPauseMs) {
+      recoveryMs += dt;
+    }
+    inputs.set(w, cur + ch);
+    tr.strokes.push(s);
+    strokes.push(s);
+    prev = { w, pos, ok };
+  }
+
+  // --- timing validity + the test's own tempo
+  const valid: number[] = [];
+  for (const s of strokes) {
+    if (s === null) continue;
+    s.timed =
+      s.first &&
+      s.ok &&
+      s.contig &&
+      Number.isFinite(s.dt) &&
+      s.dt > 0 &&
+      s.dt <= cfg.maxPauseMs;
+    if (s.timed) valid.push(s.dt);
+  }
+  const med = median(valid) || 150;
+  const hesMs = med * cfg.hesitationFactor;
+
+  const obs: Observation[] = [];
+  const acc = (id: string, err: boolean): void => {
+    obs.push({ id, err: err ? 1 : 0 });
+  };
+  const time = (id: string, ms: number): void => {
+    obs.push({ id, ms, rel: ms / med, hes: ms > hesMs });
+  };
+  const lower = (s: string): string => s.toLowerCase();
+  const usable = (text: string): boolean =>
+    cfg.trackSpaceNgrams || !text.includes(" ");
+
+  let chars = 0;
+  let errors = 0;
+
+  // --- per keystroke: keys, n-grams, fingers, motion patterns
+  for (let i = 0; i < strokes.length; i++) {
+    const s = strokes[i];
+    if (s === null || s === undefined || !s.first) continue;
+    const target = targets[s.w] as string;
+    chars++;
+    if (!s.ok) errors++;
+    if (s.exp === "") {
+      // typed past the end of the word: a missed space
+      acc("k: ", true);
+      continue;
+    }
+    const c = lower(s.exp);
+    const p1 =
+      s.pos > 0 ? lower(target[s.pos - 1] as string) : s.w > 0 ? " " : "";
+    const p2 =
+      s.pos > 1
+        ? lower(target[s.pos - 2] as string)
+        : s.pos === 1 && s.w > 0
+          ? " "
+          : "";
+    const before = strokes[i - 1];
+    const before2 = strokes[i - 2];
+    const ctx1 = s.contig;
+    const ctx2 = ctx1 && before?.contig === true;
+
+    acc(`k:${c}`, !s.ok);
+    if (s.timed) time(`k:${c}`, s.dt);
+
+    const info = geo.keys.get(s.exp) ?? geo.keys.get(c);
+    if (info !== undefined) {
+      acc(`c:finger-${info.finger}`, !s.ok);
+      if (s.timed) time(`c:finger-${info.finger}`, s.dt);
+      if (info.finger !== 8) {
+        acc(`c:row-${info.row}`, !s.ok);
+        if (s.timed) time(`c:row-${info.row}`, s.dt);
+      }
+    }
+    if (s.exp !== c) {
+      acc("c:capital", !s.ok);
+      if (s.timed) time("c:capital", s.dt);
+    } else if (digitRe.test(c)) {
+      acc("c:number", !s.ok);
+      if (s.timed) time("c:number", s.dt);
+    } else if (c !== " " && punctRe.test(c)) {
+      acc("c:punctuation", !s.ok);
+      if (s.timed) time("c:punctuation", s.dt);
+    }
+    if (s.pos === 0 && s.w > 0) {
+      acc("c:word-start", !s.ok);
+      if (s.timed) time("c:word-start", s.dt);
+    }
+
+    if (p1 !== "" && ctx1) {
+      const bg = p1 + c;
+      if (cfg.trackBigrams && usable(bg)) {
+        acc(`b:${bg}`, !s.ok);
+        if (s.timed) time(`b:${bg}`, s.dt);
+      }
+      for (const cls of pairClasses(p1, c, geo)) {
+        acc(`c:${cls}`, !s.ok);
+        if (s.timed) time(`c:${cls}`, s.dt);
+      }
+      if (cfg.trackTrigrams && p2 !== "" && ctx2) {
+        const tg = p2 + bg;
+        if (usable(tg)) {
+          acc(`t:${tg}`, !s.ok);
+          if (
+            s.timed &&
+            before !== null &&
+            before !== undefined &&
+            before.timed &&
+            before2 !== undefined
+          ) {
+            time(`t:${tg}`, (s.dt + before.dt) / 2);
+          }
+        }
+      }
+    }
+  }
+
+  // --- per word: words, syllables, length classes, error taxonomy
+  const errTypes: Partial<Record<ErrorType, number>> = {};
+  const confusions: Record<string, number> = {};
+  const postErrorRel: number[] = [];
+
+  for (const [w, tr] of traces) {
+    const target = tr.target;
+    if (target.length === 0) continue;
+    const firsts: (Stroke | undefined)[] = [];
+    for (const s of tr.strokes) {
+      if (s.first && !s.commit && s.pos < target.length) firsts[s.pos] = s;
+    }
+    const complete =
+      firsts.filter((s) => s !== undefined).length === target.length;
+    const anyError =
+      tr.strokes.some((s) => s.first && !s.ok) ||
+      (tr.committed && !tr.commitOk);
+    const clean = complete && !anyError && !tr.hadDelete;
+    const key = lower(target);
+
+    if (complete || tr.committed) {
+      if (cfg.trackWords && target.length >= 2 && !key.includes(" ")) {
+        acc(`w:${key}`, anyError);
+        if (clean) {
+          const inner = firsts.slice(1) as Stroke[];
+          if (inner.length > 0 && inner.every((s) => s.timed)) {
+            time(`w:${key}`, mean(inner.map((s) => s.dt)));
+          }
+        }
+      }
+      const bucket = `c:len-${lengthBucket(target.length)}`;
+      acc(bucket, anyError);
+      if (clean) {
+        const inner = (firsts.slice(1) as Stroke[]).filter((s) => s.timed);
+        if (inner.length > 0) time(bucket, mean(inner.map((s) => s.dt)));
+      }
+    }
+
+    if (cfg.trackSyllables) {
+      const spans = syllableSpans(key);
+      if (spans.length > 1) {
+        for (const [a, b] of spans) {
+          if (b - a < 2 || b - a > 6) continue;
+          const part = firsts.slice(a, b);
+          if (part.some((s) => s === undefined)) continue;
+          const ss = part as Stroke[];
+          const id = `s:${key.slice(a, b)}`;
+          acc(
+            id,
+            ss.some((s) => !s.ok),
+          );
+          const timedPart = a === 0 ? ss.slice(1) : ss;
+          if (timedPart.length > 0 && timedPart.every((s) => s.timed)) {
+            time(id, mean(timedPart.map((s) => s.dt)));
+          }
+        }
+      }
+    }
+
+    if (anyError) {
+      const cls = classifyFirstError(tr, targets[w + 1], geo);
+      if (cls !== null) {
+        errTypes[cls.type] = (errTypes[cls.type] ?? 0) + 1;
+        if (cls.exp !== undefined && cls.typed !== undefined) {
+          const pair = `${lower(cls.exp)}>${lower(cls.typed)}`;
+          if (cls.type !== "case") {
+            confusions[pair] = (confusions[pair] ?? 0) + 1;
+          }
+        }
+      }
+    }
+  }
+
+  // --- post-error slowdown: tempo of the clean keystrokes right after a recovery
+  let sinceError = Infinity;
+  for (const s of strokes) {
+    if (s === null) {
+      sinceError = 0;
+      continue;
+    }
+    if (!s.ok) {
+      sinceError = 0;
+      continue;
+    }
+    if (s.timed && sinceError < 4) postErrorRel.push(s.dt / med);
+    sinceError++;
+  }
+
+  // --- fatigue: tempo in the last third vs the first third
+  const firstThird: number[] = [];
+  const lastThird: number[] = [];
+  for (const s of strokes) {
+    if (s === null || !s.timed) continue;
+    if (s.ms < testEnd / 3) firstThird.push(s.dt);
+    else if (s.ms > (2 * testEnd) / 3) lastThird.push(s.dt);
+  }
+  const fatigue =
+    firstThird.length >= 8 && lastThird.length >= 8
+      ? mean(lastThird) / mean(firstThird)
+      : 1;
+
+  const m = mean(valid);
+  const sd = Math.sqrt(mean(valid.map((v) => (v - m) * (v - m))));
+
+  return {
+    obs,
+    errTypes,
+    confusions,
+    chars,
+    errors,
+    medianDt: med,
+    errCost: errors > 0 ? recoveryMs / errors : 0,
+    fatigue,
+    postError: postErrorRel.length >= 3 ? mean(postErrorRel) : 1,
+    cv: m > 0 ? sd / m : 0,
+  };
+}
+
+export type TestMeta = {
+  wpm: number;
+  acc: number;
+  mode: string;
+  adaptive: boolean;
+  intensity?: number;
+};
+
+export type IngestReport = {
+  summary: SessionSummary;
+  /** the units this test showed as weakest, for the after-test note */
+  weakest: { id: string; weakness: number }[];
+};
+
+function ema(old: number, value: number, a: number): number {
+  return old === 0 ? value : old + a * (value - old);
+}
+
+/** Fold one analyzed test into the profile (mutates it). */
+export function ingest(
+  profile: Profile,
+  ex: Extraction,
+  cfg: AdaptiveSettings,
+  now: number,
+  meta: TestMeta,
+): IngestReport {
+  // per touched unit: did it have an error, and when was it last seen before
+  const touched = new Map<string, { error: boolean; prevSeen: number }>();
+  for (const o of ex.obs) {
+    let s = profile.units[o.id];
+    if (s === undefined) {
+      s = newStat(now, cfg.initialStability);
+      profile.units[o.id] = s;
+    }
+    if (o.err !== undefined) {
+      let entry = touched.get(o.id);
+      if (entry === undefined) {
+        entry = { error: false, prevSeen: s.ls };
+        touched.set(o.id, entry);
+      }
+      if (o.err === 1) entry.error = true;
+      observeAccuracy(s, o.err, cfg, now);
+    }
+    if (o.ms !== undefined && o.rel !== undefined) {
+      observeTime(s, o.ms, o.rel, o.hes === true, cfg);
+    }
+  }
+
+  const lam = Math.pow(0.5, 1 / cfg.halfLife);
+  for (const key in profile.conf) {
+    profile.conf[key] = (profile.conf[key] as number) * lam;
+  }
+  for (const [pair, count] of Object.entries(ex.confusions)) {
+    profile.conf[pair] = (profile.conf[pair] ?? 0) + count;
+  }
+  for (const [type, count] of Object.entries(ex.errTypes)) {
+    const k = type as ErrorType;
+    profile.errTypes[k] = (profile.errTypes[k] ?? 0) + count;
+  }
+
+  profile.g.tests++;
+  profile.g.chars += ex.chars;
+  profile.g.medianDt = ema(profile.g.medianDt, ex.medianDt, 0.2);
+  if (ex.errCost > 0) {
+    profile.g.errCost = ema(profile.g.errCost, ex.errCost, 0.2);
+  }
+  if (!meta.adaptive) profile.g.wpm = ema(profile.g.wpm, meta.wpm, 0.2);
+
+  // spaced repetition + peak tracking for everything this test touched
+  const base = baselines(profile);
+  const weakest: { id: string; weakness: number }[] = [];
+  for (const [id, entry] of touched) {
+    const s = profile.units[id] as Stat;
+    if (entry.error) {
+      s.st = Math.max(0.1, s.st * cfg.stabilityShrink);
+    } else {
+      // remembering something after a real gap is what proves the memory is
+      // stable: a clean repeat seconds later earns almost nothing
+      const gapDays = Math.max(0, (now - entry.prevSeen) / 86400000);
+      const earned = Math.min(1, gapDays / Math.max(0.05, s.st));
+      s.st = Math.min(365, s.st * (1 + (cfg.stabilityGrowth - 1) * earned));
+    }
+    const b = base[baselineKey(id)];
+    if (b === undefined) continue;
+    const sc = scoreUnit(id, s, b, profile, cfg, { now });
+    const raw = Math.max(sc.components.accuracy, sc.components.speed);
+    s.pk = Math.max(s.pk * 0.97, sc.level === "new" ? 0 : raw);
+    if (sc.type !== "c" && sc.level !== "new") {
+      weakest.push({ id, weakness: sc.weakness });
+    }
+  }
+  weakest.sort((a, b) => b.weakness - a.weakness);
+
+  prune(profile, cfg.maxUnits, now);
+
+  const wi = weaknessIndex(scoreAll(profile, cfg, { now }));
+  const summary: SessionSummary = {
+    t: now,
+    wpm: meta.wpm,
+    acc: meta.acc,
+    chars: ex.chars,
+    mode: meta.mode,
+    adaptive: meta.adaptive,
+    wi,
+    medianDt: ex.medianDt,
+    errCost: ex.errCost,
+    fatigue: ex.fatigue,
+    postError: ex.postError,
+    consistency: ex.cv,
+    intensity: meta.intensity,
+  };
+  profile.sessions.push(summary);
+  if (profile.sessions.length > cfg.maxSessions) {
+    profile.sessions.splice(0, profile.sessions.length - cfg.maxSessions);
+  }
+
+  // difficulty controller: steer training tests towards the target accuracy
+  if (meta.adaptive && cfg.autoDifficulty) {
+    const delta = ((meta.acc - cfg.targetAccuracy) / 100) * cfg.difficultyGain;
+    profile.g.intensity = Math.min(
+      cfg.maxIntensity,
+      Math.max(cfg.minIntensity, profile.g.intensity + delta),
+    );
+  }
+
+  return { summary, weakest: weakest.slice(0, 5) };
+}
diff --git a/frontend/src/ts/adaptive/generate.ts b/frontend/src/ts/adaptive/generate.ts
new file mode 100644
index 0000000..3b05076
--- /dev/null
+++ b/frontend/src/ts/adaptive/generate.ts
@@ -0,0 +1,654 @@
+// Test generation: picks focus targets from the scored profile and builds a
+// word sequence that concentrates on them.
+
+import { Geometry, pairClasses, syllableSpans } from "./geometry";
+import {
+  Profile,
+  Rng,
+  Scored,
+  scoreAll,
+  textOf,
+  typeLabels,
+  typeOf,
+  UnitType,
+} from "./model";
+import { AdaptiveSettings, effectiveWeights } from "./settings";
+
+export type Target = {
+  id: string;
+  type: UnitType;
+  text: string;
+  score: number;
+  weakness: number;
+  reason: string;
+};
+
+export type Plan = {
+  words: string[];
+  targets: Target[];
+  intensity: number;
+  /** how many words of each origin ended up in the test */
+  mix: { targeted: number; filler: number; pseudo: number; drill: number };
+  /** false when the profile has too little data and the test is plain words */
+  informed: boolean;
+};
+
+const lengthBucket = (len: number): string =>
+  len <= 3 ? "short" : len <= 6 ? "medium" : len <= 9 ? "long" : "xlong";
+
+const digitRe = /\p{N}/u;
+const punctRe = /[^\p{L}\p{N}\s]/u;
+
+/** Every unit id a word exercises (same naming as the analyzer). */
+export function unitsOfWord(
+  word: string,
+  cfg: AdaptiveSettings,
+  geo: Geometry,
+): string[] {
+  const out = new Set<string>();
+  const w = word.toLowerCase();
+  const padded = cfg.trackSpaceNgrams ? ` ${w} ` : w;
+  for (let i = 0; i < w.length; i++) {
+    const c = w[i] as string;
+    out.add(`k:${c}`);
+    const info = geo.keys.get(word[i] as string) ?? geo.keys.get(c);
+    if (info !== undefined) {
+      out.add(`c:finger-${info.finger}`);
+      if (info.finger !== 8) out.add(`c:row-${info.row}`);
+    }
+    if (word[i] !== c) out.add("c:capital");
+    else if (digitRe.test(c)) out.add("c:number");
+    else if (punctRe.test(c)) out.add("c:punctuation");
+    if (i > 0) {
+      for (const cls of pairClasses(w[i - 1] as string, c, geo)) {
+        out.add(`c:${cls}`);
+      }
+    }
+  }
+  if (cfg.trackBigrams) {
+    for (let i = 0; i + 2 <= padded.length; i++) {
+      out.add(`b:${padded.slice(i, i + 2)}`);
+    }
+  }
+  if (cfg.trackTrigrams) {
+    for (let i = 0; i + 3 <= padded.length; i++) {
+      out.add(`t:${padded.slice(i, i + 3)}`);
+    }
+  }
+  if (cfg.trackSyllables) {
+    const spans = syllableSpans(w);
+    if (spans.length > 1) {
+      for (const [a, b] of spans) {
+        if (b - a >= 2 && b - a <= 6) out.add(`s:${w.slice(a, b)}`);
+      }
+    }
+  }
+  if (cfg.trackWords && w.length >= 2) out.add(`w:${w}`);
+  out.add(`c:len-${lengthBucket(w.length)}`);
+  return [...out];
+}
+
+function describe(s: Scored): string {
+  const c = s.components;
+  const parts: [number, string][] = [
+    [c.accuracy, `${(s.errorRate * 100).toFixed(1)}% errors`],
+    [c.speed, `${Math.round((s.relLatency - 1) * 100)}% slower`],
+    [c.consistency, "erratic timing"],
+    [c.hesitation, "hesitations"],
+    [c.trend, "getting worse"],
+    [c.forgetting, "due for review"],
+  ];
+  parts.sort((a, b) => b[0] - a[0]);
+  const top = parts.filter((p) => p[0] > 0.08).slice(0, 2);
+  if (top.length === 0) {
+    return s.level === "new" ? "not enough data yet" : "exploring";
+  }
+  return top.map((p) => p[1]).join(", ");
+}
+
+function weightedPick<T>(
+  items: T[],
+  weight: (item: T) => number,
+  rng: Rng,
+): T | undefined {
+  let total = 0;
+  for (const it of items) total += Math.max(0, weight(it));
+  if (total <= 0) return items[Math.floor(rng() * items.length)];
+  let r = rng() * total;
+  for (const it of items) {
+    r -= Math.max(0, weight(it));
+    if (r <= 0) return it;
+  }
+  return items[items.length - 1];
+}
+
+/** Choose what this test concentrates on. */
+export function selectTargets(
+  profile: Profile,
+  cfg: AdaptiveSettings,
+  now: number,
+  rng: Rng,
+): { targets: Target[]; scored: Scored[] } {
+  const draw =
+    cfg.selection === "thompson"
+      ? "thompson"
+      : cfg.selection === "ucb"
+        ? "ucb"
+        : "mean";
+  const eff = effectiveWeights(cfg);
+  const scored = scoreAll(profile, cfg, { now, draw, rng, ...eff }).filter(
+    (s) => s.score > 0,
+  );
+  // length classes and the space bar cannot be targeted by choosing words
+  const eligible = scored.filter(
+    (s) =>
+      !s.id.startsWith("c:len-") &&
+      s.id !== "c:word-start" &&
+      s.id !== "c:finger-8" &&
+      s.id !== "k: ",
+  );
+  eligible.sort((a, b) => b.score - a.score);
+
+  let chosen: Scored[];
+  if (cfg.selection === "softmax") {
+    const candidates = eligible.slice(0, Math.max(cfg.focusCount * 8, 40));
+    const max = candidates[0]?.score ?? 1;
+    chosen = [];
+    const left = [...candidates];
+    while (chosen.length < cfg.focusCount && left.length > 0) {
+      const pick = weightedPick(
+        left,
+        (s) =>
+          Math.exp((s.score - max) / Math.max(0.02, cfg.temperature * max)),
+        rng,
+      ) as Scored;
+      chosen.push(pick);
+      left.splice(left.indexOf(pick), 1);
+    }
+    chosen.sort((a, b) => b.score - a.score);
+  } else {
+    chosen = eligible.slice(0, cfg.focusCount);
+  }
+
+  return {
+    scored,
+    targets: chosen.map((s) => ({
+      id: s.id,
+      type: s.type,
+      text: s.text,
+      score: s.score,
+      weakness: s.weakness,
+      reason: describe(s),
+    })),
+  };
+}
+
+type MarkovModel = Map<string, { next: string[]; count: number[] }>;
+
+function buildMarkov(words: string[]): MarkovModel {
+  const model: MarkovModel = new Map();
+  for (const word of words) {
+    const w = `^^${word.toLowerCase()}$`;
+    for (let i = 2; i < w.length; i++) {
+      const ctx = w.slice(i - 2, i);
+      const ch = w[i] as string;
+      let node = model.get(ctx);
+      if (node === undefined) {
+        node = { next: [], count: [] };
+        model.set(ctx, node);
+      }
+      const idx = node.next.indexOf(ch);
+      if (idx === -1) {
+        node.next.push(ch);
+        node.count.push(1);
+      } else {
+        node.count[idx] = (node.count[idx] ?? 0) + 1;
+      }
+    }
+  }
+  return model;
+}
+
+/**
+ * A pronounceable non-word from a character trigram model of the pool, with
+ * transitions that produce weak n-grams boosted.
+ */
+function pseudoWord(
+  model: MarkovModel,
+  boost: Map<string, number>,
+  rng: Rng,
+  minLen: number,
+  maxLen: number,
+): string | null {
+  for (let attempt = 0; attempt < 12; attempt++) {
+    let out = "";
+    let ctx = "^^";
+    for (let i = 0; i < maxLen + 1; i++) {
+      const node = model.get(ctx);
+      if (node === undefined) break;
+      const prev1 = ctx[1] === "^" ? " " : (ctx[1] as string);
+      const prev2 = ctx.startsWith("^") ? " " : (ctx[0] as string);
+      const idx = weightedPick(
+        node.next.map((_, j) => j),
+        (j) => {
+          const ch = node.next[j] as string;
+          let weight = node.count[j] as number;
+          if (ch === "$") {
+            return out.length < minLen
+              ? 0
+              : weight * (out.length / maxLen + 0.3);
+          }
+          const b = boost.get(`b:${prev1}${ch}`) ?? 0;
+          const t = boost.get(`t:${prev2}${prev1}${ch}`) ?? 0;
+          const k = boost.get(`k:${ch}`) ?? 0;
+          weight *= 1 + 12 * b + 16 * t + 4 * k;
+          return weight;
+        },
+        rng,
+      );
+      if (idx === undefined) break;
+      const ch = node.next[idx] as string;
+      if (ch === "$") break;
+      out += ch;
+      ctx = (ctx[1] as string) + ch;
+    }
+    if (out.length >= minLen && out.length <= maxLen) return out;
+  }
+  return null;
+}
+
+function drillToken(target: Target, rng: Rng): string | null {
+  if (target.type !== "b" && target.type !== "t" && target.type !== "s") {
+    return null;
+  }
+  const g = target.text.replace(/ /g, "");
+  if (g.length < 2) return null;
+  const reps = g.length >= 4 ? 2 : 2 + Math.floor(rng() * 2);
+  return g.repeat(reps);
+}
+
+function shuffle<T>(arr: T[], rng: Rng): T[] {
+  for (let i = arr.length - 1; i > 0; i--) {
+    const j = Math.floor(rng() * (i + 1));
+    [arr[i], arr[j]] = [arr[j] as T, arr[i] as T];
+  }
+  return arr;
+}
+
+export type PoolIndex = {
+  words: string[];
+  units: string[][];
+};
+
+export function indexPool(
+  pool: string[],
+  cfg: AdaptiveSettings,
+  geo: Geometry,
+): PoolIndex {
+  const seen = new Set<string>();
+  const words: string[] = [];
+  for (const w of pool) {
+    if (words.length >= cfg.poolSize) break;
+    if (w.includes(" ") || seen.has(w)) continue;
+    if (w.length < cfg.minWordLength || w.length > cfg.maxWordLength) continue;
+    seen.add(w);
+    words.push(w);
+  }
+  return { words, units: words.map((w) => unitsOfWord(w, cfg, geo)) };
+}
+
+/** Score every pool word against the focus targets and the general weakness map. */
+export function scoreWords(
+  index: PoolIndex,
+  targets: Target[],
+  scored: Scored[],
+  profile: Profile,
+  cfg: AdaptiveSettings,
+): Float64Array {
+  const focus = new Map<string, number>();
+  const maxScore = targets[0]?.score ?? 1;
+  for (const t of targets) focus.set(t.id, t.score / (maxScore || 1));
+  const general = new Map<string, number>();
+  for (const s of scored) general.set(s.id, s.score);
+
+  // letters the typist swaps: words holding both are good discrimination practice
+  const pairs = Object.entries(profile.conf)
+    .filter(([, count]) => count >= 1.5)
+    .sort((a, b) => b[1] - a[1])
+    .slice(0, 6)
+    .map(([pair]) => pair.split(">") as [string, string]);
+
+  const out = new Float64Array(index.words.length);
+  for (let i = 0; i < index.words.length; i++) {
+    const units = index.units[i] as string[];
+    const word = index.words[i] as string;
+    let f = 0;
+    let g = 0;
+    let gn = 0;
+    for (const u of units) {
+      const fw = focus.get(u);
+      if (fw !== undefined) f += fw;
+      const gs = general.get(u);
+      if (gs !== undefined && typeOf(u) !== "c") {
+        g += gs;
+        gn++;
+      }
+    }
+    let score = f / Math.sqrt(Math.max(2, word.length) / 4);
+    if (gn > 0) score += cfg.broadFactor * (g / gn) * 2;
+    if (cfg.confusionBonus > 0) {
+      for (const [a, b] of pairs) {
+        if (word.includes(a) && word.includes(b)) {
+          score += cfg.confusionBonus * 0.5;
+          break;
+        }
+      }
+    }
+    out[i] = score;
+  }
+  return out;
+}
+
+function categoryActive(
+  mode: "off" | "auto" | "on",
+  id: string,
+  scored: Scored[],
+): boolean {
+  if (mode === "on") return true;
+  if (mode === "off") return false;
+  const s = scored.find((x) => x.id === id);
+  return s !== undefined && s.level !== "new" && s.weakness >= 0.14;
+}
+
+const punctuationMarks = [",", ".", ",", ".", ";", "?", "!", ":"];
+
+export type GenerateInput = {
+  profile: Profile;
+  cfg: AdaptiveSettings;
+  pool: string[];
+  geo: Geometry;
+  now: number;
+  rng?: Rng;
+  /** overrides the word count (time mode needs enough words to fill the time) */
+  count?: number;
+};
+
+export function generate(input: GenerateInput): Plan {
+  const { profile, cfg, geo, now } = input;
+  const rng = input.rng ?? Math.random;
+  const count = input.count ?? cfg.wordCount;
+  const index = indexPool(input.pool, cfg, geo);
+  const intensity = cfg.autoDifficulty ? profile.g.intensity : cfg.intensity;
+  const { targets, scored } = selectTargets(profile, cfg, now, rng);
+  const informed = targets.length > 0 && profile.g.chars >= 100;
+
+  if (index.words.length === 0) {
+    return {
+      words: [],
+      targets: [],
+      intensity,
+      mix: { targeted: 0, filler: 0, pseudo: 0, drill: 0 },
+      informed: false,
+    };
+  }
+
+  const wordScores = scoreWords(index, targets, scored, profile, cfg);
+
+  // candidate list: the best scoring slice of the pool
+  const order = Array.from(index.words.keys()).sort(
+    (a, b) => (wordScores[b] as number) - (wordScores[a] as number),
+  );
+  const topN = Math.max(
+    30,
+    Math.min(order.length, Math.round(order.length * 0.15)),
+  );
+  const top = order.slice(0, topN);
+  const best = wordScores[top[0] as number] ?? 1;
+  const temp = Math.max(0.02, cfg.temperature) * (best || 1);
+  const sampleWeight = (i: number): number =>
+    Math.exp(((wordScores[i] as number) - best) / temp);
+
+  const nTargeted = informed ? Math.round(count * intensity) : 0;
+  const nPseudo = informed ? Math.round(nTargeted * cfg.pseudoWordRatio) : 0;
+  const nDrill = informed ? Math.round(nTargeted * cfg.drillRatio) : 0;
+  const nReal = Math.max(0, nTargeted - nPseudo - nDrill);
+
+  type Token = {
+    word: string;
+    kind: "targeted" | "filler" | "pseudo" | "drill";
+    block?: number;
+  };
+  const tokens: Token[] = [];
+
+  // --- real words rich in targets
+  const blockedShare =
+    cfg.structure === "blocked" ? 1 : cfg.structure === "progressive" ? 0.5 : 0;
+  const nBlocked = Math.round(nReal * blockedShare);
+  const blocked: Token[] = [];
+  if (nBlocked > 0 && targets.length > 0) {
+    let block = 0;
+    while (blocked.length < nBlocked) {
+      const target = targets[block % targets.length] as Target;
+      const holders = top.filter((i) =>
+        (index.units[i] as string[]).includes(target.id),
+      );
+      const source = holders.length >= 2 ? holders : top;
+      for (let j = 0; j < cfg.blockSize && blocked.length < nBlocked; j++) {
+        const i = weightedPick(source, sampleWeight, rng) as number;
+        blocked.push({
+          word: index.words[i] as string,
+          kind: "targeted",
+          block,
+        });
+      }
+      block++;
+      if (block > 500) break;
+    }
+  }
+  for (let j = 0; j < nReal - blocked.length; j++) {
+    const i = weightedPick(top, sampleWeight, rng) as number;
+    tokens.push({ word: index.words[i] as string, kind: "targeted" });
+  }
+
+  // --- pseudo-words from the biased character model
+  if (nPseudo > 0) {
+    const boost = new Map<string, number>();
+    const maxScore = targets[0]?.score ?? 1;
+    for (const t of targets) boost.set(t.id, t.score / (maxScore || 1));
+    const model = buildMarkov(index.words);
+    for (let j = 0; j < nPseudo; j++) {
+      const w = pseudoWord(
+        model,
+        boost,
+        rng,
+        Math.max(3, cfg.minWordLength),
+        Math.min(9, cfg.maxWordLength),
+      );
+      if (w !== null) tokens.push({ word: w, kind: "pseudo" });
+    }
+  }
+
+  // --- bare n-gram repetitions
+  if (nDrill > 0) {
+    const drillable = targets.filter(
+      (t) => t.type === "b" || t.type === "t" || t.type === "s",
+    );
+    for (let j = 0; j < nDrill && drillable.length > 0; j++) {
+      const w = drillToken(drillable[j % drillable.length] as Target, rng);
+      if (w !== null) tokens.push({ word: w, kind: "drill" });
+    }
+  }
+
+  // --- filler: ordinary words, so the test still reads like typing
+  const fillerCount = Math.max(0, count - tokens.length - blocked.length);
+  for (let j = 0; j < fillerCount; j++) {
+    const i = Math.floor(rng() * index.words.length);
+    tokens.push({ word: index.words[i] as string, kind: "filler" });
+  }
+
+  shuffle(tokens, rng);
+  // blocked groups go first (progressive: blocked warm-up, then interleaved)
+  let sequence: Token[] = [...blocked, ...tokens].slice(0, count);
+
+  // --- no immediate repeats
+  if (cfg.repeatWindow > 0) {
+    const fixed: Token[] = [];
+    for (const tok of sequence) {
+      const recent = new Set(fixed.slice(-cfg.repeatWindow).map((x) => x.word));
+      if (tok.block === undefined && recent.has(tok.word)) {
+        let replaced = false;
+        for (let tries = 0; tries < 8; tries++) {
+          const src = tok.kind === "targeted" ? top : order;
+          const i =
+            tok.kind === "targeted"
+              ? (weightedPick(src, sampleWeight, rng) as number)
+              : (src[Math.floor(rng() * src.length)] as number);
+          const w = index.words[i] as string;
+          if (!recent.has(w)) {
+            fixed.push({
+              word: w,
+              kind: tok.kind === "targeted" ? "targeted" : "filler",
+            });
+            replaced = true;
+            break;
+          }
+        }
+        if (!replaced) fixed.push(tok);
+      } else {
+        fixed.push(tok);
+      }
+    }
+    sequence = fixed;
+  }
+
+  // --- surface form: capitals, punctuation, numbers
+  const caps = categoryActive(cfg.capitalization, "c:capital", scored);
+  const punct = categoryActive(cfg.punctuation, "c:punctuation", scored);
+  const nums = categoryActive(cfg.numbers, "c:number", scored);
+  const words = sequence.map((tok) => {
+    let w = tok.word;
+    if (tok.kind === "drill") return w;
+    if (nums && rng() < cfg.numbersRate) {
+      return String(
+        Math.floor(rng() * Math.pow(10, 1 + Math.floor(rng() * 4))),
+      );
+    }
+    if (caps && rng() < cfg.capitalizationRate) {
+      w = w.charAt(0).toUpperCase() + w.slice(1);
+    }
+    if (punct && rng() < cfg.punctuationRate) {
+      w += punctuationMarks[
+        Math.floor(rng() * punctuationMarks.length)
+      ] as string;
+    }
+    return w;
+  });
+
+  const mix = { targeted: 0, filler: 0, pseudo: 0, drill: 0 };
+  for (const tok of sequence) mix[tok.kind]++;
+
+  return { words, targets: informed ? targets : [], intensity, mix, informed };
+}
+
+/**
+ * Passive blending: given the word the normal generator picked, maybe swap
+ * it for one from the same wordset that exercises weak units.
+ */
+export class PassiveBlender {
+  private key: string[] | null = null;
+  private stamp = -1;
+  private candidates: string[] = [];
+  private weights: number[] = [];
+
+  pick(
+    wordset: string[],
+    profile: Profile,
+    cfg: AdaptiveSettings,
+    geo: Geometry,
+    profileStamp: number,
+    now: number,
+    rng: Rng = Math.random,
+  ): string | null {
+    if (cfg.passiveBlend <= 0 || rng() >= cfg.passiveBlend) return null;
+    if (profile.g.chars < 300) return null;
+    if (this.key !== wordset || this.stamp !== profileStamp) {
+      this.key = wordset;
+      this.stamp = profileStamp;
+      const index = indexPool(wordset, { ...cfg, poolSize: 20000 }, geo);
+      // point estimates here: passive tests should drift, not jump around
+      const { targets, scored } = selectTargets(
+        profile,
+        {
+          ...cfg,
+          selection: "greedy",
+          focusCount: Math.max(cfg.focusCount, 12),
+        },
+        now,
+        rng,
+      );
+      const scores = scoreWords(index, targets, scored, profile, cfg);
+      const order = Array.from(index.words.keys()).sort(
+        (a, b) => (scores[b] as number) - (scores[a] as number),
+      );
+      const top = order.slice(0, Math.max(20, Math.round(order.length * 0.12)));
+      this.candidates = top.map((i) => index.words[i] as string);
+      this.weights = top.map((i) => scores[i] as number);
+    }
+    if (this.candidates.length === 0) return null;
+    const idx = weightedPick(
+      this.candidates.map((_, i) => i),
+      (i) => this.weights[i] as number,
+      rng,
+    );
+    return idx === undefined ? null : (this.candidates[idx] as string);
+  }
+}
+
+export function targetLabel(t: { type: UnitType; id: string }): string {
+  if (t.type === "c") return patternLabel(textOf(t.id));
+  return textOf(t.id).replace(/ /g, "␣");
+}
+
+const patternNames: Record<string, string> = {
+  sfb: "same-finger bigrams",
+  double: "double letters",
+  alt: "hand alternation",
+  "roll-in": "inward rolls",
+  "roll-out": "outward rolls",
+  rowjump: "row jumps",
+  stretch: "index stretches",
+  capital: "capitals",
+  number: "numbers",
+  punctuation: "punctuation",
+  "word-start": "word starts",
+  "len-short": "short words (1-3)",
+  "len-medium": "medium words (4-6)",
+  "len-long": "long words (7-9)",
+  "len-xlong": "very long words (10+)",
+  "row-0": "number row",
+  "row-1": "top row",
+  "row-2": "home row",
+  "row-3": "bottom row",
+};
+const fingers = [
+  "left pinky",
+  "left ring",
+  "left middle",
+  "left index",
+  "right index",
+  "right middle",
+  "right ring",
+  "right pinky",
+  "thumb",
+];
+
+export function patternLabel(name: string): string {
+  if (name.startsWith("finger-")) {
+    return fingers[Number(name.slice(7))] ?? name;
+  }
+  return patternNames[name] ?? name;
+}
+
+export function typeLabel(t: UnitType): string {
+  return typeLabels[t];
+}
diff --git a/frontend/src/ts/adaptive/geometry.ts b/frontend/src/ts/adaptive/geometry.ts
new file mode 100644
index 0000000..78b9b03
--- /dev/null
+++ b/frontend/src/ts/adaptive/geometry.ts
@@ -0,0 +1,161 @@
+// Keyboard geometry (which finger / hand / row types a character) and the
+// motion classes of key pairs. Syllable splitting lives here too: both are
+// "structure of the text" helpers shared by the analyzer and the generator.
+
+export type KeyInfo = {
+  row: number; // 0 = number row ... 3 = bottom row, 4 = space
+  col: number;
+  finger: number; // 0..3 left pinky..index, 4..7 right index..pinky, 8 thumb
+  shifted: boolean;
+};
+
+export type Geometry = {
+  name: string;
+  keys: Map<string, KeyInfo>;
+  rows: string[][]; // unshifted chars per row, for the heatmap
+};
+
+type LayoutLike = {
+  type?: string;
+  keys: Record<string, string[][]>;
+};
+
+const fingerByCol = [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7, 7];
+// number row is shifted one to the left relative to the letter rows
+const fingerByColRow0 = [0, 0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7];
+
+export const fingerNames = [
+  "left pinky",
+  "left ring",
+  "left middle",
+  "left index",
+  "right index",
+  "right middle",
+  "right ring",
+  "right pinky",
+  "thumb",
+];
+
+export function buildGeometry(name: string, layout: LayoutLike): Geometry {
+  const keys = new Map<string, KeyInfo>();
+  const rows: string[][] = [];
+  const rowNames = ["row1", "row2", "row3", "row4"];
+  rowNames.forEach((rowName, row) => {
+    const defs = layout.keys[rowName] ?? [];
+    // iso boards have an extra key left of the bottom row
+    const offset = row === 3 && layout.type === "iso" ? -1 : 0;
+    const chars: string[] = [];
+    defs.forEach((pair, i) => {
+      const col = Math.max(0, i + offset);
+      const table = row === 0 ? fingerByColRow0 : fingerByCol;
+      const finger = table[Math.min(col, table.length - 1)] as number;
+      pair.forEach((ch, idx) => {
+        if (ch === undefined || ch === "" || keys.has(ch)) return;
+        keys.set(ch, { row, col, finger, shifted: idx === 1 });
+      });
+      chars.push(pair[0] ?? "");
+    });
+    rows.push(chars);
+  });
+  keys.set(" ", { row: 4, col: 5, finger: 8, shifted: false });
+  return { name, keys, rows };
+}
+
+const qwertyRows: [string, string][] = [
+  ["`1234567890-=", "~!@#$%^&*()_+"],
+  ["qwertyuiop[]\\", "QWERTYUIOP{}|"],
+  ["asdfghjkl;'", 'ASDFGHJKL:"'],
+  ["zxcvbnm,./", "ZXCVBNM<>?"],
+];
+
+export const qwertyGeometry: Geometry = buildGeometry("qwerty", {
+  type: "ansi",
+  keys: Object.fromEntries(
+    qwertyRows.map(([lower, upper], i) => [
+      `row${i + 1}`,
+      lower.split("").map((ch, j) => [ch, upper[j] as string]),
+    ]),
+  ),
+});
+
+export type PairClass =
+  | "double"
+  | "sfb"
+  | "alt"
+  | "roll-in"
+  | "roll-out"
+  | "rowjump"
+  | "stretch";
+
+/** Motion classes of typing `b` right after `a`. */
+export function pairClasses(a: string, b: string, geo: Geometry): PairClass[] {
+  const ka = geo.keys.get(a);
+  const kb = geo.keys.get(b);
+  if (ka === undefined || kb === undefined) return [];
+  if (ka.finger === 8 || kb.finger === 8) return [];
+  const out: PairClass[] = [];
+  if (ka.row === kb.row && ka.col === kb.col) {
+    out.push("double");
+    return out;
+  }
+  const handA = ka.finger < 4 ? 0 : 1;
+  const handB = kb.finger < 4 ? 0 : 1;
+  if (handA !== handB) {
+    out.push("alt");
+    return out;
+  }
+  if (ka.finger === kb.finger) {
+    out.push("sfb");
+  } else {
+    // towards the index finger = inward roll
+    const inward = handA === 0 ? kb.finger > ka.finger : kb.finger < ka.finger;
+    out.push(inward ? "roll-in" : "roll-out");
+  }
+  if (Math.abs(ka.row - kb.row) >= 2) out.push("rowjump");
+  // index finger inner column reach
+  if ((ka.col === 4 || ka.col === 5) !== (kb.col === 4 || kb.col === 5)) {
+    if (ka.finger === kb.finger) out.push("stretch");
+  }
+  return out;
+}
+
+export function isAdjacent(a: string, b: string, geo: Geometry): boolean {
+  const ka = geo.keys.get(a.toLowerCase());
+  const kb = geo.keys.get(b.toLowerCase());
+  if (ka === undefined || kb === undefined) return false;
+  if (ka.row === kb.row && ka.col === kb.col) return false;
+  return Math.abs(ka.row - kb.row) <= 1 && Math.abs(ka.col - kb.col) <= 1;
+}
+
+export function isMirror(a: string, b: string, geo: Geometry): boolean {
+  const ka = geo.keys.get(a.toLowerCase());
+  const kb = geo.keys.get(b.toLowerCase());
+  if (ka === undefined || kb === undefined) return false;
+  return ka.row === kb.row && ka.finger + kb.finger === 7 && ka.finger !== 8;
+}
+
+const vowels = "aeiouyäöüáéíóúàèìòùâêîôûãõåæøœ";
+const syllableRe = new RegExp(
+  `[^${vowels}]*[${vowels}]+(?:[^${vowels}]*$|[^${vowels}](?=[^${vowels}]))?`,
+  "gi",
+);
+const letterRe = /^\p{L}+$/u;
+
+/**
+ * Heuristic syllable split for alphabetic scripts (onset + vowel group +
+ * optional coda). Returns [start, end) spans. Words without vowels, or in
+ * scripts the heuristic does not understand, come back as one span.
+ */
+export function syllableSpans(word: string): [number, number][] {
+  if (word.length < 2 || !letterRe.test(word)) return [];
+  const spans: [number, number][] = [];
+  let covered = 0;
+  for (const m of word.matchAll(syllableRe)) {
+    const start = m.index;
+    if (start !== covered) return [[0, word.length]];
+    covered = start + m[0].length;
+    spans.push([start, covered]);
+  }
+  if (covered !== word.length || spans.length === 0) return [[0, word.length]];
+  return spans;
+}
diff --git a/frontend/src/ts/adaptive/insights.ts b/frontend/src/ts/adaptive/insights.ts
new file mode 100644
index 0000000..b739ebc
--- /dev/null
+++ b/frontend/src/ts/adaptive/insights.ts
@@ -0,0 +1,247 @@
+// Plain-language findings derived from the profile, for the overview tab.
+
+import { patternLabel } from "./generate";
+import { errorTypes, ErrorType, Profile, Scored } from "./model";
+
+export type Insight = {
+  icon: string;
+  title: string;
+  text: string;
+  /** which focus preset addresses it, if any */
+  preset?: string;
+};
+
+export const errorTypeInfo: Record<ErrorType, { label: string; help: string }> =
+  {
+    substitution: {
+      label: "substitution",
+      help: "A different, unrelated key was pressed.",
+    },
+    adjacent: {
+      label: "adjacent key",
+      help: "The key next to the right one: finger placement drift.",
+    },
+    mirror: {
+      label: "mirror",
+      help: "The same finger on the other hand: hand confusion.",
+    },
+    case: {
+      label: "capitalization",
+      help: "Right letter, wrong case: shift timing.",
+    },
+    omission: { label: "omission", help: "A letter was skipped." },
+    insertion: { label: "insertion", help: "An extra letter was typed." },
+    doubling: { label: "doubling", help: "The previous letter was repeated." },
+    transposition: {
+      label: "transposition",
+      help: "Two letters in swapped order: hands out of sync.",
+    },
+    "early-space": {
+      label: "early space",
+      help: "Space pressed before the word was finished.",
+    },
+    "missed-space": {
+      label: "missed space",
+      help: "Next word started without pressing space.",
+    },
+    other: { label: "other", help: "Unclassified." },
+  };
+
+export function errorBreakdown(
+  profile: Profile,
+): { type: ErrorType; count: number; share: number }[] {
+  const total = errorTypes.reduce(
+    (sum, t) => sum + (profile.errTypes[t] ?? 0),
+    0,
+  );
+  return errorTypes
+    .map((type) => {
+      const count = profile.errTypes[type] ?? 0;
+      return { type, count, share: total > 0 ? count / total : 0 };
+    })
+    .filter((x) => x.count > 0)
+    .sort((a, b) => b.count - a.count);
+}
+
+/** Share of typing time that the measured weaknesses cost, at bigram level. */
+export function potentialGain(scored: Scored[]): number {
+  let lost = 0;
+  let spent = 0;
+  for (const s of scored) {
+    if (s.type !== "b" || s.level === "new") continue;
+    lost += Math.max(0, s.lostMs) * s.samples;
+    spent += s.ms * s.samples;
+  }
+  return spent > 0 ? Math.min(0.6, lost / spent) : 0;
+}
+
+function recent<T>(arr: T[], n: number): T[] {
+  return arr.slice(Math.max(0, arr.length - n));
+}
+
+function avg(values: number[]): number {
+  return values.length === 0
+    ? 0
+    : values.reduce((a, b) => a + b, 0) / values.length;
+}
+
+export function buildInsights(profile: Profile, scored: Scored[]): Insight[] {
+  const out: Insight[] = [];
+  if (profile.g.tests === 0) return out;
+  const sessions = recent(profile.sessions, 20);
+  const usable = scored.filter((s) => s.level !== "new");
+
+  // speed vs accuracy trade-off
+  const acc = avg(sessions.map((s) => s.acc));
+  const errCost = profile.g.errCost;
+  const med = profile.g.medianDt;
+  if (errCost > 0 && med > 0) {
+    const errRate = 1 - acc / 100;
+    const share = (errRate * errCost) / (med + errRate * errCost);
+    if (share > 0.12) {
+      out.push({
+        icon: "fa-tachometer-alt",
+        title: "errors are your biggest time sink",
+        text: `Each error costs you about ${Math.round(errCost)} ms (${(errCost / med).toFixed(1)} keystrokes). At ${acc.toFixed(1)}% accuracy that is roughly ${Math.round(share * 100)}% of your typing time. Slowing down slightly would make you faster overall.`,
+        preset: "accuracy",
+      });
+    } else if (acc > 98.5 && sessions.length >= 5) {
+      out.push({
+        icon: "fa-rocket",
+        title: "room to push speed",
+        text: `Accuracy is ${acc.toFixed(1)}% and errors cost little (${Math.round(share * 100)}% of your time). You can afford to type more aggressively.`,
+        preset: "speed",
+      });
+    }
+  }
+
+  // weakest finger
+  const fingers = usable
+    .filter((s) => s.id.startsWith("c:finger-") && s.id !== "c:finger-8")
+    .sort((a, b) => b.weakness - a.weakness);
+  const worstFinger = fingers[0];
+  if (worstFinger !== undefined && worstFinger.weakness > 0.12) {
+    out.push({
+      icon: "fa-hand-paper",
+      title: `weakest finger: ${patternLabel(worstFinger.text)}`,
+      text: `${(worstFinger.errorRate * 100).toFixed(1)}% errors and ${Math.abs(Math.round((worstFinger.relLatency - 1) * 100))}% ${worstFinger.relLatency >= 1 ? "slower" : "faster"} than your average finger.`,
+      preset: "fingers",
+    });
+  }
+
+  // motion patterns
+  const patterns = usable
+    .filter(
+      (s) =>
+        s.type === "c" &&
+        [
+          "sfb",
+          "double",
+          "rowjump",
+          "roll-in",
+          "roll-out",
+          "alt",
+          "stretch",
+        ].includes(s.text),
+    )
+    .sort((a, b) => b.weakness - a.weakness);
+  const worstPattern = patterns[0];
+  if (worstPattern !== undefined && worstPattern.weakness > 0.15) {
+    out.push({
+      icon: "fa-exchange-alt",
+      title: `hard motion: ${patternLabel(worstPattern.text)}`,
+      text: `These take ${Math.round(worstPattern.ms)} ms on average, ${Math.abs(Math.round((worstPattern.relLatency - 1) * 100))}% ${worstPattern.relLatency >= 1 ? "above" : "below"} your norm, with ${(worstPattern.errorRate * 100).toFixed(1)}% errors.`,
+      preset: "fingers",
+    });
+  }
+
+  // dominant error type
+  const breakdown = errorBreakdown(profile);
+  const top = breakdown[0];
+  if (top !== undefined && top.share > 0.3 && top.count >= 8) {
+    const info = errorTypeInfo[top.type];
+    out.push({
+      icon: "fa-bug",
+      title: `most common mistake: ${info.label}`,
+      text: `${Math.round(top.share * 100)}% of your errors. ${info.help}`,
+      preset:
+        top.type === "substitution" || top.type === "adjacent"
+          ? "confusions"
+          : "accuracy",
+    });
+  }
+
+  // confusion pair
+  const pair = Object.entries(profile.conf).sort((a, b) => b[1] - a[1])[0];
+  if (pair !== undefined && pair[1] >= 4) {
+    const [exp, typed] = pair[0].split(">") as [string, string];
+    out.push({
+      icon: "fa-random",
+      title: `you type "${typed}" for "${exp}"`,
+      text: "Your most frequent letter confusion. The confusions preset mixes both letters into the same words.",
+      preset: "confusions",
+    });
+  }
+
+  // word starts
+  const start = usable.find((s) => s.id === "c:word-start");
+  if (start !== undefined && start.relLatency > 1.35) {
+    out.push({
+      icon: "fa-step-forward",
+      title: "you pause between words",
+      text: `The first letter of a word takes ${Math.round((start.relLatency - 1) * 100)}% longer than other keys. Reading one word ahead removes that stall.`,
+    });
+  }
+
+  // fatigue
+  const fatigue = avg(sessions.map((s) => s.fatigue));
+  if (sessions.length >= 5 && fatigue > 1.06) {
+    out.push({
+      icon: "fa-battery-quarter",
+      title: "you slow down during tests",
+      text: `The last third of your tests is ${Math.round((fatigue - 1) * 100)}% slower than the first. Longer tests build the stamina to hold your pace.`,
+    });
+  }
+
+  // post error slowdown
+  const post = avg(sessions.map((s) => s.postError));
+  if (sessions.length >= 5 && post > 1.25) {
+    out.push({
+      icon: "fa-undo",
+      title: "errors throw you off rhythm",
+      text: `After correcting a mistake your next keystrokes are ${Math.round((post - 1) * 100)}% slower than normal.`,
+      preset: "consistency",
+    });
+  }
+
+  // long vs short words
+  const long = usable.find((s) => s.id === "c:len-long");
+  const short = usable.find((s) => s.id === "c:len-short");
+  if (
+    long !== undefined &&
+    short !== undefined &&
+    long.errorRate > short.errorRate * 2.5
+  ) {
+    out.push({
+      icon: "fa-text-width",
+      title: "long words break down",
+      text: `You make an error in ${(long.errorRate * 100).toFixed(0)}% of 7-9 letter words versus ${(short.errorRate * 100).toFixed(0)}% of short ones.`,
+      preset: "syllables",
+    });
+  }
+
+  // review backlog
+  const due = usable.filter(
+    (s) => s.type !== "c" && s.components.forgetting > 0.3,
+  );
+  if (due.length >= 5) {
+    out.push({
+      icon: "fa-history",
+      title: `${due.length} past weaknesses are due for review`,
+      text: "They improved earlier but have not come up for a while.",
+      preset: "review",
+    });
+  }
+
+  return out;
+}
diff --git a/frontend/src/ts/adaptive/model.ts b/frontend/src/ts/adaptive/model.ts
new file mode 100644
index 0000000..41c4d0b
--- /dev/null
+++ b/frontend/src/ts/adaptive/model.ts
@@ -0,0 +1,589 @@
+// The statistical model: per-unit statistics, how observations update them,
+// and how a unit's weakness is scored.
+//
+// A "unit" is anything we keep statistics for. Its id carries the level:
+//   k:<char>      single key
+//   b:<2 chars>   bigram          t:<3 chars>  trigram
+//   s:<chunk>     syllable        w:<word>     whole word
+//   c:<name>      category (finger, motion pattern, capitals, word length...)
+
+import {
+  AdaptiveSettings,
+  ComponentWeights,
+  effectiveWeights,
+  TypeWeights,
+} from "./settings";
+
+export type Stat = {
+  /** decayed number of accuracy samples */
+  n: number;
+  /** decayed number of errors */
+  e: number;
+  /** lifetime samples */
+  c: number;
+  /** decayed number of timing samples */
+  tn: number;
+  /** decayed mean ms per keystroke */
+  tm: number;
+  /** decayed variance of ms */
+  tv: number;
+  /** decayed mean latency relative to the test's median keystroke */
+  rm: number;
+  /** decayed hesitation count */
+  h: number;
+  /** fast / slow moving average of errors, for the trend */
+  ef: number;
+  es: number;
+  /** fast / slow moving average of relative latency */
+  rf: number;
+  rs: number;
+  /** memory stability in days (spaced repetition) */
+  st: number;
+  /** last seen (ms epoch) */
+  ls: number;
+  /** peak weakness seen, slowly decaying: what "forgetting" brings back */
+  pk: number;
+};
+
+export type SessionSummary = {
+  t: number;
+  wpm: number;
+  acc: number;
+  chars: number;
+  mode: string;
+  adaptive: boolean;
+  /** frequency weighted mean weakness after this session, 0..100 */
+  wi: number;
+  medianDt: number;
+  errCost: number;
+  fatigue: number;
+  postError: number;
+  consistency: number;
+  intensity?: number;
+};
+
+export const errorTypes = [
+  "substitution",
+  "adjacent",
+  "mirror",
+  "case",
+  "omission",
+  "insertion",
+  "doubling",
+  "transposition",
+  "early-space",
+  "missed-space",
+  "other",
+] as const;
+export type ErrorType = (typeof errorTypes)[number];
+
+export type Profile = {
+  v: 1;
+  created: number;
+  units: Record<string, Stat>;
+  /** substitution pairs "expected>typed" -> decayed count */
+  conf: Record<string, number>;
+  errTypes: Partial<Record<ErrorType, number>>;
+  sessions: SessionSummary[];
+  /** running estimates about the typist as a whole */
+  g: {
+    tests: number;
+    chars: number;
+    medianDt: number;
+    errCost: number;
+    wpm: number;
+    intensity: number;
+  };
+};
+
+export function newProfile(now: number, intensity = 0.6): Profile {
+  return {
+    v: 1,
+    created: now,
+    units: {},
+    conf: {},
+    errTypes: {},
+    sessions: [],
+    g: { tests: 0, chars: 0, medianDt: 0, errCost: 0, wpm: 0, intensity },
+  };
+}
+
+export function newStat(now: number, stability: number): Stat {
+  return {
+    n: 0,
+    e: 0,
+    c: 0,
+    tn: 0,
+    tm: 0,
+    tv: 0,
+    rm: 1,
+    h: 0,
+    ef: 0,
+    es: 0,
+    rf: 1,
+    rs: 1,
+    st: stability,
+    ls: now,
+    pk: 0,
+  };
+}
+
+export function observeAccuracy(
+  s: Stat,
+  err: 0 | 1,
+  cfg: AdaptiveSettings,
+  now: number,
+): void {
+  const lam = Math.pow(0.5, 1 / cfg.halfLife);
+  s.n = s.n * lam + 1;
+  s.e = s.e * lam + err;
+  if (s.c === 0) {
+    s.ef = err;
+    s.es = err;
+  } else {
+    s.ef += (2 / (cfg.trendFast + 1)) * (err - s.ef);
+    s.es += (2 / (cfg.trendSlow + 1)) * (err - s.es);
+  }
+  s.c++;
+  s.ls = now;
+}
+
+export function observeTime(
+  s: Stat,
+  ms: number,
+  rel: number,
+  hesitated: boolean,
+  cfg: AdaptiveSettings,
+): void {
+  const lam = Math.pow(0.5, 1 / cfg.halfLife);
+  const first = s.tn === 0;
+  s.tn = s.tn * lam + 1;
+  s.h = s.h * lam + (hesitated ? 1 : 0);
+  const a = 1 / s.tn;
+  if (first) {
+    s.tm = ms;
+    s.tv = 0;
+    s.rm = rel;
+    s.rf = rel;
+    s.rs = rel;
+    return;
+  }
+  const d = ms - s.tm;
+  s.tm += a * d;
+  s.tv = (1 - a) * (s.tv + a * d * d);
+  s.rm += a * (rel - s.rm);
+  s.rf += (2 / (cfg.trendFast + 1)) * (rel - s.rf);
+  s.rs += (2 / (cfg.trendSlow + 1)) * (rel - s.rs);
+}
+
+// ---------------------------------------------------------------- scoring
+
+export type UnitType = "k" | "b" | "t" | "s" | "w" | "c";
+export const unitTypes: UnitType[] = ["k", "b", "t", "s", "w", "c"];
+export const typeLabels: Record<UnitType, string> = {
+  k: "key",
+  b: "bigram",
+  t: "trigram",
+  s: "syllable",
+  w: "word",
+  c: "pattern",
+};
+const typeWeightKey: Record<UnitType, keyof TypeWeights> = {
+  k: "key",
+  b: "bigram",
+  t: "trigram",
+  s: "syllable",
+  w: "word",
+  c: "category",
+};
+
+export function typeOf(id: string): UnitType {
+  return id[0] as UnitType;
+}
+export function textOf(id: string): string {
+  return id.slice(2);
+}
+
+export type Baseline = {
+  /** mean error rate */
+  p: number;
+  /** mean relative latency */
+  r: number;
+  /** mean ms */
+  ms: number;
+  /** mean coefficient of variation */
+  cv: number;
+  /** mean hesitation rate */
+  h: number;
+  /** total lifetime samples and the largest single unit */
+  total: number;
+  maxC: number;
+};
+
+type Accumulator = {
+  n: number;
+  e: number;
+  tn: number;
+  r: number;
+  ms: number;
+  cv: number;
+  h: number;
+  total: number;
+  maxC: number;
+};
+
+/**
+ * N-grams that begin with the space carry the pause between words, so they
+ * are compared with each other, not with n-grams inside words.
+ */
+export function baselineKey(id: string): string {
+  const t = id[0] as string;
+  return (t === "b" || t === "t") && id[2] === " " ? `${t}_` : t;
+}
+const baselineKeys = [...unitTypes, "b_", "t_"];
+
+export type Baselines = Record<string, Baseline>;
+
+export function baselines(profile: Profile): Baselines {
+  const acc = new Map<string, Accumulator>();
+  for (const t of baselineKeys) {
+    acc.set(t, {
+      n: 0,
+      e: 0,
+      tn: 0,
+      r: 0,
+      ms: 0,
+      cv: 0,
+      h: 0,
+      total: 0,
+      maxC: 1,
+    });
+  }
+  for (const id in profile.units) {
+    const s = profile.units[id] as Stat;
+    const a = acc.get(baselineKey(id));
+    if (a === undefined) continue;
+    a.n += s.n;
+    a.e += s.e;
+    a.total += s.c;
+    if (s.c > a.maxC) a.maxC = s.c;
+    if (s.tn > 0 && s.tm > 0) {
+      a.tn += s.tn;
+      a.r += s.tn * s.rm;
+      a.ms += s.tn * s.tm;
+      a.cv += (s.tn * Math.sqrt(s.tv)) / s.tm;
+      a.h += s.h;
+    }
+  }
+  const out: Baselines = {};
+  for (const t of baselineKeys) {
+    const a = acc.get(t) as Accumulator;
+    out[t] = {
+      p: a.n > 0 ? Math.max(0.002, a.e / a.n) : 0.05,
+      r: a.tn > 0 ? a.r / a.tn : 1,
+      ms: a.tn > 0 ? a.ms / a.tn : 150,
+      cv: a.tn > 0 ? Math.max(0.05, a.cv / a.tn) : 0.4,
+      h: a.tn > 0 ? Math.max(0.005, a.h / a.tn) : 0.03,
+      total: a.total,
+      maxC: a.maxC,
+    };
+  }
+  return out;
+}
+
+/** 0 for x <= 0, rising towards 1; reaches 0.5 at x = half. */
+function sat(x: number, half: number): number {
+  return x <= 0 ? 0 : x / (x + half);
+}
+
+export type Level = "new" | "critical" | "weak" | "fair" | "good" | "mastered";
+
+export type Scored = {
+  id: string;
+  type: UnitType;
+  text: string;
+  /** final selection score (weights, frequency and exploration applied) */
+  score: number;
+  /** weakness alone, 0..1, comparable across units */
+  weakness: number;
+  level: Level;
+  components: {
+    accuracy: number;
+    speed: number;
+    consistency: number;
+    hesitation: number;
+    trend: number;
+    forgetting: number;
+    exploration: number;
+    impact: number;
+  };
+  /** shrunk estimates, for display */
+  errorRate: number;
+  ms: number;
+  relLatency: number;
+  /** estimated ms lost per occurrence */
+  lostMs: number;
+  samples: number;
+  confidence: number;
+  /** negative = improving, positive = getting worse */
+  trend: number;
+  recall: number;
+  stat: Stat;
+};
+
+export type Rng = () => number;
+
+function gaussian(rng: Rng): number {
+  let u = 0;
+  while (u === 0) u = rng();
+  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * rng());
+}
+
+// Marsaglia-Tsang
+function gamma(shape: number, rng: Rng): number {
+  if (shape < 1) {
+    return gamma(shape + 1, rng) * Math.pow(Math.max(rng(), 1e-12), 1 / shape);
+  }
+  const d = shape - 1 / 3;
+  const c = 1 / Math.sqrt(9 * d);
+  for (;;) {
+    let x = 0;
+    let v = 0;
+    do {
+      x = gaussian(rng);
+      v = 1 + c * x;
+    } while (v <= 0);
+    v = v * v * v;
+    const u = rng();
+    if (u < 1 - 0.0331 * x * x * x * x) return d * v;
+    if (Math.log(u) < 0.5 * x * x + d * (1 - v + Math.log(v))) return d * v;
+  }
+}
+
+export function sampleBeta(a: number, b: number, rng: Rng): number {
+  const x = gamma(Math.max(a, 1e-3), rng);
+  const y = gamma(Math.max(b, 1e-3), rng);
+  return x + y === 0 ? 0.5 : x / (x + y);
+}
+
+export type ScoreOptions = {
+  now: number;
+  /** how estimates are drawn: point estimate, posterior sample or optimistic bound */
+  draw?: "mean" | "thompson" | "ucb";
+  rng?: Rng;
+  weights?: ComponentWeights;
+  typeWeights?: TypeWeights;
+};
+
+const dayMs = 86400000;
+
+export function scoreUnit(
+  id: string,
+  s: Stat,
+  base: Baseline,
+  profile: Profile,
+  cfg: AdaptiveSettings,
+  opts: ScoreOptions,
+): Scored {
+  const type = typeOf(id);
+  const eff =
+    opts.weights !== undefined && opts.typeWeights !== undefined
+      ? { weights: opts.weights, typeWeights: opts.typeWeights }
+      : effectiveWeights(cfg);
+  const w = eff.weights;
+  const k = cfg.priorStrength;
+  const rng = opts.rng ?? Math.random;
+  const draw = opts.draw ?? "mean";
+
+  // --- accuracy: beta posterior around the typist's own average for this level
+  const alpha = s.e + k * base.p;
+  const beta = Math.max(1e-3, s.n - s.e) + k * (1 - base.p);
+  let p = alpha / (alpha + beta);
+  const pMean = p;
+  if (draw === "thompson") p = sampleBeta(alpha, beta, rng);
+  else if (draw === "ucb") p += Math.sqrt((p * (1 - p)) / (alpha + beta + 1));
+
+  // --- speed: relative latency shrunk towards the level average
+  const hasTime = s.tn > 0 && s.tm > 0;
+  const tn = hasTime ? s.tn : 0;
+  let r = (tn * s.rm + k * base.r) / (tn + k || 1);
+  const rMean = r;
+  const cvUnit = hasTime ? Math.sqrt(s.tv) / s.tm : base.cv;
+  const rSe = (Math.max(cvUnit, base.cv) * r) / Math.sqrt(tn + k + 1);
+  if (draw === "thompson") r += gaussian(rng) * rSe;
+  else if (draw === "ucb") r += rSe;
+  const ms = (tn * s.tm + k * base.ms) / (tn + k || 1);
+
+  const conf = s.n / (s.n + cfg.minSamples);
+  const tconf = tn / (tn + cfg.minSamples);
+
+  const accuracy = sat(p / base.p - 1, 1.5);
+  const speed = sat(r / base.r - 1, 0.35);
+  const consistency = tconf * sat(cvUnit / base.cv - 1, 0.8);
+  const hRate = (s.h + k * base.h) / (tn + k || 1);
+  const hesitation = sat(hRate / base.h - 1, 2);
+  const errTrend = s.ef - s.es;
+  const spdTrend = s.rs > 0 ? (s.rf - s.rs) / s.rs : 0;
+  const trendRaw = errTrend * 4 + spdTrend * 2;
+  const trend = conf * Math.min(1, Math.max(0, trendRaw));
+  const days = Math.max(0, (opts.now - s.ls) / dayMs);
+  const recall = Math.pow(2, -days / Math.max(0.05, s.st));
+  const forgetting = (1 - recall) * s.pk;
+  const exploration = Math.min(
+    1,
+    Math.sqrt((2 * Math.log(base.total + 2)) / (s.c + 1)) / 3,
+  );
+
+  // --- impact: estimated ms lost every time this unit comes up
+  const errCost = profile.g.errCost > 0 ? profile.g.errCost : base.ms * 4;
+  const lostDraw = Math.max(0, (r / base.r - 1) * base.ms) + p * errCost;
+  const lostBase = base.p * errCost;
+  const impact = sat(lostDraw / Math.max(1, lostBase) - 1, 2);
+  const lostMs =
+    Math.max(0, (rMean / base.r - 1) * base.ms) + pMean * errCost - lostBase;
+
+  // A unit that is terrible on one dimension is a real weakness even when it
+  // is fine on the others, so the strongest component dominates and the
+  // weighted mean only nudges.
+  const blend = (parts: [number, number][]): number => {
+    let wMax = 0;
+    let wSum = 0;
+    for (const [weight] of parts) {
+      wMax = Math.max(wMax, weight);
+      wSum += weight;
+    }
+    if (wMax <= 0) return 0;
+    let peak = 0;
+    let sum = 0;
+    for (const [weight, value] of parts) {
+      peak = Math.max(peak, (weight / wMax) * value);
+      sum += weight * value;
+    }
+    return 0.65 * peak + 0.35 * (sum / wSum);
+  };
+  const shared: [number, number][] = [
+    [w.consistency, consistency],
+    [w.hesitation, hesitation],
+    [w.trend, trend],
+    [w.forgetting, forgetting],
+  ];
+  const composite = blend([
+    [w.accuracy, accuracy],
+    [w.speed, speed],
+    ...shared,
+  ]);
+  // impact folds accuracy and speed into one "time lost" figure
+  const impactMix = blend([[Math.max(w.accuracy, w.speed), impact], ...shared]);
+  const model =
+    cfg.scoringModel === "composite"
+      ? composite
+      : cfg.scoringModel === "impact"
+        ? impactMix
+        : (composite + impactMix) / 2;
+
+  const freq = Math.pow(
+    Math.min(1, (s.c + 1) / (base.maxC + 1)),
+    cfg.frequencyBias * 0.5,
+  );
+  const tw = eff.typeWeights[typeWeightKey[type]];
+  const score = tw * (model * freq + w.exploration * exploration * 0.5);
+
+  // level from point estimates only, so it does not flicker with sampling
+  const wk = s.c < cfg.minSamples ? 0 : model;
+  const level: Level =
+    s.c < cfg.minSamples
+      ? "new"
+      : wk >= 0.45
+        ? "critical"
+        : wk >= 0.28
+          ? "weak"
+          : wk >= 0.14
+            ? "fair"
+            : wk >= 0.05
+              ? "good"
+              : "mastered";
+
+  return {
+    id,
+    type,
+    text: textOf(id),
+    score,
+    weakness: model,
+    level,
+    components: {
+      accuracy,
+      speed,
+      consistency,
+      hesitation,
+      trend,
+      forgetting,
+      exploration,
+      impact,
+    },
+    errorRate: pMean,
+    ms,
+    relLatency: rMean / base.r,
+    lostMs,
+    samples: s.c,
+    confidence: Math.max(conf, tconf),
+    trend: trendRaw,
+    recall,
+    stat: s,
+  };
+}
+
+export function scoreAll(
+  profile: Profile,
+  cfg: AdaptiveSettings,
+  opts: ScoreOptions,
+): Scored[] {
+  const base = baselines(profile);
+  const out: Scored[] = [];
+  for (const id in profile.units) {
+    const b = base[baselineKey(id)];
+    if (b === undefined) continue;
+    out.push(scoreUnit(id, profile.units[id] as Stat, b, profile, cfg, opts));
+  }
+  return out;
+}
+
+/** Frequency weighted mean weakness of the whole profile, 0..100. Lower is better. */
+export function weaknessIndex(scored: Scored[]): number {
+  let num = 0;
+  let den = 0;
+  for (const s of scored) {
+    if (s.type === "c" || s.level === "new") continue;
+    num += s.weakness * s.samples;
+    den += s.samples;
+  }
+  return den > 0 ? (100 * num) / den : 0;
+}
+
+/** Drop the least valuable units when the profile grows past the limit. */
+export function prune(profile: Profile, max: number, now: number): void {
+  const ids = Object.keys(profile.units);
+  if (ids.length <= max) return;
+  const value = (id: string): number => {
+    const s = profile.units[id] as Stat;
+    if (typeOf(id) === "k" || typeOf(id) === "c") return Infinity;
+    const ageDays = (now - s.ls) / dayMs;
+    return s.c / (1 + ageDays / 30) + s.pk * 20;
+  };
+  ids.sort((a, b) => value(a) - value(b));
+  // prune 10% below the limit so this does not run after every test
+  const remove = ids.length - Math.floor(max * 0.9);
+  for (let i = 0; i < remove; i++) {
+    // oxlint-disable-next-line typescript/no-dynamic-delete
+    delete profile.units[ids[i] as string];
+  }
+  const pairs = Object.keys(profile.conf);
+  if (pairs.length > 600) {
+    pairs.sort(
+      (a, b) => (profile.conf[a] as number) - (profile.conf[b] as number),
+    );
+    for (const key of pairs.slice(0, pairs.length - 400)) {
+      // oxlint-disable-next-line typescript/no-dynamic-delete
+      delete profile.conf[key];
+    }
+  }
+}
diff --git a/frontend/src/ts/adaptive/session.ts b/frontend/src/ts/adaptive/session.ts
new file mode 100644
index 0000000..2a58f63
--- /dev/null
+++ b/frontend/src/ts/adaptive/session.ts
@@ -0,0 +1,504 @@
+// Glue between the adaptive engine and monkeytype: storage, passive capture
+// of finished tests, starting / continuing / leaving training sessions and
+// passive blending. Must not import test-logic (it imports this module).
+
+import { createEffect, createRoot, createSignal, on } from "solid-js";
+import { CustomTextSettings } from "@monkeytype/schemas/results";
+import { Mode } from "@monkeytype/schemas/shared";
+
+import { setConfig } from "../config/setters";
+import { Config } from "../config/store";
+import { configEvent } from "../events/config";
+import { setCustomTextIndicator } from "../states/core";
+import {
+  showErrorNotification,
+  showNoticeNotification,
+} from "../states/notifications";
+import { getLastEventLog, getLastResult } from "../states/test";
+import * as CustomText from "../test/custom-text";
+import { cachedFetchJson } from "../utils/json-data";
+import { extract, ingest } from "./analyze";
+import { generate, PassiveBlender, Plan, targetLabel } from "./generate";
+import { buildGeometry, Geometry, qwertyGeometry } from "./geometry";
+import { newProfile, Profile, typeOf } from "./model";
+import {
+  AdaptiveSettings,
+  defaultSettings,
+  presets,
+  sanitizeSettings,
+} from "./settings";
+
+const settingsKey = "adaptiveSettings";
+const profilePrefix = "adaptiveProfile:";
+
+// ------------------------------------------------------------ settings
+
+function loadSettings(): AdaptiveSettings {
+  try {
+    const raw = localStorage.getItem(settingsKey);
+    if (raw !== null) return sanitizeSettings(JSON.parse(raw));
+  } catch (e) {
+    console.error("adaptive: could not read settings", e);
+  }
+  return structuredClone(defaultSettings);
+}
+
+const [settings, setSettingsSignal] =
+  createSignal<AdaptiveSettings>(loadSettings());
+export { settings };
+
+export function updateSettings(next: AdaptiveSettings): void {
+  const clean = sanitizeSettings(next);
+  const scopeChanged = clean.profileScope !== settings().profileScope;
+  const layoutChanged = clean.layout !== settings().layout;
+  setSettingsSignal(clean);
+  try {
+    localStorage.setItem(settingsKey, JSON.stringify(clean));
+  } catch (e) {
+    console.error("adaptive: could not save settings", e);
+  }
+  if (scopeChanged) loadedProfileId = null;
+  if (layoutChanged) void loadGeometry();
+  bumpVersion();
+}
+
+export function resetSettings(): void {
+  updateSettings(structuredClone(defaultSettings));
+}
+
+// ------------------------------------------------------------ geometry
+
+let geometry: Geometry = qwertyGeometry;
+
+function layoutName(): string {
+  const wanted = settings().layout.trim().toLowerCase();
+  if (wanted !== "" && wanted !== "auto") return wanted;
+  return Config.layout === "default" ? "qwerty" : Config.layout;
+}
+
+async function loadGeometry(): Promise<void> {
+  const name = layoutName();
+  if (geometry.name === name) return;
+  try {
+    const layout = await cachedFetchJson<{
+      type?: string;
+      keys: Record<string, string[][]>;
+    }>(`/layouts/${name}.json`);
+    geometry = buildGeometry(name, layout);
+  } catch {
+    geometry = qwertyGeometry;
+  }
+  bumpVersion();
+}
+
+export function getGeometry(): Geometry {
+  return geometry;
+}
+
+// ------------------------------------------------------------ profile
+
+let profile: Profile = newProfile(Date.now());
+let loadedProfileId: string | null = null;
+
+/** Bumped whenever the profile or anything derived from it changes. */
+const [version, setVersion] = createSignal(0);
+export { version };
+function bumpVersion(): void {
+  setVersion((v) => v + 1);
+}
+
+export function profileId(): string {
+  const scope = settings().profileScope;
+  const parts: string[] = [];
+  if (scope.includes("language")) parts.push(Config.language);
+  if (scope.includes("layout")) parts.push(layoutName());
+  return parts.length === 0 ? "global" : parts.join("|");
+}
+
+function isProfile(value: unknown): value is Profile {
+  const p = value as Profile | null;
+  return (
+    typeof p === "object" &&
+    p?.v === 1 &&
+    typeof p.units === "object" &&
+    Array.isArray(p.sessions) &&
+    typeof p.g === "object"
+  );
+}
+
+export function getProfile(): Profile {
+  const id = profileId();
+  if (loadedProfileId !== id) {
+    loadedProfileId = id;
+    profile = newProfile(Date.now(), settings().intensity);
+    try {
+      const raw = localStorage.getItem(profilePrefix + id);
+      if (raw !== null) {
+        const parsed: unknown = JSON.parse(raw);
+        if (isProfile(parsed)) profile = parsed;
+      }
+    } catch (e) {
+      console.error("adaptive: could not read profile", e);
+    }
+  }
+  return profile;
+}
+
+function round(value: number): number {
+  return Math.round(value * 1000) / 1000;
+}
+
+function saveProfile(): void {
+  if (loadedProfileId === null) return;
+  try {
+    // 3 decimals is plenty and roughly halves the stored size
+    const json = JSON.stringify(profile, (_key, value: unknown) =>
+      typeof value === "number" ? round(value) : value,
+    );
+    localStorage.setItem(profilePrefix + loadedProfileId, json);
+  } catch (e) {
+    console.error("adaptive: could not save profile", e);
+    showErrorNotification(
+      "Adaptive trainer could not save its profile (storage full?). Lower 'max tracked units' in its settings.",
+    );
+  }
+}
+
+export function resetProfile(): void {
+  getProfile();
+  profile = newProfile(Date.now(), settings().intensity);
+  saveProfile();
+  bumpVersion();
+}
+
+export function exportData(): string {
+  return JSON.stringify(
+    { adaptiveExport: 1, settings: settings(), profile: getProfile() },
+    null,
+    1,
+  );
+}
+
+export function importData(json: string): boolean {
+  try {
+    const data = JSON.parse(json) as {
+      settings?: unknown;
+      profile?: unknown;
+    };
+    if (!isProfile(data.profile)) return false;
+    if (data.settings !== undefined) {
+      updateSettings(sanitizeSettings(data.settings));
+    }
+    getProfile();
+    profile = data.profile;
+    saveProfile();
+    bumpVersion();
+    return true;
+  } catch {
+    return false;
+  }
+}
+
+export function listProfiles(): string[] {
+  const out: string[] = [];
+  for (let i = 0; i < localStorage.length; i++) {
+    const key = localStorage.key(i);
+    if (key?.startsWith(profilePrefix)) {
+      out.push(key.slice(profilePrefix.length));
+    }
+  }
+  return out;
+}
+
+// ------------------------------------------------------------ word pool
+
+async function loadPool(): Promise<string[]> {
+  const wanted = settings().wordPool.trim().toLowerCase();
+  const name = wanted === "" || wanted === "test" ? Config.language : wanted;
+  try {
+    const lang = await cachedFetchJson<{ words: string[] }>(
+      `/languages/${name}.json`,
+    );
+    return lang.words;
+  } catch {
+    if (name !== Config.language) {
+      showNoticeNotification(
+        `Adaptive trainer: word pool "${name}" not found, using ${Config.language}.`,
+      );
+      const lang = await cachedFetchJson<{ words: string[] }>(
+        `/languages/${Config.language}.json`,
+      );
+      return lang.words;
+    }
+    throw new Error("could not load word pool");
+  }
+}
+
+// ------------------------------------------------------------ sessions
+
+type Before = {
+  mode: Mode;
+  punctuation: boolean;
+  numbers: boolean;
+  customText: CustomTextSettings;
+};
+
+let before: Before | null = null;
+let ownModeChange = false;
+let freshPlan = false;
+let lastPlanAnalyzed = true;
+
+const [activePlan, setActivePlan] = createSignal<Plan | null>(null);
+/** The plan of the running training session, null when not training. */
+export { activePlan };
+
+export function isTraining(): boolean {
+  return activePlan() !== null;
+}
+
+async function buildPlan(): Promise<Plan> {
+  const cfg = settings();
+  await loadGeometry();
+  const pool = await loadPool();
+  const p = getProfile();
+  let count = cfg.wordCount;
+  if (cfg.lengthMode === "time") {
+    // enough words that even a fast typist does not loop
+    const wpm = Math.max(60, p.g.wpm * 1.5);
+    count = Math.ceil((cfg.seconds / 60) * wpm) + 10;
+  }
+  return generate({
+    profile: p,
+    cfg,
+    pool,
+    geo: geometry,
+    now: Date.now(),
+    count,
+  });
+}
+
+function applyPlan(plan: Plan): void {
+  const cfg = settings();
+  CustomText.setPipeDelimiter(false);
+  CustomText.setText(plan.words);
+  CustomText.setMode("repeat");
+  if (cfg.lengthMode === "time") {
+    CustomText.setLimitMode("time");
+    CustomText.setLimitValue(cfg.seconds);
+  } else {
+    CustomText.setLimitMode("word");
+    CustomText.setLimitValue(plan.words.length);
+  }
+  setCustomTextIndicator({
+    name: `adaptive: ${presets[cfg.preset].label}`,
+    isLong: false,
+  });
+  setActivePlan(plan);
+  lastPlanAnalyzed = false;
+}
+
+/**
+ * Prepares a training test (custom text + mode). The caller restarts the
+ * test or navigates to the test page afterwards.
+ */
+export async function prepareTraining(): Promise<boolean> {
+  let plan: Plan;
+  try {
+    plan = await buildPlan();
+  } catch (e) {
+    console.error(e);
+    showErrorNotification("Adaptive trainer could not generate a test.");
+    return false;
+  }
+  if (plan.words.length === 0) {
+    showNoticeNotification(
+      "Adaptive trainer: no usable words in the pool (check the word length limits).",
+    );
+    return false;
+  }
+  before ??= {
+    mode: Config.mode,
+    punctuation: Config.punctuation,
+    numbers: Config.numbers,
+    customText: structuredClone(CustomText.getData()),
+  };
+  applyPlan(plan);
+  ownModeChange = true;
+  setConfig("mode", "custom", { nosave: true });
+  ownModeChange = false;
+  freshPlan = true;
+  if (!plan.informed) {
+    showNoticeNotification(
+      "Adaptive trainer has little data yet, so this test is mostly normal words. It sharpens as you type.",
+      { durationMs: 5000 },
+    );
+  }
+  return true;
+}
+
+function restoreBefore(restoreMode: boolean): void {
+  if (before === null) return;
+  const b = before;
+  before = null;
+  CustomText.setText(b.customText.text);
+  CustomText.setMode(b.customText.mode);
+  CustomText.setLimitMode(b.customText.limit.mode);
+  CustomText.setLimitValue(b.customText.limit.value);
+  CustomText.setPipeDelimiter(b.customText.pipeDelimiter);
+  setCustomTextIndicator(undefined);
+  if (!restoreMode) return;
+  ownModeChange = true;
+  setConfig("punctuation", b.punctuation);
+  setConfig("numbers", b.numbers);
+  setConfig("mode", b.mode);
+  ownModeChange = false;
+}
+
+/** Leave training and go back to the mode that was active before it. */
+export function endTraining(): void {
+  if (!isTraining()) return;
+  setActivePlan(null);
+  restoreBefore(true);
+}
+
+/**
+ * Called by restartTest before it resets the test. While training, a restart
+ * either builds the next adaptive test or returns to the previous mode.
+ */
+export async function beforeRestart(options: {
+  withSameWordset?: boolean;
+}): Promise<void> {
+  if (!isTraining()) return;
+  if (freshPlan) {
+    freshPlan = false;
+    return;
+  }
+  if (options.withSameWordset === true) return;
+  if (!settings().continuous) {
+    showNoticeNotification("Leaving adaptive training.");
+    endTraining();
+    return;
+  }
+  try {
+    const plan = await buildPlan();
+    if (plan.words.length > 0) applyPlan(plan);
+  } catch (e) {
+    console.error("adaptive: could not build next test", e);
+  }
+}
+
+// ------------------------------------------------------------ passive blend
+
+const blender = new PassiveBlender();
+
+/** Hook for the word generator in normal time / words tests. */
+export function blendWord(wordset: string[], candidate: string): string {
+  const cfg = settings();
+  if (cfg.passiveBlend <= 0 || !cfg.enabled) return candidate;
+  if (Config.mode !== "time" && Config.mode !== "words") return candidate;
+  if (Config.funbox.length > 0) return candidate;
+  return (
+    blender.pick(wordset, getProfile(), cfg, geometry, version(), Date.now()) ??
+    candidate
+  );
+}
+
+// ------------------------------------------------------------ capture
+
+function shouldAnalyze(
+  mode: string,
+  funbox: unknown,
+  training: boolean,
+): boolean {
+  const cfg = settings();
+  if (!cfg.enabled) return false;
+  if (training) return cfg.analyzeAdaptiveTests;
+  if (Array.isArray(funbox) && funbox.length > 0 && !cfg.analyzeFunboxTests) {
+    return false;
+  }
+  switch (mode) {
+    case "time":
+      return cfg.analyzeTime;
+    case "words":
+      return cfg.analyzeWords;
+    case "quote":
+      return cfg.analyzeQuote;
+    case "custom":
+      return cfg.analyzeCustom;
+    default:
+      return false;
+  }
+}
+
+function analyzeFinishedTest(): void {
+  const log = getLastEventLog();
+  const result = getLastResult();
+  if (log === null || result === null) return;
+  const training = isTraining() && !lastPlanAnalyzed;
+  if (!shouldAnalyze(log.context.mode, result.funbox, training)) return;
+  if (log.context.hasKorean) return;
+  const cfg = settings();
+  if (result.acc < cfg.minTestAccuracy) return;
+
+  const ex = extract(log, cfg, geometry);
+  if (ex.chars < cfg.minTestChars) return;
+
+  const p = getProfile();
+  const report = ingest(p, ex, cfg, Date.now(), {
+    wpm: result.wpm,
+    acc: result.acc,
+    mode: training ? "adaptive" : log.context.mode,
+    adaptive: training,
+    intensity: training ? activePlan()?.intensity : undefined,
+  });
+  if (training) lastPlanAnalyzed = true;
+  saveProfile();
+  bumpVersion();
+
+  if (cfg.notifyAfterTest && report.weakest.length > 0) {
+    const list = report.weakest
+      .slice(0, 4)
+      .map((u) => targetLabel({ type: typeOf(u.id), id: u.id }))
+      .join("  ");
+    showNoticeNotification(`Weak spots in this test: ${list}`, {
+      durationMs: 4000,
+      customTitle: "Adaptive trainer",
+    });
+  }
+}
+
+let initialized = false;
+
+/** Start listening for finished tests. Called once at boot. */
+export function initAdaptive(): void {
+  if (initialized) return;
+  initialized = true;
+  void loadGeometry();
+  createRoot(() => {
+    createEffect(
+      on(
+        getLastEventLog,
+        () => {
+          try {
+            analyzeFinishedTest();
+          } catch (e) {
+            console.error("adaptive: analysis failed", e);
+          }
+        },
+        { defer: true },
+      ),
+    );
+  });
+  configEvent.subscribe(({ key }) => {
+    if (key === "mode" && !ownModeChange && isTraining()) {
+      // the user picked another mode: training is over. Give them their own
+      // custom text back, but keep the mode they just chose
+      setActivePlan(null);
+      restoreBefore(false);
+    }
+    if (key === "layout") void loadGeometry();
+    if (key === "language" && settings().profileScope.includes("language")) {
+      bumpVersion();
+    }
+  });
+}
diff --git a/frontend/src/ts/adaptive/settings.ts b/frontend/src/ts/adaptive/settings.ts
new file mode 100644
index 0000000..0708420
--- /dev/null
+++ b/frontend/src/ts/adaptive/settings.ts
@@ -0,0 +1,998 @@
+// Adaptive trainer settings: defaults, presets and the schema the settings UI
+// is rendered from. Pure module (no DOM / Solid) so the engine stays testable.
+
+export type FocusPreset =
+  | "smart"
+  | "accuracy"
+  | "speed"
+  | "consistency"
+  | "keys"
+  | "bigrams"
+  | "trigrams"
+  | "syllables"
+  | "words"
+  | "fingers"
+  | "confusions"
+  | "review"
+  | "explore"
+  | "custom";
+
+export type ComponentWeights = {
+  accuracy: number;
+  speed: number;
+  consistency: number;
+  hesitation: number;
+  trend: number;
+  forgetting: number;
+  exploration: number;
+};
+
+export type TypeWeights = {
+  key: number;
+  bigram: number;
+  trigram: number;
+  syllable: number;
+  word: number;
+  category: number;
+};
+
+export type TriState = "off" | "auto" | "on";
+
+export type AdaptiveSettings = {
+  // --- passive analysis
+  enabled: boolean;
+  analyzeTime: boolean;
+  analyzeWords: boolean;
+  analyzeQuote: boolean;
+  analyzeCustom: boolean;
+  analyzeAdaptiveTests: boolean;
+  analyzeFunboxTests: boolean;
+  minTestChars: number;
+  minTestAccuracy: number;
+  maxPauseMs: number;
+  hesitationFactor: number;
+  notifyAfterTest: boolean;
+  // --- tracking
+  trackBigrams: boolean;
+  trackTrigrams: boolean;
+  trackSyllables: boolean;
+  trackWords: boolean;
+  trackSpaceNgrams: boolean;
+  profileScope: "global" | "language" | "layout" | "language+layout";
+  layout: string;
+  maxUnits: number;
+  maxSessions: number;
+  // --- model
+  halfLife: number;
+  priorStrength: number;
+  minSamples: number;
+  trendFast: number;
+  trendSlow: number;
+  initialStability: number;
+  stabilityGrowth: number;
+  stabilityShrink: number;
+  // --- scoring
+  scoringModel: "composite" | "impact" | "hybrid";
+  preset: FocusPreset;
+  weights: ComponentWeights;
+  typeWeights: TypeWeights;
+  frequencyBias: number;
+  // --- target selection
+  selection: "greedy" | "softmax" | "thompson" | "ucb";
+  temperature: number;
+  focusCount: number;
+  broadFactor: number;
+  // --- generation
+  structure: "interleaved" | "blocked" | "progressive";
+  blockSize: number;
+  lengthMode: "words" | "time";
+  wordCount: number;
+  seconds: number;
+  wordPool: string;
+  poolSize: number;
+  minWordLength: number;
+  maxWordLength: number;
+  repeatWindow: number;
+  pseudoWordRatio: number;
+  drillRatio: number;
+  confusionBonus: number;
+  capitalization: TriState;
+  capitalizationRate: number;
+  punctuation: TriState;
+  punctuationRate: number;
+  numbers: TriState;
+  numbersRate: number;
+  // --- difficulty
+  autoDifficulty: boolean;
+  intensity: number;
+  targetAccuracy: number;
+  difficultyGain: number;
+  minIntensity: number;
+  maxIntensity: number;
+  // --- session
+  continuous: boolean;
+  passiveBlend: number;
+};
+
+export const defaultSettings: AdaptiveSettings = {
+  enabled: true,
+  analyzeTime: true,
+  analyzeWords: true,
+  analyzeQuote: true,
+  analyzeCustom: true,
+  analyzeAdaptiveTests: true,
+  analyzeFunboxTests: false,
+  minTestChars: 40,
+  minTestAccuracy: 60,
+  maxPauseMs: 1500,
+  hesitationFactor: 2.5,
+  notifyAfterTest: false,
+  trackBigrams: true,
+  trackTrigrams: true,
+  trackSyllables: true,
+  trackWords: true,
+  trackSpaceNgrams: true,
+  profileScope: "global",
+  layout: "auto",
+  maxUnits: 12000,
+  maxSessions: 400,
+  halfLife: 60,
+  priorStrength: 8,
+  minSamples: 6,
+  trendFast: 8,
+  trendSlow: 40,
+  initialStability: 1,
+  stabilityGrowth: 2,
+  stabilityShrink: 0.5,
+  scoringModel: "hybrid",
+  preset: "smart",
+  weights: {
+    accuracy: 1,
+    speed: 1,
+    consistency: 0.4,
+    hesitation: 0.4,
+    trend: 0.3,
+    forgetting: 0.4,
+    exploration: 0.15,
+  },
+  typeWeights: {
+    key: 0.8,
+    bigram: 1,
+    trigram: 0.9,
+    syllable: 0.7,
+    word: 0.8,
+    category: 0.4,
+  },
+  frequencyBias: 0.3,
+  selection: "thompson",
+  temperature: 0.25,
+  focusCount: 8,
+  broadFactor: 0.35,
+  structure: "interleaved",
+  blockSize: 4,
+  lengthMode: "words",
+  wordCount: 50,
+  seconds: 60,
+  wordPool: "test",
+  poolSize: 5000,
+  minWordLength: 1,
+  maxWordLength: 20,
+  repeatWindow: 6,
+  pseudoWordRatio: 0.1,
+  drillRatio: 0,
+  confusionBonus: 0.5,
+  capitalization: "off",
+  capitalizationRate: 0.15,
+  punctuation: "off",
+  punctuationRate: 0.15,
+  numbers: "off",
+  numbersRate: 0.08,
+  autoDifficulty: true,
+  intensity: 0.6,
+  targetAccuracy: 95,
+  difficultyGain: 2,
+  minIntensity: 0.2,
+  maxIntensity: 0.95,
+  continuous: true,
+  passiveBlend: 0,
+};
+
+type PresetDef = {
+  label: string;
+  description: string;
+  weights?: Partial<ComponentWeights>;
+  typeWeights?: Partial<TypeWeights>;
+};
+
+const zeroTypes: TypeWeights = {
+  key: 0,
+  bigram: 0,
+  trigram: 0,
+  syllable: 0,
+  word: 0,
+  category: 0,
+};
+
+export const presets: Record<FocusPreset, PresetDef> = {
+  smart: {
+    label: "smart mix",
+    description: "Balanced: whatever currently costs you the most.",
+  },
+  accuracy: {
+    label: "accuracy",
+    description: "Sequences you mistype most often.",
+    weights: { accuracy: 1.6, speed: 0.2, hesitation: 0.2, consistency: 0.2 },
+  },
+  speed: {
+    label: "speed",
+    description: "Sequences you type correctly but slowly.",
+    weights: { accuracy: 0.2, speed: 1.6, hesitation: 0.6 },
+  },
+  consistency: {
+    label: "consistency",
+    description: "Sequences with erratic timing and hesitations.",
+    weights: { accuracy: 0.2, speed: 0.3, consistency: 1.5, hesitation: 1.2 },
+  },
+  keys: {
+    label: "keys",
+    description: "Individual weak keys.",
+    typeWeights: { ...zeroTypes, key: 1 },
+  },
+  bigrams: {
+    label: "bigrams",
+    description: "Weak two-letter transitions.",
+    typeWeights: { ...zeroTypes, bigram: 1 },
+  },
+  trigrams: {
+    label: "trigrams",
+    description: "Weak three-letter sequences.",
+    typeWeights: { ...zeroTypes, trigram: 1 },
+  },
+  syllables: {
+    label: "syllables",
+    description: "Weak syllables and letter chunks.",
+    typeWeights: { ...zeroTypes, syllable: 1 },
+  },
+  words: {
+    label: "words",
+    description: "Whole words you fumble or slow down on.",
+    typeWeights: { ...zeroTypes, word: 1 },
+  },
+  fingers: {
+    label: "fingers",
+    description: "Weak fingers and motion patterns (same-finger, rolls...).",
+    typeWeights: { ...zeroTypes, category: 1, bigram: 0.3 },
+  },
+  confusions: {
+    label: "confusions",
+    description: "Letters you substitute for each other.",
+    weights: { accuracy: 1.5, speed: 0.1 },
+    typeWeights: { ...zeroTypes, key: 1, bigram: 0.5 },
+  },
+  review: {
+    label: "review",
+    description: "Spaced repetition of past weaknesses that are due.",
+    weights: {
+      accuracy: 0.3,
+      speed: 0.3,
+      forgetting: 2,
+      consistency: 0,
+      hesitation: 0,
+      trend: 0,
+      exploration: 0,
+    },
+  },
+  explore: {
+    label: "explore",
+    description: "Sequences with too little data to judge yet.",
+    weights: {
+      accuracy: 0.2,
+      speed: 0.2,
+      exploration: 2,
+      consistency: 0,
+      hesitation: 0,
+      trend: 0,
+      forgetting: 0,
+    },
+  },
+  custom: {
+    label: "custom",
+    description: "Uses the weights from the settings tab as they are.",
+  },
+};
+
+export function effectiveWeights(s: AdaptiveSettings): {
+  weights: ComponentWeights;
+  typeWeights: TypeWeights;
+} {
+  const p = presets[s.preset];
+  if (s.preset === "custom" || s.preset === "smart") {
+    return { weights: s.weights, typeWeights: s.typeWeights };
+  }
+  return {
+    weights: { ...s.weights, ...p.weights },
+    typeWeights: { ...s.typeWeights, ...p.typeWeights },
+  };
+}
+
+// ---- settings UI schema
+
+export type SettingField =
+  | {
+      kind: "toggle";
+      path: string;
+      label: string;
+      help: string;
+    }
+  | {
+      kind: "number";
+      path: string;
+      label: string;
+      help: string;
+      min: number;
+      max: number;
+      step: number;
+      unit?: string;
+    }
+  | {
+      kind: "select";
+      path: string;
+      label: string;
+      help: string;
+      options: { value: string; label: string }[];
+    }
+  | {
+      kind: "text";
+      path: string;
+      label: string;
+      help: string;
+    };
+
+export type SettingGroup = {
+  title: string;
+  icon: string;
+  description: string;
+  fields: SettingField[];
+};
+
+const tri = [
+  { value: "off", label: "off" },
+  { value: "auto", label: "auto" },
+  { value: "on", label: "on" },
+];
+
+const t = (path: string, label: string, help: string): SettingField => ({
+  kind: "toggle",
+  path,
+  label,
+  help,
+});
+const n = (
+  path: string,
+  label: string,
+  help: string,
+  min: number,
+  max: number,
+  step: number,
+  unit?: string,
+): SettingField => ({
+  kind: "number",
+  path,
+  label,
+  help,
+  min,
+  max,
+  step,
+  unit,
+});
+
+export const settingGroups: SettingGroup[] = [
+  {
+    title: "passive analysis",
+    icon: "fa-eye",
+    description:
+      "What gets recorded while you type normal tests. Nothing leaves your browser.",
+    fields: [
+      t("enabled", "analyze tests", "Master switch for passive analysis."),
+      t("analyzeTime", "time mode", "Analyze tests in time mode."),
+      t("analyzeWords", "words mode", "Analyze tests in words mode."),
+      t("analyzeQuote", "quote mode", "Analyze quote tests."),
+      t("analyzeCustom", "custom mode", "Analyze custom text tests."),
+      t(
+        "analyzeAdaptiveTests",
+        "adaptive tests",
+        "Feed training tests back into the model (recommended: this is how it sees you improve).",
+      ),
+      t(
+        "analyzeFunboxTests",
+        "funbox tests",
+        "Analyze tests typed with a funbox active.",
+      ),
+      n(
+        "minTestChars",
+        "minimum characters",
+        "Ignore tests shorter than this.",
+        0,
+        500,
+        5,
+      ),
+      n(
+        "minTestAccuracy",
+        "minimum accuracy",
+        "Ignore tests below this accuracy (key mashing, giving up).",
+        0,
+        100,
+        1,
+        "%",
+      ),
+      n(
+        "maxPauseMs",
+        "pause cutoff",
+        "Gaps longer than this are treated as breaks, not as slow typing.",
+        300,
+        10000,
+        50,
+        "ms",
+      ),
+      n(
+        "hesitationFactor",
+        "hesitation factor",
+        "A keystroke counts as a hesitation when it takes this many times your median interval.",
+        1.2,
+        6,
+        0.1,
+        "×",
+      ),
+      t(
+        "notifyAfterTest",
+        "notify after test",
+        "Show a short notification with the weak spots found in each test.",
+      ),
+    ],
+  },
+  {
+    title: "tracking",
+    icon: "fa-layer-group",
+    description: "Which levels of detail the model keeps statistics for.",
+    fields: [
+      t("trackBigrams", "bigrams", "Two-character transitions."),
+      t("trackTrigrams", "trigrams", "Three-character sequences."),
+      t("trackSyllables", "syllables", "Syllables / letter chunks of words."),
+      t("trackWords", "words", "Whole words."),
+      t(
+        "trackSpaceNgrams",
+        "word boundaries",
+        "Include the space in n-grams (word starts and endings).",
+      ),
+      {
+        kind: "select",
+        path: "profileScope",
+        label: "profile scope",
+        help: "Keep one profile, or separate ones per language and/or keyboard layout.",
+        options: [
+          { value: "global", label: "one profile" },
+          { value: "language", label: "per language" },
+          { value: "layout", label: "per layout" },
+          { value: "language+layout", label: "per language + layout" },
+        ],
+      },
+      {
+        kind: "text",
+        path: "layout",
+        label: "keyboard layout",
+        help: "Used for finger / hand / row analysis. 'auto' follows the layout setting (qwerty when that is default). Otherwise any layout name, e.g. colemak_dh, dvorak, workman.",
+      },
+      n(
+        "maxUnits",
+        "max tracked units",
+        "Upper bound on stored statistics; the least seen, oldest ones are pruned.",
+        1000,
+        60000,
+        500,
+      ),
+      n(
+        "maxSessions",
+        "session history",
+        "How many analyzed tests to keep in the progress history.",
+        20,
+        5000,
+        10,
+      ),
+    ],
+  },
+  {
+    title: "statistical model",
+    icon: "fa-square-root-alt",
+    description:
+      "How observations are turned into estimates. Defaults are sensible; change only if you know what you want.",
+    fields: [
+      n(
+        "halfLife",
+        "memory half-life",
+        "After this many new samples of a unit, old samples count half. Lower adapts faster, higher is more stable.",
+        5,
+        1000,
+        5,
+        "samples",
+      ),
+      n(
+        "priorStrength",
+        "prior strength",
+        "Bayesian shrinkage: how many pseudo-samples at your average pull each estimate towards it. Stops rare units with one error from looking terrible.",
+        0,
+        100,
+        1,
+      ),
+      n(
+        "minSamples",
+        "confidence samples",
+        "Number of samples at which a unit's estimate is trusted halfway.",
+        1,
+        100,
+        1,
+      ),
+      n(
+        "trendFast",
+        "trend fast window",
+        "Fast moving average for trend detection.",
+        2,
+        100,
+        1,
+        "samples",
+      ),
+      n(
+        "trendSlow",
+        "trend slow window",
+        "Slow moving average for trend detection.",
+        5,
+        500,
+        5,
+        "samples",
+      ),
+      n(
+        "initialStability",
+        "initial memory stability",
+        "Spaced repetition: days until a freshly practised unit is half due again.",
+        0.1,
+        30,
+        0.1,
+        "days",
+      ),
+      n(
+        "stabilityGrowth",
+        "stability growth",
+        "Multiplier applied to a unit's stability after a clean session.",
+        1,
+        5,
+        0.1,
+        "×",
+      ),
+      n(
+        "stabilityShrink",
+        "stability shrink",
+        "Multiplier applied to a unit's stability after a session with errors.",
+        0.1,
+        1,
+        0.05,
+        "×",
+      ),
+    ],
+  },
+  {
+    title: "weakness scoring",
+    icon: "fa-balance-scale",
+    description:
+      "What counts as a weakness. Presets on the overview tab override the component and level weights, except 'smart mix' and 'custom', which use these.",
+    fields: [
+      {
+        kind: "select",
+        path: "scoringModel",
+        label: "scoring model",
+        help: "composite: weighted mix of the components below. impact: estimated milliseconds lost per occurrence (slowness + error rate × your measured correction cost). hybrid: average of both.",
+        options: [
+          { value: "composite", label: "composite" },
+          { value: "impact", label: "impact (time lost)" },
+          { value: "hybrid", label: "hybrid" },
+        ],
+      },
+      n(
+        "weights.accuracy",
+        "accuracy weight",
+        "Error rate above your average.",
+        0,
+        3,
+        0.05,
+      ),
+      n(
+        "weights.speed",
+        "speed weight",
+        "Latency above your average.",
+        0,
+        3,
+        0.05,
+      ),
+      n(
+        "weights.consistency",
+        "consistency weight",
+        "Timing variance above your average.",
+        0,
+        3,
+        0.05,
+      ),
+      n(
+        "weights.hesitation",
+        "hesitation weight",
+        "Frequency of long stalls.",
+        0,
+        3,
+        0.05,
+      ),
+      n(
+        "weights.trend",
+        "trend weight",
+        "Units that are currently getting worse.",
+        0,
+        3,
+        0.05,
+      ),
+      n(
+        "weights.forgetting",
+        "forgetting weight",
+        "Past weaknesses that have not been practised for a while.",
+        0,
+        3,
+        0.05,
+      ),
+      n(
+        "weights.exploration",
+        "exploration weight",
+        "Bonus for units with little data.",
+        0,
+        3,
+        0.05,
+      ),
+      n("typeWeights.key", "keys level", "Weight of single keys.", 0, 2, 0.05),
+      n(
+        "typeWeights.bigram",
+        "bigrams level",
+        "Weight of bigrams.",
+        0,
+        2,
+        0.05,
+      ),
+      n(
+        "typeWeights.trigram",
+        "trigrams level",
+        "Weight of trigrams.",
+        0,
+        2,
+        0.05,
+      ),
+      n(
+        "typeWeights.syllable",
+        "syllables level",
+        "Weight of syllables.",
+        0,
+        2,
+        0.05,
+      ),
+      n(
+        "typeWeights.word",
+        "words level",
+        "Weight of whole words.",
+        0,
+        2,
+        0.05,
+      ),
+      n(
+        "typeWeights.category",
+        "patterns level",
+        "Weight of fingers and motion patterns.",
+        0,
+        2,
+        0.05,
+      ),
+      n(
+        "frequencyBias",
+        "frequency bias",
+        "0 ignores how common a unit is; 1 strongly prefers weaknesses you meet often.",
+        0,
+        1,
+        0.05,
+      ),
+    ],
+  },
+  {
+    title: "target selection",
+    icon: "fa-crosshairs",
+    description: "How each training test picks what to focus on.",
+    fields: [
+      {
+        kind: "select",
+        path: "selection",
+        label: "selection algorithm",
+        help: "greedy: always the worst units. softmax: random, weighted by score. thompson: samples each unit's plausible true weakness from its posterior, so uncertain units get tested. ucb: optimistic upper confidence bound.",
+        options: [
+          { value: "greedy", label: "greedy" },
+          { value: "softmax", label: "softmax" },
+          { value: "thompson", label: "thompson sampling" },
+          { value: "ucb", label: "upper confidence bound" },
+        ],
+      },
+      n(
+        "temperature",
+        "temperature",
+        "Randomness of softmax selection and of word sampling. Lower is more focused.",
+        0.02,
+        2,
+        0.01,
+      ),
+      n(
+        "focusCount",
+        "focus targets",
+        "How many weaknesses one test concentrates on.",
+        1,
+        40,
+        1,
+      ),
+      n(
+        "broadFactor",
+        "breadth",
+        "How much a word's overall weakness counts besides the focus targets.",
+        0,
+        2,
+        0.05,
+      ),
+    ],
+  },
+  {
+    title: "test generation",
+    icon: "fa-magic",
+    description: "The shape of generated training tests.",
+    fields: [
+      {
+        kind: "select",
+        path: "structure",
+        label: "structure",
+        help: "interleaved: targets mixed randomly (best retention). blocked: one target at a time in groups. progressive: blocked first, then interleaved.",
+        options: [
+          { value: "interleaved", label: "interleaved" },
+          { value: "blocked", label: "blocked" },
+          { value: "progressive", label: "progressive" },
+        ],
+      },
+      n(
+        "blockSize",
+        "block size",
+        "Words per target in blocked sections.",
+        2,
+        12,
+        1,
+      ),
+      {
+        kind: "select",
+        path: "lengthMode",
+        label: "length mode",
+        help: "End the test after a number of words or after a time.",
+        options: [
+          { value: "words", label: "words" },
+          { value: "time", label: "time" },
+        ],
+      },
+      n("wordCount", "word count", "Length in words mode.", 5, 500, 5),
+      n("seconds", "duration", "Length in time mode.", 10, 600, 5, "s"),
+      {
+        kind: "text",
+        path: "wordPool",
+        label: "word pool",
+        help: "'test' uses the current test language. Or any language name for a bigger vocabulary, e.g. english_1k, english_5k, english_10k.",
+      },
+      n(
+        "poolSize",
+        "pool size",
+        "Use only the first N words of the pool (most frequent first in ordered lists).",
+        100,
+        50000,
+        100,
+      ),
+      n("minWordLength", "min word length", "Shortest word to use.", 1, 10, 1),
+      n("maxWordLength", "max word length", "Longest word to use.", 3, 30, 1),
+      n(
+        "repeatWindow",
+        "repeat window",
+        "A word cannot reappear within this many words.",
+        0,
+        50,
+        1,
+      ),
+      n(
+        "pseudoWordRatio",
+        "pseudo-words",
+        "Share of targeted words replaced by generated pronounceable non-words packed with your weak n-grams.",
+        0,
+        1,
+        0.05,
+      ),
+      n(
+        "drillRatio",
+        "raw drills",
+        "Share of targeted words replaced by bare n-gram repetitions (e.g. 'ththth').",
+        0,
+        1,
+        0.05,
+      ),
+      n(
+        "confusionBonus",
+        "confusion bonus",
+        "Extra preference for words containing both letters of a pair you confuse.",
+        0,
+        2,
+        0.05,
+      ),
+      {
+        kind: "select",
+        path: "capitalization",
+        label: "capitalization",
+        help: "auto adds capitals only when the model sees capitals as a weakness.",
+        options: tri,
+      },
+      n(
+        "capitalizationRate",
+        "capitalization rate",
+        "Share of words capitalized.",
+        0,
+        1,
+        0.01,
+      ),
+      {
+        kind: "select",
+        path: "punctuation",
+        label: "punctuation",
+        help: "auto adds punctuation only when it is a measured weakness.",
+        options: tri,
+      },
+      n(
+        "punctuationRate",
+        "punctuation rate",
+        "Share of words punctuated.",
+        0,
+        1,
+        0.01,
+      ),
+      {
+        kind: "select",
+        path: "numbers",
+        label: "numbers",
+        help: "auto adds numbers only when they are a measured weakness.",
+        options: tri,
+      },
+      n(
+        "numbersRate",
+        "numbers rate",
+        "Share of tokens that are numbers.",
+        0,
+        1,
+        0.01,
+      ),
+    ],
+  },
+  {
+    title: "difficulty",
+    icon: "fa-sliders-h",
+    description:
+      "How concentrated the weak material is. Too easy teaches nothing, too hard builds bad habits.",
+    fields: [
+      t(
+        "autoDifficulty",
+        "automatic difficulty",
+        "Adjust intensity after every training test to keep you near the target accuracy.",
+      ),
+      n(
+        "intensity",
+        "manual intensity",
+        "Share of targeted words when automatic difficulty is off.",
+        0,
+        1,
+        0.05,
+      ),
+      n(
+        "targetAccuracy",
+        "target accuracy",
+        "Accuracy the controller steers training tests towards.",
+        80,
+        100,
+        0.5,
+        "%",
+      ),
+      n(
+        "difficultyGain",
+        "controller gain",
+        "How aggressively intensity reacts to missing the target.",
+        0.1,
+        10,
+        0.1,
+      ),
+      n(
+        "minIntensity",
+        "minimum intensity",
+        "Lower bound for automatic intensity.",
+        0,
+        1,
+        0.05,
+      ),
+      n(
+        "maxIntensity",
+        "maximum intensity",
+        "Upper bound for automatic intensity.",
+        0,
+        1,
+        0.05,
+      ),
+    ],
+  },
+  {
+    title: "session behaviour",
+    icon: "fa-sync-alt",
+    description: "How training fits into normal typing.",
+    fields: [
+      t(
+        "continuous",
+        "continuous training",
+        "Restarting during training generates a fresh adaptive test. When off, restarting returns to your previous mode.",
+      ),
+      n(
+        "passiveBlend",
+        "passive blend",
+        "Share of words in NORMAL time / words tests that are quietly swapped for words rich in your weak spots. 0 leaves normal tests untouched.",
+        0,
+        1,
+        0.05,
+      ),
+    ],
+  },
+];
+
+export function getPath(obj: unknown, path: string): unknown {
+  let cur = obj as Record<string, unknown> | undefined;
+  for (const part of path.split(".")) {
+    if (cur === undefined || cur === null) return undefined;
+    cur = cur[part] as Record<string, unknown> | undefined;
+  }
+  return cur;
+}
+
+export function setPath<T extends object>(
+  obj: T,
+  path: string,
+  value: unknown,
+): T {
+  const parts = path.split(".");
+  const clone = structuredClone(obj) as Record<string, unknown>;
+  let cur = clone;
+  for (let i = 0; i < parts.length - 1; i++) {
+    cur = cur[parts[i] as string] as Record<string, unknown>;
+  }
+  cur[parts[parts.length - 1] as string] = value;
+  return clone as T;
+}
+
+/** Merge stored settings over the defaults, dropping unknown / mistyped keys. */
+export function sanitizeSettings(raw: unknown): AdaptiveSettings {
+  const merge = (def: unknown, val: unknown): unknown => {
+    if (typeof def === "object" && def !== null) {
+      const out: Record<string, unknown> = {};
+      const v = (typeof val === "object" && val !== null ? val : {}) as Record<
+        string,
+        unknown
+      >;
+      for (const [k, d] of Object.entries(def)) out[k] = merge(d, v[k]);
+      return out;
+    }
+    if (typeof val !== typeof def) return def;
+    if (typeof val === "number" && !Number.isFinite(val)) return def;
+    return val;
+  };
+  const s = merge(defaultSettings, raw) as AdaptiveSettings;
+  if (!(s.preset in presets)) s.preset = "smart";
+  return s;
+}
diff --git a/frontend/src/ts/adaptive/start.ts b/frontend/src/ts/adaptive/start.ts
new file mode 100644
index 0000000..276b41e
--- /dev/null
+++ b/frontend/src/ts/adaptive/start.ts
@@ -0,0 +1,31 @@
+// Entry points used by the UI and the command line to start / stop training.
+
+import { navigate } from "../router/navigate";
+import { getRoutePage } from "../states/router";
+import { restartTest } from "../test/test-logic";
+import {
+  endTraining,
+  isTraining,
+  prepareTraining,
+  settings,
+  updateSettings,
+} from "./session";
+import { FocusPreset } from "./settings";
+
+export async function startTraining(preset?: FocusPreset): Promise<void> {
+  if (preset !== undefined && preset !== settings().preset) {
+    updateSettings({ ...settings(), preset });
+  }
+  if (!(await prepareTraining())) return;
+  if (getRoutePage() === "test") {
+    await restartTest();
+  } else {
+    await navigate({ to: "/" });
+  }
+}
+
+export async function stopTraining(): Promise<void> {
+  if (!isTraining()) return;
+  endTraining();
+  if (getRoutePage() === "test") await restartTest();
+}
diff --git a/frontend/src/ts/boot.ts b/frontend/src/ts/boot.ts
index f8b93ee..3c07af2 100644
--- a/frontend/src/ts/boot.ts
+++ b/frontend/src/ts/boot.ts
@@ -1,13 +1,11 @@
+import { initAdaptive } from "./adaptive/session";
 import { applyEngineSettings } from "./anim";
 import * as ServerConfiguration from "./ape/server-configuration";
 import { loadFromLocalStorage } from "./config/lifecycle";
 import * as Cookies from "./cookies";
-import * as MerchBanner from "./elements/merch-banner";
-import * as Psa from "./elements/psa";
 import { authPromise, initFirebase } from "./firebase";
 import { initConnection } from "./states/connection";
 import { setAppReady, setVersion } from "./states/core";
-import { showModal } from "./states/modals";
 import { isDevEnvironment } from "./utils/env";
 import { fetchLatestVersion } from "./utils/version";
 
@@ -15,9 +13,9 @@ import { fetchLatestVersion } from "./utils/version";
  * Firebase, then waits for both before the app is ready. Call once, right after
  * render. */
 export async function boot(): Promise<void> {
-  // before awaiting: PSAs show on the first auth state change
   initConnection();
-  Psa.init();
+  initAdaptive();
+  // LOCAL: no backend, so PSAs / server-status banners are disabled
 
   applyEngineSettings();
   const configLoaded = loadFromLocalStorage();
@@ -27,9 +25,7 @@ export async function boot(): Promise<void> {
   });
 
   const accepted = Cookies.getAcceptedCookies();
-  if (accepted === null) {
-    showModal("Cookies");
-  }
+  // LOCAL: no cookie popup; nothing is accepted, so analytics/sentry stay off
   void initFirebase().then(() => {
     if (accepted !== null) {
       Cookies.activateWhatsAccepted();
@@ -39,8 +35,6 @@ export async function boot(): Promise<void> {
   await configLoaded;
   await authPromise;
 
-  MerchBanner.showIfNotClosedBefore();
-
   setAppReady(true);
 
   void ServerConfiguration.sync();
diff --git a/frontend/src/ts/commandline/lists/navigation.ts b/frontend/src/ts/commandline/lists/navigation.ts
index 46f5d92..dd4451e 100644
--- a/frontend/src/ts/commandline/lists/navigation.ts
+++ b/frontend/src/ts/commandline/lists/navigation.ts
@@ -34,6 +34,33 @@ const commands: Command[] = [
       void navigate({ to: "/about" });
     },
   },
+  {
+    id: "viewAdaptive",
+    display: "View Adaptive Trainer",
+    alias: "navigate go to weakness analysis training practice",
+    fa: { icon: "fa-brain" },
+    exec: (): void => {
+      void navigate({ to: "/adaptive" });
+    },
+  },
+  {
+    id: "startAdaptiveTraining",
+    display: "Adaptive training: start",
+    alias: "weakness practice train drill smart",
+    fa: { icon: "fa-dumbbell" },
+    exec: (): void => {
+      void import("../../adaptive/start").then(async (m) => m.startTraining());
+    },
+  },
+  {
+    id: "stopAdaptiveTraining",
+    display: "Adaptive training: stop",
+    alias: "weakness practice train end leave",
+    fa: { icon: "fa-stop" },
+    exec: (): void => {
+      void import("../../adaptive/start").then(async (m) => m.stopTraining());
+    },
+  },
   {
     id: "viewSettings",
     display: "View Settings Page",
diff --git a/frontend/src/ts/components/layout/header/Nav.tsx b/frontend/src/ts/components/layout/header/Nav.tsx
index 2ca7c56..e9b4a27 100644
--- a/frontend/src/ts/components/layout/header/Nav.tsx
+++ b/frontend/src/ts/components/layout/header/Nav.tsx
@@ -108,6 +108,18 @@ export function Nav(): JSXElement {
         class={buttonClass()}
         to="/leaderboards"
       />
+      <Button
+        variant="text"
+        fa={{
+          icon: "fa-brain",
+          fixedWidth: true,
+        }}
+        class={buttonClass()}
+        dataset={{
+          "data-nav-item": "adaptive",
+        }}
+        to="/adaptive"
+      />
       <Button
         variant="text"
         fa={{
diff --git a/frontend/src/ts/components/pages/adaptive/AdaptivePage.tsx b/frontend/src/ts/components/pages/adaptive/AdaptivePage.tsx
new file mode 100644
index 0000000..779ad03
--- /dev/null
+++ b/frontend/src/ts/components/pages/adaptive/AdaptivePage.tsx
@@ -0,0 +1,89 @@
+import { createSignal, For, JSXElement, Match, Show, Switch } from "solid-js";
+
+import { isTraining, settings } from "../../../adaptive/session";
+import { FaSolidIcon } from "../../../types/font-awesome";
+import { Button } from "../../common/Button";
+import { H2 } from "../../common/Headers";
+import { ErrorsTab } from "./ErrorsTab";
+import { KeyboardTab } from "./KeyboardTab";
+import { OverviewTab } from "./OverviewTab";
+import { ProgressTab } from "./ProgressTab";
+import { SettingsTab } from "./SettingsTab";
+import { createScored } from "./shared";
+import { UnitsTab } from "./UnitsTab";
+
+type Tab =
+  | "overview"
+  | "units"
+  | "keyboard"
+  | "errors"
+  | "progress"
+  | "settings";
+
+const tabs: { id: Tab; label: string; icon: FaSolidIcon }[] = [
+  { id: "overview", label: "overview", icon: "fa-brain" },
+  { id: "units", label: "weak spots", icon: "fa-list-ol" },
+  { id: "keyboard", label: "keyboard", icon: "fa-keyboard" },
+  { id: "errors", label: "errors", icon: "fa-bug" },
+  { id: "progress", label: "progress", icon: "fa-chart-line" },
+  { id: "settings", label: "settings", icon: "fa-cog" },
+];
+
+/** The adaptive trainer: analysis of passively collected data + training control. */
+export function AdaptivePage(): JSXElement {
+  const [tab, setTab] = createSignal<Tab>("overview");
+  const scored = createScored();
+
+  return (
+    <div class="content-grid grid content-start gap-6 pb-8">
+      <div class="flex flex-wrap items-end justify-between gap-4">
+        <H2 class="pb-0" fa={{ icon: "fa-brain" }} text="adaptive trainer" />
+        <div class="text-sm text-sub">
+          <Show
+            when={settings().enabled}
+            fallback={<span class="text-error">passive analysis is off</span>}
+          >
+            passive analysis is on
+          </Show>
+          <Show when={isTraining()}>
+            {" · "}
+            <span class="text-main">training in progress</span>
+          </Show>
+        </div>
+      </div>
+      <div class="flex flex-wrap gap-2">
+        <For each={tabs}>
+          {(t) => (
+            <Button
+              variant="button"
+              active={tab() === t.id}
+              fa={{ icon: t.icon, fixedWidth: true }}
+              text={t.label}
+              onClick={() => setTab(t.id)}
+            />
+          )}
+        </For>
+      </div>
+      <Switch>
+        <Match when={tab() === "overview"}>
+          <OverviewTab scored={scored()} />
+        </Match>
+        <Match when={tab() === "units"}>
+          <UnitsTab scored={scored()} />
+        </Match>
+        <Match when={tab() === "keyboard"}>
+          <KeyboardTab scored={scored()} />
+        </Match>
+        <Match when={tab() === "errors"}>
+          <ErrorsTab />
+        </Match>
+        <Match when={tab() === "progress"}>
+          <ProgressTab />
+        </Match>
+        <Match when={tab() === "settings"}>
+          <SettingsTab />
+        </Match>
+      </Switch>
+    </div>
+  );
+}
diff --git a/frontend/src/ts/components/pages/adaptive/ErrorsTab.tsx b/frontend/src/ts/components/pages/adaptive/ErrorsTab.tsx
new file mode 100644
index 0000000..5e3e0dc
--- /dev/null
+++ b/frontend/src/ts/components/pages/adaptive/ErrorsTab.tsx
@@ -0,0 +1,78 @@
+import { createMemo, For, JSXElement, Show } from "solid-js";
+
+import { errorBreakdown, errorTypeInfo } from "../../../adaptive/insights";
+import { getProfile, version } from "../../../adaptive/session";
+import { Card, Empty, Meter, pct, show } from "./shared";
+
+export function ErrorsTab(): JSXElement {
+  const profile = createMemo(() => {
+    version();
+    return getProfile();
+  });
+  const breakdown = createMemo(() => errorBreakdown(profile()));
+  const pairs = createMemo(() =>
+    Object.entries(profile().conf)
+      .filter(([, count]) => count >= 0.5)
+      .sort((a, b) => b[1] - a[1])
+      .slice(0, 30),
+  );
+  const maxPair = (): number => pairs()[0]?.[1] ?? 1;
+
+  return (
+    <div class="grid gap-6 xl:grid-cols-2">
+      <Card title="what kind of mistakes" icon="fa-bug">
+        <Show
+          when={breakdown().length > 0}
+          fallback={<Empty text="No errors recorded yet." />}
+        >
+          <div class="grid grid-cols-[auto_1fr_auto] items-center gap-x-4 gap-y-3">
+            <For each={breakdown()}>
+              {(row) => (
+                <>
+                  <div>
+                    <div class="text-text">{errorTypeInfo[row.type].label}</div>
+                    <div class="max-w-72 text-xs text-sub">
+                      {errorTypeInfo[row.type].help}
+                    </div>
+                  </div>
+                  <Meter value={row.share / (breakdown()[0]?.share ?? 1)} />
+                  <div class="text-right whitespace-nowrap">
+                    {pct(row.share, 0)}{" "}
+                    <span class="text-sm text-sub">({row.count})</span>
+                  </div>
+                </>
+              )}
+            </For>
+          </div>
+        </Show>
+      </Card>
+      <Card title="letter confusions (expected → typed)" icon="fa-random">
+        <Show
+          when={pairs().length > 0}
+          fallback={<Empty text="No confusions recorded yet." />}
+        >
+          <div class="grid grid-cols-2 gap-x-8 gap-y-2 md:grid-cols-3">
+            <For each={pairs()}>
+              {([pair, count]) => {
+                const [exp, typed] = pair.split(">") as [string, string];
+                return (
+                  <div class="grid grid-cols-[auto_1fr] items-center gap-3">
+                    <div class="text-xl whitespace-pre">
+                      <span class="text-main">{show(exp)}</span>
+                      <span class="text-sub"> → </span>
+                      <span class="text-error">{show(typed)}</span>
+                    </div>
+                    <Meter value={count / maxPair()} />
+                  </div>
+                );
+              }}
+            </For>
+          </div>
+          <div class="mt-4 text-xs text-sub">
+            Recency-weighted: old confusions fade as you stop making them.
+          </div>
+        </Show>
+      </Card>
+    </div>
+  );
+}
diff --git a/frontend/src/ts/components/pages/adaptive/KeyboardTab.tsx b/frontend/src/ts/components/pages/adaptive/KeyboardTab.tsx
new file mode 100644
index 0000000..4251d1c
--- /dev/null
+++ b/frontend/src/ts/components/pages/adaptive/KeyboardTab.tsx
@@ -0,0 +1,190 @@
+// oxlint-disable monkeytype-rules/one-component-per-file
+import { createMemo, createSignal, For, JSXElement, Show } from "solid-js";
+
+import { patternLabel } from "../../../adaptive/generate";
+import { Scored } from "../../../adaptive/model";
+import { getGeometry, version } from "../../../adaptive/session";
+import { cn } from "../../../utils/cn";
+import { Button } from "../../common/Button";
+import { Card, Empty, levelClass, Meter, msToWpm, pct } from "./shared";
+
+type Metric = "weakness" | "errors" | "speed" | "samples";
+
+const fingerOrder = [0, 1, 2, 3, 4, 5, 6, 7];
+const motionIds = [
+  "alt",
+  "roll-in",
+  "roll-out",
+  "sfb",
+  "double",
+  "rowjump",
+  "stretch",
+];
+const otherIds = [
+  "word-start",
+  "capital",
+  "punctuation",
+  "number",
+  "row-0",
+  "row-1",
+  "row-2",
+  "row-3",
+  "len-short",
+  "len-medium",
+  "len-long",
+  "len-xlong",
+];
+
+function PatternTable(props: {
+  title: string;
+  icon: string;
+  ids: string[];
+  byId: Map<string, Scored>;
+  wordLevel?: boolean;
+}): JSXElement {
+  const rows = (): Scored[] =>
+    props.ids
+      .map((id) => props.byId.get(`c:${id}`))
+      .filter((s): s is Scored => s !== undefined);
+  return (
+    <Card title={props.title} icon={props.icon}>
+      <Show when={rows().length > 0} fallback={<Empty text="No data yet." />}>
+        <div class="grid grid-cols-[auto_minmax(2.5rem,1fr)_auto_auto_auto] items-center gap-x-3 gap-y-2 text-sm">
+          <For each={rows()}>
+            {(s) => (
+              <>
+                <div class={cn("whitespace-nowrap", levelClass[s.level])}>
+                  {patternLabel(s.text)}
+                </div>
+                <Meter value={s.level === "new" ? 0 : s.weakness} />
+                <div class="text-right whitespace-nowrap">
+                  {pct(s.errorRate)} err
+                </div>
+                <div class="text-right whitespace-nowrap">
+                  {Math.round(msToWpm(s.ms))} wpm
+                </div>
+                <div class="text-right text-sm whitespace-nowrap text-sub">
+                  {s.relLatency >= 1 ? "+" : ""}
+                  {Math.round((s.relLatency - 1) * 100)}%
+                </div>
+              </>
+            )}
+          </For>
+        </div>
+      </Show>
+    </Card>
+  );
+}
+
+export function KeyboardTab(props: { scored: Scored[] }): JSXElement {
+  const [metric, setMetric] = createSignal<Metric>("weakness");
+  const byId = createMemo(() => new Map(props.scored.map((s) => [s.id, s])));
+  const geo = createMemo(() => {
+    version();
+    return getGeometry();
+  });
+  const maxSamples = createMemo(() =>
+    Math.max(
+      1,
+      ...props.scored.filter((s) => s.type === "k").map((s) => s.samples),
+    ),
+  );
+
+  const heat = (ch: string): number => {
+    const s = byId().get(`k:${ch}`);
+    if (s === undefined) return 0;
+    switch (metric()) {
+      case "weakness":
+        return s.level === "new" ? 0 : Math.min(1, s.weakness * 1.6);
+      case "errors":
+        return Math.min(1, s.errorRate * 8);
+      case "speed":
+        return Math.min(1, Math.max(0, (s.relLatency - 0.85) * 2));
+      default:
+        return s.samples / maxSamples();
+    }
+  };
+  const label = (ch: string): string => {
+    const s = byId().get(`k:${ch}`);
+    if (s === undefined) return "no data";
+    return `${pct(s.errorRate)} errors · ${Math.round(msToWpm(s.ms))} wpm · ${s.samples} samples · ${s.level}`;
+  };
+
+  return (
+    <div class="grid gap-6">
+      <Card title={`key heatmap (${geo().name})`} icon="fa-keyboard">
+        <div class="mb-4 flex flex-wrap gap-2">
+          <For each={["weakness", "errors", "speed", "samples"] as Metric[]}>
+            {(m) => (
+              <Button
+                variant="button"
+                active={metric() === m}
+                text={m}
+                onClick={() => setMetric(m)}
+              />
+            )}
+          </For>
+        </div>
+        <div class="grid justify-center gap-1.5 overflow-x-auto">
+          <For each={geo().rows}>
+            {(row, r) => (
+              <div
+                class="flex gap-1.5"
+                style={{
+                  "padding-left": `${[0, 1.5, 2.25, 3.5][r()] ?? 0}rem`,
+                }}
+              >
+                <For each={row}>
+                  {(ch) => (
+                    <div
+                      class="grid h-11 w-11 shrink-0 place-items-center rounded text-lg text-text"
+                      style={{
+                        background: `color-mix(in srgb, var(--${metric() === "samples" ? "main" : "error"}-color) ${Math.round(heat(ch) * 100)}%, var(--bg-color))`,
+                      }}
+                      aria-label={label(ch)}
+                      data-balloon-pos="up"
+                    >
+                      {ch}
+                    </div>
+                  )}
+                </For>
+              </div>
+            )}
+          </For>
+          <div class="flex justify-center pt-1">
+            <div
+              class="grid h-9 w-72 place-items-center rounded text-sm text-sub"
+              style={{
+                background: `color-mix(in srgb, var(--${metric() === "samples" ? "main" : "error"}-color) ${Math.round(heat(" ") * 100)}%, var(--bg-color))`,
+              }}
+              aria-label={label(" ")}
+              data-balloon-pos="up"
+            >
+              space
+            </div>
+          </div>
+        </div>
+      </Card>
+      <div class="grid gap-6 lg:grid-cols-2 2xl:grid-cols-3">
+        <PatternTable
+          title="fingers"
+          icon="fa-hand-paper"
+          ids={fingerOrder.map((f) => `finger-${f}`)}
+          byId={byId()}
+        />
+        <PatternTable
+          title="motion patterns"
+          icon="fa-exchange-alt"
+          ids={motionIds}
+          byId={byId()}
+        />
+        <PatternTable
+          title="rows, symbols, word length"
+          icon="fa-th"
+          ids={otherIds}
+          byId={byId()}
+        />
+      </div>
+    </div>
+  );
+}
diff --git a/frontend/src/ts/components/pages/adaptive/OverviewTab.tsx b/frontend/src/ts/components/pages/adaptive/OverviewTab.tsx
new file mode 100644
index 0000000..4335586
--- /dev/null
+++ b/frontend/src/ts/components/pages/adaptive/OverviewTab.tsx
@@ -0,0 +1,247 @@
+// oxlint-disable monkeytype-rules/one-component-per-file
+import { createMemo, For, JSXElement, Show } from "solid-js";
+
+import {
+  selectTargets,
+  Target,
+  targetLabel,
+  typeLabel,
+} from "../../../adaptive/generate";
+import { buildInsights, potentialGain } from "../../../adaptive/insights";
+import { Scored, weaknessIndex } from "../../../adaptive/model";
+import {
+  activePlan,
+  getProfile,
+  isTraining,
+  settings,
+  updateSettings,
+  version,
+} from "../../../adaptive/session";
+import { FocusPreset, presets } from "../../../adaptive/settings";
+import { startTraining, stopTraining } from "../../../adaptive/start";
+import { FaSolidIcon } from "../../../types/font-awesome";
+import { cn } from "../../../utils/cn";
+import { Button } from "../../common/Button";
+import { Fa } from "../../common/Fa";
+import { Card, Empty, StatTile } from "./shared";
+
+function TargetChip(props: { target: Target }): JSXElement {
+  return (
+    <div class="flex items-baseline gap-2 rounded bg-bg px-3 py-2">
+      <span class="text-xl text-main">{targetLabel(props.target)}</span>
+      <span class="text-xs text-sub">
+        {typeLabel(props.target.type)} · {props.target.reason}
+      </span>
+    </div>
+  );
+}
+
+export function OverviewTab(props: { scored: Scored[] }): JSXElement {
+  const profile = createMemo(() => {
+    version();
+    return getProfile();
+  });
+  const insights = createMemo(() => buildInsights(profile(), props.scored));
+  const wi = createMemo(() => weaknessIndex(props.scored));
+  const wiDelta = createMemo(() => {
+    const s = profile().sessions;
+    if (s.length < 6) return null;
+    const then = s[Math.max(0, s.length - 11)]?.wi ?? 0;
+    return wi() - then;
+  });
+  const gain = createMemo(() => potentialGain(props.scored));
+  const preview = createMemo(() => {
+    version();
+    // point estimates: a stable preview of what the model currently ranks worst
+    return selectTargets(
+      profile(),
+      { ...settings(), selection: "greedy" },
+      Date.now(),
+      Math.random,
+    ).targets;
+  });
+  const counts = createMemo(() => {
+    const out = { critical: 0, weak: 0, mastered: 0, tracked: 0 };
+    for (const s of props.scored) {
+      if (s.type === "c") continue;
+      out.tracked++;
+      if (s.level === "critical") out.critical++;
+      else if (s.level === "weak") out.weak++;
+      else if (s.level === "mastered" || s.level === "good") out.mastered++;
+    }
+    return out;
+  });
+  const intensity = (): number =>
+    settings().autoDifficulty ? profile().g.intensity : settings().intensity;
+
+  return (
+    <div class="grid gap-6">
+      <div class="grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-6">
+        <StatTile
+          label="tests analyzed"
+          value={String(profile().g.tests)}
+          sub={`${profile().g.chars.toLocaleString()} keystrokes`}
+        />
+        <StatTile
+          label="weakness index"
+          value={wi().toFixed(1)}
+          sub={
+            wiDelta() === null
+              ? "lower is better"
+              : `${(wiDelta() as number) <= 0 ? "▼" : "▲"} ${Math.abs(wiDelta() as number).toFixed(1)} vs 10 tests ago`
+          }
+          help="Frequency-weighted average weakness of everything tracked, 0 to 100."
+        />
+        <StatTile
+          label="potential gain"
+          value={`${Math.round(gain() * 100)}%`}
+          sub="time lost to weak bigrams"
+          help="Share of typing time spent on bigrams being slower or more error-prone than your own average. Roughly the speed-up from fixing them."
+        />
+        <StatTile
+          label="error cost"
+          value={`${Math.round(profile().g.errCost)} ms`}
+          sub="per mistake"
+          help="Average time from making a mistake to being back on track (noticing, deleting, retyping)."
+        />
+        <StatTile
+          label="weak spots"
+          value={String(counts().critical + counts().weak)}
+          sub={`${counts().critical} critical · ${counts().tracked} tracked`}
+        />
+        <StatTile
+          label="intensity"
+          value={`${Math.round(intensity() * 100)}%`}
+          sub={settings().autoDifficulty ? "auto-adjusted" : "manual"}
+          help="Share of each training test made of targeted material. Automatic difficulty moves it to keep you near your target accuracy."
+        />
+      </div>
+
+      <Card title="training" icon="fa-dumbbell">
+        <div class="grid gap-4">
+          <div class="grid grid-cols-2 gap-2 md:grid-cols-4 xl:grid-cols-7">
+            <For
+              each={
+                Object.entries(presets) as [
+                  FocusPreset,
+                  (typeof presets)[FocusPreset],
+                ][]
+              }
+            >
+              {([id, def]) => (
+                <Button
+                  variant="button"
+                  active={settings().preset === id}
+                  text={def.label}
+                  balloon={{
+                    text: def.description,
+                    position: "up",
+                    length: "medium",
+                  }}
+                  onClick={() => updateSettings({ ...settings(), preset: id })}
+                />
+              )}
+            </For>
+          </div>
+          <div class="text-sm text-sub">
+            {presets[settings().preset].description}
+          </div>
+          <div class="flex flex-wrap items-center gap-3">
+            <Button
+              variant="button"
+              class="px-6 py-3 text-xl"
+              fa={{ icon: "fa-play" }}
+              text={isTraining() ? "new training test" : "start training"}
+              onClick={() => void startTraining()}
+            />
+            <Show when={isTraining()}>
+              <Button
+                variant="button"
+                fa={{ icon: "fa-stop" }}
+                text="end training"
+                onClick={() => void stopTraining()}
+              />
+            </Show>
+            <span class="text-sm text-sub">
+              {settings().lengthMode === "time"
+                ? `${settings().seconds}s`
+                : `${settings().wordCount} words`}{" "}
+              · {settings().structure} · {settings().selection} ·{" "}
+              {settings().continuous ? "continuous" : "single test"}
+            </span>
+          </div>
+        </div>
+      </Card>
+
+      <Show when={activePlan()}>
+        {(plan) => (
+          <Card title="current training test" icon="fa-bullseye">
+            <div class="mb-3 text-sm text-sub">
+              {plan().mix.targeted} targeted · {plan().mix.pseudo} pseudo-words
+              · {plan().mix.drill} drills · {plan().mix.filler} filler ·
+              intensity {Math.round(plan().intensity * 100)}%
+            </div>
+            <div class="flex flex-wrap gap-2">
+              <For each={plan().targets}>
+                {(t) => <TargetChip target={t} />}
+              </For>
+            </div>
+          </Card>
+        )}
+      </Show>
+
+      <div class="grid gap-6 xl:grid-cols-2">
+        <Card title="what the model would target next" icon="fa-crosshairs">
+          <Show
+            when={preview().length > 0 && profile().g.chars >= 100}
+            fallback={
+              <Empty text="No data yet. Type a few normal tests: analysis runs in the background." />
+            }
+          >
+            <div class="flex flex-wrap gap-2">
+              <For each={preview()}>{(t) => <TargetChip target={t} />}</For>
+            </div>
+          </Show>
+        </Card>
+        <Card title="insights" icon="fa-lightbulb">
+          <Show
+            when={insights().length > 0}
+            fallback={
+              <Empty text="Insights appear once there is enough data." />
+            }
+          >
+            <div class="grid gap-3">
+              <For each={insights()}>
+                {(insight) => (
+                  <div class="grid grid-cols-[auto_1fr_auto] items-start gap-3">
+                    <Fa
+                      icon={insight.icon as FaSolidIcon}
+                      fixedWidth
+                      class="pt-1 text-main"
+                    />
+                    <div>
+                      <div class="text-text">{insight.title}</div>
+                      <div class="text-sm text-sub">{insight.text}</div>
+                    </div>
+                    <Show when={insight.preset}>
+                      <Button
+                        variant="text"
+                        class={cn("text-sm")}
+                        fa={{ icon: "fa-play" }}
+                        text={insight.preset}
+                        balloon={{ text: "train this now", position: "left" }}
+                        onClick={() =>
+                          void startTraining(insight.preset as FocusPreset)
+                        }
+                      />
+                    </Show>
+                  </div>
+                )}
+              </For>
+            </div>
+          </Show>
+        </Card>
+      </div>
+    </div>
+  );
+}
diff --git a/frontend/src/ts/components/pages/adaptive/ProgressTab.tsx b/frontend/src/ts/components/pages/adaptive/ProgressTab.tsx
new file mode 100644
index 0000000..b8e3faa
--- /dev/null
+++ b/frontend/src/ts/components/pages/adaptive/ProgressTab.tsx
@@ -0,0 +1,209 @@
+// oxlint-disable monkeytype-rules/one-component-per-file
+import { createMemo, For, JSXElement, Show } from "solid-js";
+
+import { SessionSummary } from "../../../adaptive/model";
+import { getProfile, version } from "../../../adaptive/session";
+import { Card, Empty } from "./shared";
+
+function LineChart(props: {
+  sessions: SessionSummary[];
+  value: (s: SessionSummary) => number;
+  format: (v: number) => string;
+}): JSXElement {
+  const w = 600;
+  const h = 140;
+  const pad = 6;
+  const data = createMemo(() => {
+    const values = props.sessions.map(props.value);
+    const min = Math.min(...values);
+    const max = Math.max(...values);
+    const span = max - min || 1;
+    const x = (i: number): number =>
+      pad +
+      (values.length <= 1 ? 0.5 : i / (values.length - 1)) * (w - 2 * pad);
+    const y = (v: number): number =>
+      h - pad - ((v - min) / span) * (h - 2 * pad);
+    // smoothed trend: moving average over a fifth of the history
+    const win = Math.max(1, Math.round(values.length / 5));
+    const smooth = values.map((_, i) => {
+      const part = values.slice(Math.max(0, i - win + 1), i + 1);
+      return part.reduce((a, b) => a + b, 0) / part.length;
+    });
+    return {
+      min,
+      max,
+      last: values[values.length - 1] ?? 0,
+      points: values.map((v, i) => ({
+        x: x(i),
+        y: y(v),
+        adaptive: props.sessions[i]?.adaptive,
+      })),
+      path: smooth
+        .map(
+          (v, i) =>
+            `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(v).toFixed(1)}`,
+        )
+        .join(" "),
+    };
+  });
+  return (
+    <div>
+      <svg
+        viewBox={`0 0 ${w} ${h}`}
+        class="h-36 w-full"
+        preserveAspectRatio="none"
+      >
+        {/* oxlint-disable-next-line react/no-unknown-property */}
+        <path
+          d={data().path}
+          fill="none"
+          class="stroke-main stroke-2 [vector-effect:non-scaling-stroke]"
+        ></path>
+        <For each={data().points}>
+          {(p) => (
+            <circle
+              cx={p.x}
+              cy={p.y}
+              r="2.5"
+              class={p.adaptive ? "fill-main" : "fill-sub"}
+            ></circle>
+          )}
+        </For>
+      </svg>
+      <div class="flex justify-between text-xs text-sub">
+        <span>
+          min {props.format(data().min)} · max {props.format(data().max)}
+        </span>
+        <span class="text-text">now {props.format(data().last)}</span>
+      </div>
+    </div>
+  );
+}
+
+export function ProgressTab(): JSXElement {
+  const sessions = createMemo(() => {
+    version();
+    return getProfile().sessions;
+  });
+  const recent = (): SessionSummary[] => [...sessions()].reverse().slice(0, 15);
+  const fmtTime = (t: number): string =>
+    new Date(t).toLocaleString(undefined, {
+      month: "short",
+      day: "numeric",
+      hour: "2-digit",
+      minute: "2-digit",
+    });
+
+  return (
+    <Show
+      when={sessions().length >= 2}
+      fallback={
+        <Empty text="Progress charts appear after two analyzed tests." />
+      }
+    >
+      <div class="grid gap-6">
+        <div class="text-xs text-sub">
+          Each dot is one analyzed test (highlighted = training test). The line
+          is a moving average.
+        </div>
+        <div class="grid gap-6 xl:grid-cols-2">
+          <Card title="weakness index (lower is better)" icon="fa-chart-line">
+            <LineChart
+              sessions={sessions()}
+              value={(s) => s.wi}
+              format={(v) => v.toFixed(1)}
+            />
+          </Card>
+          <Card title="speed" icon="fa-tachometer-alt">
+            <LineChart
+              sessions={sessions()}
+              value={(s) => s.wpm}
+              format={(v) => `${Math.round(v)} wpm`}
+            />
+          </Card>
+          <Card title="accuracy" icon="fa-bullseye">
+            <LineChart
+              sessions={sessions()}
+              value={(s) => s.acc}
+              format={(v) => `${v.toFixed(1)}%`}
+            />
+          </Card>
+          <Card
+            title="rhythm consistency (variation, lower is better)"
+            icon="fa-wave-square"
+          >
+            <LineChart
+              sessions={sessions()}
+              value={(s) => s.consistency}
+              format={(v) => `${Math.round(v * 100)}%`}
+            />
+          </Card>
+          <Card title="error cost" icon="fa-hourglass-half">
+            <LineChart
+              sessions={sessions().filter((s) => s.errCost > 0)}
+              value={(s) => s.errCost}
+              format={(v) => `${Math.round(v)} ms`}
+            />
+          </Card>
+          <Card
+            title="fatigue (last third vs first third)"
+            icon="fa-battery-quarter"
+          >
+            <LineChart
+              sessions={sessions()}
+              value={(s) => s.fatigue}
+              format={(v) =>
+                `${v >= 1 ? "+" : ""}${Math.round((v - 1) * 100)}%`
+              }
+            />
+          </Card>
+        </div>
+        <Card title="recent tests" icon="fa-history">
+          <div class="overflow-x-auto">
+            <table class="w-full border-collapse [&>tbody>tr:nth-child(odd)>td]:bg-bg">
+              <thead>
+                <tr class="text-left text-sub [&>th]:px-3 [&>th]:py-2 [&>th]:font-normal">
+                  <th>when</th>
+                  <th>mode</th>
+                  <th>wpm</th>
+                  <th>acc</th>
+                  <th>keystrokes</th>
+                  <th>weakness index</th>
+                  <th>error cost</th>
+                  <th>after-error tempo</th>
+                  <th>intensity</th>
+                </tr>
+              </thead>
+              <tbody>
+                <For each={recent()}>
+                  {(s) => (
+                    <tr class="[&>td]:px-3 [&>td]:py-2">
+                      <td class="whitespace-nowrap text-sub">{fmtTime(s.t)}</td>
+                      <td class={s.adaptive ? "text-main" : ""}>{s.mode}</td>
+                      <td>{Math.round(s.wpm)}</td>
+                      <td>{s.acc.toFixed(1)}%</td>
+                      <td>{s.chars}</td>
+                      <td>{s.wi.toFixed(1)}</td>
+                      <td>
+                        {s.errCost > 0 ? `${Math.round(s.errCost)} ms` : "–"}
+                      </td>
+                      <td>
+                        {s.postError >= 1 ? "+" : ""}
+                        {Math.round((s.postError - 1) * 100)}%
+                      </td>
+                      <td>
+                        {s.intensity !== undefined
+                          ? `${Math.round(s.intensity * 100)}%`
+                          : "–"}
+                      </td>
+                    </tr>
+                  )}
+                </For>
+              </tbody>
+            </table>
+          </div>
+        </Card>
+      </div>
+    </Show>
+  );
+}
diff --git a/frontend/src/ts/components/pages/adaptive/SettingsTab.tsx b/frontend/src/ts/components/pages/adaptive/SettingsTab.tsx
new file mode 100644
index 0000000..cd9a096
--- /dev/null
+++ b/frontend/src/ts/components/pages/adaptive/SettingsTab.tsx
@@ -0,0 +1,288 @@
+// oxlint-disable monkeytype-rules/one-component-per-file
+import { createSignal, For, JSXElement, Match, Show, Switch } from "solid-js";
+
+import {
+  exportData,
+  getProfile,
+  importData,
+  listProfiles,
+  profileId,
+  resetProfile,
+  resetSettings,
+  settings,
+  updateSettings,
+  version,
+} from "../../../adaptive/session";
+import {
+  defaultSettings,
+  getPath,
+  SettingField,
+  settingGroups,
+  setPath,
+} from "../../../adaptive/settings";
+import {
+  showErrorNotification,
+  showSuccessNotification,
+} from "../../../states/notifications";
+import { FaSolidIcon } from "../../../types/font-awesome";
+import { cn } from "../../../utils/cn";
+import { Button } from "../../common/Button";
+import { Fa } from "../../common/Fa";
+import { Card } from "./shared";
+
+function set(path: string, value: unknown): void {
+  updateSettings(setPath(settings(), path, value));
+}
+
+function Field(props: { field: SettingField }): JSXElement {
+  const value = (): unknown => getPath(settings(), props.field.path);
+  const changed = (): boolean =>
+    value() !== getPath(defaultSettings, props.field.path);
+  return (
+    <div class="grid grid-cols-1 items-center gap-x-6 gap-y-2 py-2 md:grid-cols-[1fr_auto]">
+      <div>
+        <div class="flex items-center gap-2 text-text">
+          {props.field.label}
+          <Show when={changed()}>
+            <button
+              type="button"
+              class="cursor-pointer text-xs text-sub hover:text-text"
+              aria-label="reset to default"
+              data-balloon-pos="right"
+              onClick={() =>
+                set(
+                  props.field.path,
+                  getPath(defaultSettings, props.field.path),
+                )
+              }
+            >
+              <Fa icon="fa-undo" />
+            </button>
+          </Show>
+        </div>
+        <div class="text-sm text-sub">{props.field.help}</div>
+      </div>
+      <Switch>
+        <Match when={props.field.kind === "toggle"}>
+          <div class="flex gap-2">
+            <Button
+              variant="button"
+              class="w-16"
+              active={value() === false}
+              text="off"
+              onClick={() => set(props.field.path, false)}
+            />
+            <Button
+              variant="button"
+              class="w-16"
+              active={value() === true}
+              text="on"
+              onClick={() => set(props.field.path, true)}
+            />
+          </div>
+        </Match>
+        <Match when={props.field.kind === "number" && props.field}>
+          {(f) => {
+            const field = f();
+            const commit = (raw: string): void => {
+              const parsed = Number(raw);
+              if (!Number.isFinite(parsed)) return;
+              set(field.path, Math.min(field.max, Math.max(field.min, parsed)));
+            };
+            return (
+              <div class="flex items-center gap-3">
+                <input
+                  type="range"
+                  class="w-40"
+                  min={field.min}
+                  max={field.max}
+                  step={field.step}
+                  value={value() as number}
+                  onInput={(e) => commit(e.currentTarget.value)}
+                />
+                <input
+                  type="number"
+                  class="w-24 text-right"
+                  min={field.min}
+                  max={field.max}
+                  step={field.step}
+                  value={value() as number}
+                  onChange={(e) => commit(e.currentTarget.value)}
+                />
+                <span class="w-14 text-sm text-sub">{field.unit ?? ""}</span>
+              </div>
+            );
+          }}
+        </Match>
+        <Match when={props.field.kind === "select" && props.field}>
+          {(f) => (
+            <div class="flex flex-wrap justify-end gap-2">
+              <For each={f().options}>
+                {(opt) => (
+                  <Button
+                    variant="button"
+                    active={value() === opt.value}
+                    text={opt.label}
+                    onClick={() => set(props.field.path, opt.value)}
+                  />
+                )}
+              </For>
+            </div>
+          )}
+        </Match>
+        <Match when={props.field.kind === "text"}>
+          <input
+            class="w-56"
+            value={value() as string}
+            onChange={(e) =>
+              set(props.field.path, e.currentTarget.value.trim() || "auto")
+            }
+          />
+        </Match>
+      </Switch>
+    </div>
+  );
+}
+
+export function SettingsTab(): JSXElement {
+  const [importText, setImportText] = createSignal("");
+  const [confirmReset, setConfirmReset] = createSignal(false);
+  const [query, setQuery] = createSignal("");
+
+  const download = (): void => {
+    const blob = new Blob([exportData()], { type: "application/json" });
+    const url = URL.createObjectURL(blob);
+    const a = document.createElement("a");
+    a.href = url;
+    a.download = `adaptive-trainer-${new Date().toISOString().slice(0, 10)}.json`;
+    a.click();
+    URL.revokeObjectURL(url);
+  };
+  const matches = (f: SettingField): boolean => {
+    const q = query().toLowerCase();
+    return q === "" || f.label.includes(q) || f.help.toLowerCase().includes(q);
+  };
+  const stats = (): string => {
+    version();
+    const p = getProfile();
+    return `profile "${profileId()}": ${Object.keys(p.units).length} tracked units, ${p.sessions.length} sessions`;
+  };
+
+  return (
+    <div class="grid gap-6">
+      <div class="flex flex-wrap items-center gap-3">
+        <input
+          class="w-64"
+          placeholder="search settings..."
+          value={query()}
+          onInput={(e) => setQuery(e.currentTarget.value)}
+        />
+        <div class="grow"></div>
+        <Button
+          variant="button"
+          fa={{ icon: "fa-undo" }}
+          text="reset all settings"
+          onClick={() => {
+            resetSettings();
+            showSuccessNotification("Adaptive trainer settings reset");
+          }}
+        />
+      </div>
+      <For each={settingGroups}>
+        {(group) => (
+          <Show when={group.fields.some(matches)}>
+            <section>
+              <h3 class="flex items-center gap-2 text-2xl text-sub">
+                <Fa icon={group.icon as FaSolidIcon} fixedWidth />
+                {group.title}
+              </h3>
+              <div class="mb-2 text-sm text-sub">{group.description}</div>
+              <div class="grid divide-y divide-sub-alt">
+                <For each={group.fields.filter(matches)}>
+                  {(field) => <Field field={field} />}
+                </For>
+              </div>
+            </section>
+          </Show>
+        )}
+      </For>
+
+      <Card title="data" icon="fa-database">
+        <div class="grid gap-4">
+          <div class="text-sm text-sub">
+            {stats()}. Everything is stored in this browser only.
+            <Show when={listProfiles().length > 1}>
+              {" "}
+              Other profiles:{" "}
+              {listProfiles()
+                .filter((p) => p !== profileId())
+                .join(", ")}
+              .
+            </Show>
+          </div>
+          <div class="flex flex-wrap gap-3">
+            <Button
+              variant="button"
+              fa={{ icon: "fa-download" }}
+              text="export"
+              onClick={download}
+            />
+            <Button
+              variant="button"
+              fa={{ icon: "fa-copy" }}
+              text="copy export"
+              onClick={() => {
+                void navigator.clipboard
+                  .writeText(exportData())
+                  .then(() => showSuccessNotification("Copied"));
+              }}
+            />
+            <Button
+              variant="button"
+              danger={confirmReset()}
+              fa={{ icon: "fa-trash" }}
+              text={
+                confirmReset()
+                  ? "click again to erase this profile"
+                  : "reset profile"
+              }
+              onClick={() => {
+                if (!confirmReset()) {
+                  setConfirmReset(true);
+                  return;
+                }
+                resetProfile();
+                setConfirmReset(false);
+                showSuccessNotification("Adaptive profile erased");
+              }}
+            />
+          </div>
+          <textarea
+            class={cn("h-24 w-full text-sm")}
+            placeholder="paste an export here to import it (replaces the current profile and settings)"
+            value={importText()}
+            onInput={(e) => setImportText(e.currentTarget.value)}
+          ></textarea>
+          <div>
+            <Button
+              variant="button"
+              disabled={importText().trim() === ""}
+              fa={{ icon: "fa-upload" }}
+              text="import"
+              onClick={() => {
+                if (importData(importText())) {
+                  setImportText("");
+                  showSuccessNotification("Adaptive profile imported");
+                } else {
+                  showErrorNotification(
+                    "That is not a valid adaptive trainer export",
+                  );
+                }
+              }}
+            />
+          </div>
+        </div>
+      </Card>
+    </div>
+  );
+}
diff --git a/frontend/src/ts/components/pages/adaptive/UnitsTab.tsx b/frontend/src/ts/components/pages/adaptive/UnitsTab.tsx
new file mode 100644
index 0000000..0d7db55
--- /dev/null
+++ b/frontend/src/ts/components/pages/adaptive/UnitsTab.tsx
@@ -0,0 +1,246 @@
+// oxlint-disable monkeytype-rules/one-component-per-file
+import { createMemo, createSignal, For, JSXElement, Show } from "solid-js";
+
+import { Scored, UnitType } from "../../../adaptive/model";
+import { cn } from "../../../utils/cn";
+import { Button } from "../../common/Button";
+import { Empty, levelClass, Meter, msToWpm, pct, show } from "./shared";
+
+type SortKey =
+  | "weakness"
+  | "errorRate"
+  | "relLatency"
+  | "lostMs"
+  | "samples"
+  | "trend"
+  | "due";
+
+const sorters: Record<SortKey, (s: Scored) => number> = {
+  weakness: (s) => (s.level === "new" ? -1 : s.weakness),
+  errorRate: (s) => s.errorRate,
+  relLatency: (s) => s.relLatency,
+  lostMs: (s) => s.lostMs * s.samples,
+  samples: (s) => s.samples,
+  trend: (s) => s.trend,
+  due: (s) => s.components.forgetting,
+};
+
+const types: { id: UnitType; label: string }[] = [
+  { id: "k", label: "keys" },
+  { id: "b", label: "bigrams" },
+  { id: "t", label: "trigrams" },
+  { id: "s", label: "syllables" },
+  { id: "w", label: "words" },
+];
+
+function Th(props: {
+  label: string;
+  help: string;
+  sort?: SortKey;
+  current: SortKey;
+  onSort: (k: SortKey) => void;
+}): JSXElement {
+  return (
+    <th
+      class={cn("px-3 py-2 text-left font-normal whitespace-nowrap text-sub", {
+        "cursor-pointer hover:text-text": props.sort !== undefined,
+        "text-main": props.sort === props.current,
+      })}
+      aria-label={props.help}
+      data-balloon-pos="up"
+      data-balloon-length="medium"
+      onClick={() => props.sort !== undefined && props.onSort(props.sort)}
+    >
+      {props.label}
+      {props.sort === props.current ? " ▾" : ""}
+    </th>
+  );
+}
+
+export function UnitsTab(props: { scored: Scored[] }): JSXElement {
+  const [type, setType] = createSignal<UnitType>("b");
+  const [sort, setSort] = createSignal<SortKey>("weakness");
+  const [query, setQuery] = createSignal("");
+  const [limit, setLimit] = createSignal(40);
+  const [hideNew, setHideNew] = createSignal(true);
+
+  const rows = createMemo(() => {
+    const q = query().toLowerCase();
+    const key = sorters[sort()];
+    return props.scored
+      .filter(
+        (s) =>
+          s.type === type() &&
+          (!hideNew() || s.level !== "new") &&
+          (q === "" || s.text.includes(q)),
+      )
+      .sort((a, b) => key(b) - key(a));
+  });
+
+  return (
+    <div class="grid gap-4">
+      <div class="flex flex-wrap items-center gap-2">
+        <For each={types}>
+          {(t) => (
+            <Button
+              variant="button"
+              active={type() === t.id}
+              text={t.label}
+              onClick={() => {
+                setType(t.id);
+                setLimit(40);
+              }}
+            />
+          )}
+        </For>
+        <div class="grow"></div>
+        <Button
+          variant="button"
+          active={hideNew()}
+          text="hide low-data"
+          balloon={{
+            text: "Hide units with too few samples to judge",
+            position: "up",
+          }}
+          onClick={() => setHideNew(!hideNew())}
+        />
+        <input
+          class="w-40"
+          placeholder="filter..."
+          value={query()}
+          onInput={(e) => setQuery(e.currentTarget.value)}
+        />
+      </div>
+      <Show
+        when={rows().length > 0}
+        fallback={<Empty text="Nothing to show yet." />}
+      >
+        <div class="overflow-x-auto">
+          <table class="w-full border-collapse [&>tbody>tr:nth-child(odd)>td]:bg-sub-alt">
+            <thead>
+              <tr>
+                <Th
+                  label="unit"
+                  help="The key, sequence or word"
+                  current={sort()}
+                  onSort={setSort}
+                />
+                <Th
+                  label="level"
+                  help="Overall verdict"
+                  current={sort()}
+                  onSort={setSort}
+                />
+                <Th
+                  label="weakness"
+                  help="Combined weakness score (scoring model and weights from settings)"
+                  sort="weakness"
+                  current={sort()}
+                  onSort={setSort}
+                />
+                <Th
+                  label="errors"
+                  help="Estimated error rate (shrunk towards your average when data is thin)"
+                  sort="errorRate"
+                  current={sort()}
+                  onSort={setSort}
+                />
+                <Th
+                  label="speed"
+                  help="Speed through this unit, as wpm, and relative to your average for this level"
+                  sort="relLatency"
+                  current={sort()}
+                  onSort={setSort}
+                />
+                <Th
+                  label="time lost"
+                  help="Estimated total time lost on this unit versus your own average (slowness + errors x correction cost)"
+                  sort="lostMs"
+                  current={sort()}
+                  onSort={setSort}
+                />
+                <Th
+                  label="trend"
+                  help="Recent samples versus the longer run. Up = getting worse"
+                  sort="trend"
+                  current={sort()}
+                  onSort={setSort}
+                />
+                <Th
+                  label="review"
+                  help="Spaced repetition: how due this unit is, and its memory stability in days"
+                  sort="due"
+                  current={sort()}
+                  onSort={setSort}
+                />
+                <Th
+                  label="samples"
+                  help="How often you have typed it"
+                  sort="samples"
+                  current={sort()}
+                  onSort={setSort}
+                />
+              </tr>
+            </thead>
+            <tbody>
+              <For each={rows().slice(0, limit())}>
+                {(s) => (
+                  <tr>
+                    <td class="px-3 py-2 text-xl whitespace-pre text-text">
+                      {show(s.text)}
+                    </td>
+                    <td class={cn("px-3 py-2", levelClass[s.level])}>
+                      {s.level}
+                    </td>
+                    <td class="min-w-28 px-3 py-2">
+                      <Meter value={s.level === "new" ? 0 : s.weakness} />
+                    </td>
+                    <td class="px-3 py-2">{pct(s.errorRate)}</td>
+                    <td class="px-3 py-2 whitespace-nowrap">
+                      {Math.round(msToWpm(s.ms))} wpm{" "}
+                      <span class="text-sm text-sub">
+                        {s.relLatency >= 1 ? "+" : ""}
+                        {Math.round((s.relLatency - 1) * 100)}%
+                      </span>
+                    </td>
+                    <td class="px-3 py-2 whitespace-nowrap">
+                      {((Math.max(0, s.lostMs) * s.samples) / 1000).toFixed(1)}s{" "}
+                      <span class="text-sm text-sub">
+                        {Math.round(s.lostMs)}ms each
+                      </span>
+                    </td>
+                    <td
+                      class={cn("px-3 py-2", {
+                        "text-error": s.trend > 0.15,
+                        "text-main": s.trend < -0.15,
+                        "text-sub": Math.abs(s.trend) <= 0.15,
+                      })}
+                    >
+                      {s.trend > 0.15
+                        ? "▲ worse"
+                        : s.trend < -0.15
+                          ? "▼ better"
+                          : "–"}
+                    </td>
+                    <td class="px-3 py-2 whitespace-nowrap text-sub">
+                      {Math.round((1 - s.recall) * 100)}% due ·{" "}
+                      {s.stat.st.toFixed(1)}d
+                    </td>
+                    <td class="px-3 py-2 text-sub">{s.samples}</td>
+                  </tr>
+                )}
+              </For>
+            </tbody>
+          </table>
+        </div>
+        <Show when={rows().length > limit()}>
+          <Button
+            variant="button"
+            text={`show more (${rows().length - limit()} hidden)`}
+            onClick={() => setLimit(limit() + 100)}
+          />
+        </Show>
+      </Show>
+    </div>
+  );
+}
diff --git a/frontend/src/ts/components/pages/adaptive/shared.tsx b/frontend/src/ts/components/pages/adaptive/shared.tsx
new file mode 100644
index 0000000..e78ad5e
--- /dev/null
+++ b/frontend/src/ts/components/pages/adaptive/shared.tsx
@@ -0,0 +1,105 @@
+// oxlint-disable monkeytype-rules/one-component-per-file
+import { Accessor, createMemo, JSXElement, Show } from "solid-js";
+
+import { Level, Scored, scoreAll } from "../../../adaptive/model";
+import { getProfile, settings, version } from "../../../adaptive/session";
+import { FaSolidIcon } from "../../../types/font-awesome";
+import { cn } from "../../../utils/cn";
+import { Fa } from "../../common/Fa";
+
+/** Every unit scored with point estimates; recomputed when the profile changes. */
+export function createScored(): Accessor<Scored[]> {
+  const scored = createMemo(() => {
+    version();
+    return scoreAll(getProfile(), settings(), { now: Date.now() });
+  });
+  return scored;
+}
+
+export const levelClass: Record<Level, string> = {
+  new: "text-sub",
+  critical: "text-error",
+  weak: "text-error",
+  fair: "text-text",
+  good: "text-main",
+  mastered: "text-main",
+};
+
+export function Card(props: {
+  title?: string;
+  icon?: string;
+  class?: string;
+  children: JSXElement;
+}): JSXElement {
+  return (
+    <div class={cn("rounded bg-sub-alt p-4", props.class)}>
+      <Show when={props.title}>
+        <div class="mb-3 flex items-center gap-2 text-sub">
+          <Show when={props.icon}>
+            <Fa icon={props.icon as FaSolidIcon} fixedWidth />
+          </Show>
+          {props.title}
+        </div>
+      </Show>
+      {props.children}
+    </div>
+  );
+}
+
+export function StatTile(props: {
+  label: string;
+  value: string;
+  sub?: string;
+  help?: string;
+}): JSXElement {
+  return (
+    <div
+      class="rounded bg-sub-alt p-4"
+      aria-label={props.help}
+      data-balloon-pos="up"
+      data-balloon-length="large"
+    >
+      <div class="text-sm text-sub">{props.label}</div>
+      <div class="text-3xl leading-tight text-main">{props.value}</div>
+      <Show when={props.sub}>
+        <div class="text-xs text-sub">{props.sub}</div>
+      </Show>
+    </div>
+  );
+}
+
+/** A 0..1 meter. Heat blends from the sub colour to the error colour. */
+export function Meter(props: { value: number; class?: string }): JSXElement {
+  const pct = (): number =>
+    Math.round(Math.min(1, Math.max(0, props.value)) * 100);
+  return (
+    <div
+      class={cn("h-[0.5em] w-full overflow-hidden rounded bg-bg", props.class)}
+    >
+      <div
+        class="h-full rounded"
+        style={{
+          width: `${pct()}%`,
+          background: `color-mix(in srgb, var(--error-color) ${pct()}%, var(--main-color))`,
+        }}
+      ></div>
+    </div>
+  );
+}
+
+export function Empty(props: { text: string }): JSXElement {
+  return <div class="p-8 text-center text-sub">{props.text}</div>;
+}
+
+export function show(text: string): string {
+  return text.replace(/ /g, "␣");
+}
+
+export function pct(value: number, digits = 1): string {
+  return `${(value * 100).toFixed(digits)}%`;
+}
+
+/** ms per keystroke as words per minute (5 chars per word). */
+export function msToWpm(ms: number): number {
+  return ms > 0 ? 12000 / ms : 0;
+}
diff --git a/frontend/src/ts/components/pages/test/AdaptiveNotice.tsx b/frontend/src/ts/components/pages/test/AdaptiveNotice.tsx
new file mode 100644
index 0000000..739fd78
--- /dev/null
+++ b/frontend/src/ts/components/pages/test/AdaptiveNotice.tsx
@@ -0,0 +1,62 @@
+import { For, JSXElement, Show } from "solid-js";
+
+import { targetLabel } from "../../../adaptive/generate";
+import { activePlan, settings } from "../../../adaptive/session";
+import { presets } from "../../../adaptive/settings";
+import { stopTraining } from "../../../adaptive/start";
+import { isFocusMode } from "../../../states/test";
+import { cn } from "../../../utils/cn";
+import { Button } from "../../common/Button";
+import { Fa } from "../../common/Fa";
+
+/** Shown above the words during adaptive training: what this test targets. */
+export function AdaptiveNotice(): JSXElement {
+  return (
+    <Show when={activePlan()}>
+      {(plan) => (
+        <div
+          class={cn(
+            "flex flex-wrap items-center justify-center gap-x-3 gap-y-1 pt-3 text-sm text-sub transition-opacity duration-125",
+            { "pointer-events-none opacity-0": isFocusMode() },
+          )}
+        >
+          <span class="text-main">
+            <Fa icon="fa-brain" /> adaptive · {presets[settings().preset].label}
+          </span>
+          <Show
+            when={plan().targets.length > 0}
+            fallback={<span>collecting data, mostly normal words for now</span>}
+          >
+            <span>targets</span>
+            <For each={plan().targets.slice(0, 10)}>
+              {(t) => (
+                <span
+                  class="rounded bg-sub-alt px-2 py-0.5 whitespace-pre text-text"
+                  aria-label={t.reason}
+                  data-balloon-pos="down"
+                >
+                  {targetLabel(t)}
+                </span>
+              )}
+            </For>
+            <span>· {Math.round(plan().intensity * 100)}% intensity</span>
+          </Show>
+          <Button
+            variant="text"
+            class="p-0 text-sm"
+            fa={{ icon: "fa-times" }}
+            text="exit"
+            onClick={() => void stopTraining()}
+          />
+          <Button
+            variant="text"
+            class="p-0 text-sm"
+            fa={{ icon: "fa-chart-bar" }}
+            text="details"
+            to="/adaptive"
+          />
+        </div>
+      )}
+    </Show>
+  );
+}
diff --git a/frontend/src/ts/components/pages/test/TestPage.tsx b/frontend/src/ts/components/pages/test/TestPage.tsx
index eb0360a..1f9fa50 100644
--- a/frontend/src/ts/components/pages/test/TestPage.tsx
+++ b/frontend/src/ts/components/pages/test/TestPage.tsx
@@ -35,6 +35,7 @@ import * as Misc from "../../../utils/misc";
 import { canQuickRestart } from "../../../utils/quick-restart";
 import { Button } from "../../common/Button";
 import { LoadingCircle } from "../../common/LoadingCircle";
+import { AdaptiveNotice } from "./AdaptiveNotice";
 import { CapsWarning } from "./CapsWarning";
 import { CompositionDisplay } from "./CompositionDisplay";
 import { FunboxTimer } from "./FunboxTimer";
@@ -166,6 +167,7 @@ export function TestPage(): JSXElement {
     <>
       <div class="full-width">
         <TestConfig />
+        <AdaptiveNotice />
       </div>
 
       <div
diff --git a/frontend/src/ts/components/pages/test/result/ResultButtons.tsx b/frontend/src/ts/components/pages/test/result/ResultButtons.tsx
index 70bc9f6..13cbf32 100644
--- a/frontend/src/ts/components/pages/test/result/ResultButtons.tsx
+++ b/frontend/src/ts/components/pages/test/result/ResultButtons.tsx
@@ -1,6 +1,7 @@
 import { createKeyHold } from "@tanstack/solid-hotkeys";
 import { JSXElement, onMount, Show } from "solid-js";
 
+import { startTraining } from "../../../../adaptive/start";
 import { getConfig } from "../../../../config/store";
 import { getIsScreenshotting } from "../../../../states/core";
 import { showModal } from "../../../../states/modals";
@@ -63,6 +64,12 @@ export function ResultButtons(props: { glarses: boolean }): JSXElement {
             showModal("PractiseWords");
           }}
         />
+        <ResultButton
+          id="adaptiveTrainingButton"
+          text="Adaptive training"
+          fa={{ icon: "fa-brain" }}
+          onClick={() => void startTraining()}
+        />
         <Show when={!props.glarses}>
           <ResultButton
             id="showWordHistoryButton"
diff --git a/frontend/src/ts/constants/default-config.ts b/frontend/src/ts/constants/default-config.ts
index b2a43d4..24e4739 100644
--- a/frontend/src/ts/constants/default-config.ts
+++ b/frontend/src/ts/constants/default-config.ts
@@ -80,7 +80,7 @@ const obj: Config = {
   highlightMode: "letter",
   typedEffect: "keep",
   typingSpeedUnit: "wpm",
-  ads: "result",
+  ads: "off",
   hideExtraLetters: false,
   strictSpace: false,
   minAcc: "off",
diff --git a/frontend/src/ts/router/routes.ts b/frontend/src/ts/router/routes.ts
index 27af665..321a14d 100644
--- a/frontend/src/ts/router/routes.ts
+++ b/frontend/src/ts/router/routes.ts
@@ -17,6 +17,7 @@ import { isResultsReady, waitForResultsReady } from "../collections/results";
 import { UserDataLoadError } from "../utils/user-data-load-error";
 import { PageSwitcher } from "../components/core/PageSwitcher";
 import { AboutPage } from "../components/pages/AboutPage";
+import { AdaptivePage } from "../components/pages/adaptive/AdaptivePage";
 import { AccountSettingsPage } from "../components/pages/account-settings/AccountSettingsPage";
 import { AccountPage } from "../components/pages/account/AccountPage";
 import { FriendsPage } from "../components/pages/connections/FriendsPage";
@@ -63,6 +64,7 @@ export type PageName =
   | "loading"
   | "test"
   | "about"
+  | "adaptive"
   | "settings"
   | "account"
   | "login"
@@ -293,6 +295,13 @@ const about = createRoute({
   },
 });
 
+const adaptive = createRoute({
+  getParentRoute: () => userDataRoute,
+  path: "/adaptive",
+  staticData: { page: "adaptive" },
+  component: createRouterPage(AdaptivePage),
+});
+
 const settings = createRoute({
   getParentRoute: () => userDataRoute,
   path: "/settings",
@@ -414,6 +423,7 @@ export const routeTree = root.addChildren([
     test,
     leaderboards,
     about,
+    adaptive,
     settings,
     login,
     account,
diff --git a/frontend/src/ts/test/test-logic.ts b/frontend/src/ts/test/test-logic.ts
index 5b234a2..5ec1488 100644
--- a/frontend/src/ts/test/test-logic.ts
+++ b/frontend/src/ts/test/test-logic.ts
@@ -20,6 +20,7 @@ import {
 } from "../states/notifications";
 import * as CustomText from "./custom-text";
 import * as PractiseWords from "./practise-words";
+import * as AdaptiveSession from "../adaptive/session";
 import * as Funbox from "./funbox/funbox";
 import * as PaceCaret from "./pace-caret";
 import * as TestTimer from "./test-timer";
@@ -358,6 +359,9 @@ export async function restartTest(
     PractiseWords.resetBefore();
   }
 
+  // adaptive training: a restart builds the next test or leaves training
+  await AdaptiveSession.beforeRestart(options);
+
   // reset state
 
   resetTestState();
diff --git a/frontend/src/ts/test/words-generator.ts b/frontend/src/ts/test/words-generator.ts
index 48bbf83..9a5cf63 100644
--- a/frontend/src/ts/test/words-generator.ts
+++ b/frontend/src/ts/test/words-generator.ts
@@ -1,3 +1,4 @@
+import { blendWord } from "../adaptive/session";
 import { Config } from "../config/store";
 import { setConfig, setQuoteLengthAll, toggleFunbox } from "../config/setters";
 import * as CustomText from "./custom-text";
@@ -873,6 +874,8 @@ export async function getNextWord(
     } else if (isCurrentlyUsingFunboxSection) {
       randomWord = funboxSection.join(" ");
     } else {
+      // adaptive trainer: optionally swap in a word that hits weak spots
+      randomWord = blendWord(currentWordset.words, randomWord);
       let regenarationCount = 0; //infinite loop emergency stop button
       let firstAfterSplit = (randomWord.split(" ")[0] as string).toLowerCase();
       let firstAfterSplitLazy = applyLazyModeToWord(
PATCH
cp frontend/src/ts/constants/firebase-config-example.ts frontend/src/ts/constants/firebase-config.ts
cp frontend/src/ts/constants/firebase-config-example.ts frontend/src/ts/constants/firebase-config-live.ts
# keep the app from talking to monkeytype.com's servers; recaptcha value is Google's public test key
printf 'BACKEND_URL="http://localhost:5005"\nRECAPTCHA_SITE_KEY="6LeIxAcTAAAAAJcZVRqyHh71UMIEGNQ_MXjiZKhI"\n' > frontend/.env
pnpm install
echo
echo "Done. Run it with one of:"
echo "  cd monkeytype-local && pnpm dev-fe                              # hot-reload, for customizing (http://localhost:3000)"
echo "  cd monkeytype-local/frontend && npx vite build && pnpm start    # clean production build (http://localhost:3000)"

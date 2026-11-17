import { describe, expect, it } from "vitest";
import { extract, ingest, LogLike } from "../../src/ts/adaptive/analyze";
import { generate } from "../../src/ts/adaptive/generate";
import { qwertyGeometry, syllableSpans } from "../../src/ts/adaptive/geometry";
import { newProfile, scoreAll } from "../../src/ts/adaptive/model";
import { defaultSettings } from "../../src/ts/adaptive/settings";

function mulberry(seed: number): () => number {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const pool =
  "the of and to in is you that it he was for on are as with his they at be this have from or one had by word but not what all were we when your can said there use an each which she do how their if will up other about out many then them these so some her would make like him into time has look two more write go see number no way could people my than first water been call who oil its now find long down day did get come made may part quiet quick queen quite equal question require square this that there think thing both month north south earth mother father other together".split(
    " ",
  );

/** A typist who is slow on "th" and often hits "w" instead of "q". */
function simulate(words: string[], rng: () => number): LogLike {
  const events: LogLike["events"] = [];
  let ms = 0;
  const push = (data: Record<string, unknown>): void => {
    events.push({ type: "input", testMs: ms, data });
  };
  words.forEach((word, w) => {
    let input = "";
    for (let i = 0; i < word.length; i++) {
      const ch = word[i] as string;
      const slow = i > 0 && word[i - 1] === "t" && ch === "h";
      ms += (slow ? 260 : 110) + rng() * 30;
      if (ch === "q" && rng() < 0.4) {
        push({
          wordIndex: w,
          inputType: "insertText",
          data: "w",
          correct: false,
        });
        ms += 300;
        push({
          wordIndex: w,
          inputType: "deleteContentBackward",
          inputValue: input,
        });
        ms += 200;
      }
      push({ wordIndex: w, inputType: "insertText", data: ch, correct: true });
      input += ch;
    }
    ms += 120;
    push({
      wordIndex: w,
      inputType: "insertText",
      data: " ",
      correct: true,
      commitsWord: true,
    });
  });
  return { events, context: { targetWords: words.map((w) => `${w} `) } };
}

describe("adaptive engine", () => {
  it("splits syllables", () => {
    const parts = (w: string): string[] =>
      syllableSpans(w).map(([a, b]) => w.slice(a, b));
    expect(parts("together").join("")).toBe("together");
    expect(parts("together").length).toBeGreaterThan(1);
    expect(parts("the")).toEqual(["the"]);
  });

  it("finds planted weaknesses and targets them", () => {
    const rng = mulberry(7);
    const cfg = { ...defaultSettings, selection: "greedy" as const };
    const profile = newProfile(0);
    for (let test = 0; test < 12; test++) {
      const words = Array.from(
        { length: 60 },
        () => pool[Math.floor(rng() * pool.length)] as string,
      );
      const ex = extract(simulate(words, rng), cfg, qwertyGeometry);
      expect(ex.chars).toBeGreaterThan(100);
      ingest(profile, ex, cfg, test * 1000, {
        wpm: 80,
        acc: 96,
        mode: "words",
        adaptive: false,
      });
    }
    const scored = scoreAll(profile, cfg, { now: 12000 }).sort(
      (a, b) => b.score - a.score,
    );
    const top = scored.slice(0, 12).map((s) => s.id);

    expect(top).toContain("b:th");
    expect(top.some((id) => id.includes("q"))).toBe(true);
    expect(scored.find((s) => s.id === "k:q")?.level).toBe("critical");
    expect(profile.conf["q>w"]).toBeGreaterThan(1);
    expect(profile.g.errCost).toBeGreaterThan(200);

    const plan = generate({
      profile,
      cfg,
      pool,
      geo: qwertyGeometry,
      now: 12000,
      rng,
    });

    expect(plan.words.length).toBe(cfg.wordCount);
    const hits = plan.words.filter(
      (w) => w.includes("th") || w.includes("q"),
    ).length;
    const baseRate =
      pool.filter((w) => w.includes("th") || w.includes("q")).length /
      pool.length;
    expect(hits / plan.words.length).toBeGreaterThan(baseRate * 1.3);
  });

  it("generates plain words with an empty profile", () => {
    const plan = generate({
      profile: newProfile(0),
      cfg: defaultSettings,
      pool,
      geo: qwertyGeometry,
      now: 0,
    });
    expect(plan.informed).toBe(false);
    expect(plan.words.length).toBe(defaultSettings.wordCount);
  });
});

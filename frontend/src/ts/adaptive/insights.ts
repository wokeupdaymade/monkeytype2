// Plain-language findings derived from the profile, for the overview tab.

import { patternLabel } from "./generate";
import { errorTypes, ErrorType, Profile, Scored } from "./model";

export type Insight = {
  icon: string;
  title: string;
  text: string;
  /** which focus preset addresses it, if any */
  preset?: string;
};

export const errorTypeInfo: Record<ErrorType, { label: string; help: string }> =
  {
    substitution: {
      label: "substitution",
      help: "A different, unrelated key was pressed.",
    },
    adjacent: {
      label: "adjacent key",
      help: "The key next to the right one: finger placement drift.",
    },
    mirror: {
      label: "mirror",
      help: "The same finger on the other hand: hand confusion.",
    },
    case: {
      label: "capitalization",
      help: "Right letter, wrong case: shift timing.",
    },
    omission: { label: "omission", help: "A letter was skipped." },
    insertion: { label: "insertion", help: "An extra letter was typed." },
    doubling: { label: "doubling", help: "The previous letter was repeated." },
    transposition: {
      label: "transposition",
      help: "Two letters in swapped order: hands out of sync.",
    },
    "early-space": {
      label: "early space",
      help: "Space pressed before the word was finished.",
    },
    "missed-space": {
      label: "missed space",
      help: "Next word started without pressing space.",
    },
    other: { label: "other", help: "Unclassified." },
  };

export function errorBreakdown(
  profile: Profile,
): { type: ErrorType; count: number; share: number }[] {
  const total = errorTypes.reduce(
    (sum, t) => sum + (profile.errTypes[t] ?? 0),
    0,
  );
  return errorTypes
    .map((type) => {
      const count = profile.errTypes[type] ?? 0;
      return { type, count, share: total > 0 ? count / total : 0 };
    })
    .filter((x) => x.count > 0)
    .sort((a, b) => b.count - a.count);
}

/** Share of typing time that the measured weaknesses cost, at bigram level. */
export function potentialGain(scored: Scored[]): number {
  let lost = 0;
  let spent = 0;
  for (const s of scored) {
    if (s.type !== "b" || s.level === "new") continue;
    lost += Math.max(0, s.lostMs) * s.samples;
    spent += s.ms * s.samples;
  }
  return spent > 0 ? Math.min(0.6, lost / spent) : 0;
}

function recent<T>(arr: T[], n: number): T[] {
  return arr.slice(Math.max(0, arr.length - n));
}

function avg(values: number[]): number {
  return values.length === 0
    ? 0
    : values.reduce((a, b) => a + b, 0) / values.length;
}

export function buildInsights(profile: Profile, scored: Scored[]): Insight[] {
  const out: Insight[] = [];
  if (profile.g.tests === 0) return out;
  const sessions = recent(profile.sessions, 20);
  const usable = scored.filter((s) => s.level !== "new");

  // speed vs accuracy trade-off
  const acc = avg(sessions.map((s) => s.acc));
  const errCost = profile.g.errCost;
  const med = profile.g.medianDt;
  if (errCost > 0 && med > 0) {
    const errRate = 1 - acc / 100;
    const share = (errRate * errCost) / (med + errRate * errCost);
    if (share > 0.12) {
      out.push({
        icon: "fa-tachometer-alt",
        title: "errors are your biggest time sink",
        text: `Each error costs you about ${Math.round(errCost)} ms (${(errCost / med).toFixed(1)} keystrokes). At ${acc.toFixed(1)}% accuracy that is roughly ${Math.round(share * 100)}% of your typing time. Slowing down slightly would make you faster overall.`,
        preset: "accuracy",
      });
    } else if (acc > 98.5 && sessions.length >= 5) {
      out.push({
        icon: "fa-rocket",
        title: "room to push speed",
        text: `Accuracy is ${acc.toFixed(1)}% and errors cost little (${Math.round(share * 100)}% of your time). You can afford to type more aggressively.`,
        preset: "speed",
      });
    }
  }

  // weakest finger
  const fingers = usable
    .filter((s) => s.id.startsWith("c:finger-") && s.id !== "c:finger-8")
    .sort((a, b) => b.weakness - a.weakness);
  const worstFinger = fingers[0];
  if (worstFinger !== undefined && worstFinger.weakness > 0.12) {
    out.push({
      icon: "fa-hand-paper",
      title: `weakest finger: ${patternLabel(worstFinger.text)}`,
      text: `${(worstFinger.errorRate * 100).toFixed(1)}% errors and ${Math.abs(Math.round((worstFinger.relLatency - 1) * 100))}% ${worstFinger.relLatency >= 1 ? "slower" : "faster"} than your average finger.`,
      preset: "fingers",
    });
  }

  // motion patterns
  const patterns = usable
    .filter(
      (s) =>
        s.type === "c" &&
        [
          "sfb",
          "double",
          "rowjump",
          "roll-in",
          "roll-out",
          "alt",
          "stretch",
        ].includes(s.text),
    )
    .sort((a, b) => b.weakness - a.weakness);
  const worstPattern = patterns[0];
  if (worstPattern !== undefined && worstPattern.weakness > 0.15) {
    out.push({
      icon: "fa-exchange-alt",
      title: `hard motion: ${patternLabel(worstPattern.text)}`,
      text: `These take ${Math.round(worstPattern.ms)} ms on average, ${Math.abs(Math.round((worstPattern.relLatency - 1) * 100))}% ${worstPattern.relLatency >= 1 ? "above" : "below"} your norm, with ${(worstPattern.errorRate * 100).toFixed(1)}% errors.`,
      preset: "fingers",
    });
  }

  // dominant error type
  const breakdown = errorBreakdown(profile);
  const top = breakdown[0];
  if (top !== undefined && top.share > 0.3 && top.count >= 8) {
    const info = errorTypeInfo[top.type];
    out.push({
      icon: "fa-bug",
      title: `most common mistake: ${info.label}`,
      text: `${Math.round(top.share * 100)}% of your errors. ${info.help}`,
      preset:
        top.type === "substitution" || top.type === "adjacent"
          ? "confusions"
          : "accuracy",
    });
  }

  // confusion pair
  const pair = Object.entries(profile.conf).sort((a, b) => b[1] - a[1])[0];
  if (pair !== undefined && pair[1] >= 4) {
    const [exp, typed] = pair[0].split(">") as [string, string];
    out.push({
      icon: "fa-random",
      title: `you type "${typed}" for "${exp}"`,
      text: "Your most frequent letter confusion. The confusions preset mixes both letters into the same words.",
      preset: "confusions",
    });
  }

  // word starts
  const start = usable.find((s) => s.id === "c:word-start");
  if (start !== undefined && start.relLatency > 1.35) {
    out.push({
      icon: "fa-step-forward",
      title: "you pause between words",
      text: `The first letter of a word takes ${Math.round((start.relLatency - 1) * 100)}% longer than other keys. Reading one word ahead removes that stall.`,
    });
  }

  // fatigue
  const fatigue = avg(sessions.map((s) => s.fatigue));
  if (sessions.length >= 5 && fatigue > 1.06) {
    out.push({
      icon: "fa-battery-quarter",
      title: "you slow down during tests",
      text: `The last third of your tests is ${Math.round((fatigue - 1) * 100)}% slower than the first. Longer tests build the stamina to hold your pace.`,
    });
  }

  // post error slowdown
  const post = avg(sessions.map((s) => s.postError));
  if (sessions.length >= 5 && post > 1.25) {
    out.push({
      icon: "fa-undo",
      title: "errors throw you off rhythm",
      text: `After correcting a mistake your next keystrokes are ${Math.round((post - 1) * 100)}% slower than normal.`,
      preset: "consistency",
    });
  }

  // long vs short words
  const long = usable.find((s) => s.id === "c:len-long");
  const short = usable.find((s) => s.id === "c:len-short");
  if (
    long !== undefined &&
    short !== undefined &&
    long.errorRate > short.errorRate * 2.5
  ) {
    out.push({
      icon: "fa-text-width",
      title: "long words break down",
      text: `You make an error in ${(long.errorRate * 100).toFixed(0)}% of 7-9 letter words versus ${(short.errorRate * 100).toFixed(0)}% of short ones.`,
      preset: "syllables",
    });
  }

  // review backlog
  const due = usable.filter(
    (s) => s.type !== "c" && s.components.forgetting > 0.3,
  );
  if (due.length >= 5) {
    out.push({
      icon: "fa-history",
      title: `${due.length} past weaknesses are due for review`,
      text: "They improved earlier but have not come up for a while.",
      preset: "review",
    });
  }

  return out;
}

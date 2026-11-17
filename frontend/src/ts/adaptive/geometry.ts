// Keyboard geometry (which finger / hand / row types a character) and the
// motion classes of key pairs. Syllable splitting lives here too: both are
// "structure of the text" helpers shared by the analyzer and the generator.

export type KeyInfo = {
  row: number; // 0 = number row ... 3 = bottom row, 4 = space
  col: number;
  finger: number; // 0..3 left pinky..index, 4..7 right index..pinky, 8 thumb
  shifted: boolean;
};

export type Geometry = {
  name: string;
  keys: Map<string, KeyInfo>;
  rows: string[][]; // unshifted chars per row, for the heatmap
};

type LayoutLike = {
  type?: string;
  keys: Record<string, string[][]>;
};

const fingerByCol = [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7, 7];
// number row is shifted one to the left relative to the letter rows
const fingerByColRow0 = [0, 0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 7, 7, 7];

export const fingerNames = [
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

export function buildGeometry(name: string, layout: LayoutLike): Geometry {
  const keys = new Map<string, KeyInfo>();
  const rows: string[][] = [];
  const rowNames = ["row1", "row2", "row3", "row4"];
  rowNames.forEach((rowName, row) => {
    const defs = layout.keys[rowName] ?? [];
    // iso boards have an extra key left of the bottom row
    const offset = row === 3 && layout.type === "iso" ? -1 : 0;
    const chars: string[] = [];
    defs.forEach((pair, i) => {
      const col = Math.max(0, i + offset);
      const table = row === 0 ? fingerByColRow0 : fingerByCol;
      const finger = table[Math.min(col, table.length - 1)] as number;
      pair.forEach((ch, idx) => {
        if (ch === undefined || ch === "" || keys.has(ch)) return;
        keys.set(ch, { row, col, finger, shifted: idx === 1 });
      });
      chars.push(pair[0] ?? "");
    });
    rows.push(chars);
  });
  keys.set(" ", { row: 4, col: 5, finger: 8, shifted: false });
  return { name, keys, rows };
}

const qwertyRows: [string, string][] = [
  ["`1234567890-=", "~!@#$%^&*()_+"],
  ["qwertyuiop[]\\", "QWERTYUIOP{}|"],
  ["asdfghjkl;'", 'ASDFGHJKL:"'],
  ["zxcvbnm,./", "ZXCVBNM<>?"],
];

export const qwertyGeometry: Geometry = buildGeometry("qwerty", {
  type: "ansi",
  keys: Object.fromEntries(
    qwertyRows.map(([lower, upper], i) => [
      `row${i + 1}`,
      lower.split("").map((ch, j) => [ch, upper[j] as string]),
    ]),
  ),
});

export type PairClass =
  | "double"
  | "sfb"
  | "alt"
  | "roll-in"
  | "roll-out"
  | "rowjump"
  | "stretch";

/** Motion classes of typing `b` right after `a`. */
export function pairClasses(a: string, b: string, geo: Geometry): PairClass[] {
  const ka = geo.keys.get(a);
  const kb = geo.keys.get(b);
  if (ka === undefined || kb === undefined) return [];
  if (ka.finger === 8 || kb.finger === 8) return [];
  const out: PairClass[] = [];
  if (ka.row === kb.row && ka.col === kb.col) {
    out.push("double");
    return out;
  }
  const handA = ka.finger < 4 ? 0 : 1;
  const handB = kb.finger < 4 ? 0 : 1;
  if (handA !== handB) {
    out.push("alt");
    return out;
  }
  if (ka.finger === kb.finger) {
    out.push("sfb");
  } else {
    // towards the index finger = inward roll
    const inward = handA === 0 ? kb.finger > ka.finger : kb.finger < ka.finger;
    out.push(inward ? "roll-in" : "roll-out");
  }
  if (Math.abs(ka.row - kb.row) >= 2) out.push("rowjump");
  // index finger inner column reach
  if ((ka.col === 4 || ka.col === 5) !== (kb.col === 4 || kb.col === 5)) {
    if (ka.finger === kb.finger) out.push("stretch");
  }
  return out;
}

export function isAdjacent(a: string, b: string, geo: Geometry): boolean {
  const ka = geo.keys.get(a.toLowerCase());
  const kb = geo.keys.get(b.toLowerCase());
  if (ka === undefined || kb === undefined) return false;
  if (ka.row === kb.row && ka.col === kb.col) return false;
  return Math.abs(ka.row - kb.row) <= 1 && Math.abs(ka.col - kb.col) <= 1;
}

export function isMirror(a: string, b: string, geo: Geometry): boolean {
  const ka = geo.keys.get(a.toLowerCase());
  const kb = geo.keys.get(b.toLowerCase());
  if (ka === undefined || kb === undefined) return false;
  return ka.row === kb.row && ka.finger + kb.finger === 7 && ka.finger !== 8;
}

const vowels = "aeiouyäöüáéíóúàèìòùâêîôûãõåæøœ";
const syllableRe = new RegExp(
  `[^${vowels}]*[${vowels}]+(?:[^${vowels}]*$|[^${vowels}](?=[^${vowels}]))?`,
  "gi",
);
const letterRe = /^\p{L}+$/u;

/**
 * Heuristic syllable split for alphabetic scripts (onset + vowel group +
 * optional coda). Returns [start, end) spans. Words without vowels, or in
 * scripts the heuristic does not understand, come back as one span.
 */
export function syllableSpans(word: string): [number, number][] {
  if (word.length < 2 || !letterRe.test(word)) return [];
  const spans: [number, number][] = [];
  let covered = 0;
  for (const m of word.matchAll(syllableRe)) {
    const start = m.index;
    if (start !== covered) return [[0, word.length]];
    covered = start + m[0].length;
    spans.push([start, covered]);
  }
  if (covered !== word.length || spans.length === 0) return [[0, word.length]];
  return spans;
}

// Entry points used by the UI and the command line to start / stop training.

import { navigate } from "../router/navigate";
import { getRoutePage } from "../states/router";
import { restartTest } from "../test/test-logic";
import {
  endTraining,
  isTraining,
  prepareTraining,
  settings,
  updateSettings,
} from "./session";
import { FocusPreset } from "./settings";

export async function startTraining(preset?: FocusPreset): Promise<void> {
  if (preset !== undefined && preset !== settings().preset) {
    updateSettings({ ...settings(), preset });
  }
  if (!(await prepareTraining())) return;
  if (getRoutePage() === "test") {
    await restartTest();
  } else {
    await navigate({ to: "/" });
  }
}

export async function stopTraining(): Promise<void> {
  if (!isTraining()) return;
  endTraining();
  if (getRoutePage() === "test") await restartTest();
}

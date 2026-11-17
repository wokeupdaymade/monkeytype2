import { navigate } from "../../router/navigate";
import { isAuthenticated } from "../../states/core";
import { toggleFullscreen } from "../../utils/misc";
import { Command, withValidation } from "../types";
import { remoteValidation } from "../../utils/remote-validation";
import { UserNameWithoutFilterSchema } from "@monkeytype/schemas/users";
import Ape from "../../ape";

const commands: Command[] = [
  {
    id: "viewTypingPage",
    display: "View Typing Page",
    alias: "navigate go to start begin type test",
    fa: { icon: "fa-keyboard" },
    exec: (): void => {
      void navigate({ to: "/" });
    },
  },
  {
    id: "viewLeaderboards",
    display: "View Leaderboards",
    alias: "navigate go to",
    fa: { icon: "fa-crown" },
    exec: (): void => {
      void navigate({ to: "/leaderboards" });
    },
  },
  {
    id: "viewAbout",
    display: "View About Page",
    alias: "navigate go to",
    fa: { icon: "fa-info" },
    exec: (): void => {
      void navigate({ to: "/about" });
    },
  },
  {
    id: "viewAdaptive",
    display: "View Adaptive Trainer",
    alias: "navigate go to weakness analysis training practice",
    fa: { icon: "fa-brain" },
    exec: (): void => {
      void navigate({ to: "/adaptive" });
    },
  },
  {
    id: "startAdaptiveTraining",
    display: "Adaptive training: start",
    alias: "weakness practice train drill smart",
    fa: { icon: "fa-dumbbell" },
    exec: (): void => {
      void import("../../adaptive/start").then(async (m) => m.startTraining());
    },
  },
  {
    id: "stopAdaptiveTraining",
    display: "Adaptive training: stop",
    alias: "weakness practice train end leave",
    fa: { icon: "fa-stop" },
    exec: (): void => {
      void import("../../adaptive/start").then(async (m) => m.stopTraining());
    },
  },
  {
    id: "viewSettings",
    display: "View Settings Page",
    alias: "navigate go to",
    fa: { icon: "fa-cog" },
    exec: (): void => {
      void navigate({ to: "/settings" });
    },
  },

  {
    id: "viewAccount",
    display: "View Account Page",
    alias: "navigate go to stats",
    fa: { icon: "fa-user" },
    exec: (): void => {
      void navigate({ to: isAuthenticated() ? "/account" : "/login" });
    },
  },
  withValidation({
    id: "searchProfile",
    display: "Search for a profile",
    alias: "profile user search find lookup",
    fa: { icon: "fa-search" },
    input: true,
    validation: {
      schema: UserNameWithoutFilterSchema,
      debounceDelay: 1000,
      isValid: remoteValidation(
        async (name) => Ape.users.getProfile({ params: { uidOrName: name } }),
        {
          on4xx: () => "Unknown user",
        },
      ),
    },
    exec: ({ input }): void => {
      if (input === undefined) return;
      void navigate({
        to: "/profile/$uidOrName",
        params: { uidOrName: input },
      });
    },
  }),
  {
    id: "toggleFullscreen",
    display: "Toggle Fullscreen",
    fa: { icon: "fa-expand" },
    exec: (): void => {
      toggleFullscreen();
    },
  },
];

export default commands;

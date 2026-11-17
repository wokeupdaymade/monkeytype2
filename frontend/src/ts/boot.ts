import { initAdaptive } from "./adaptive/session";
import { applyEngineSettings } from "./anim";
import * as ServerConfiguration from "./ape/server-configuration";
import { loadFromLocalStorage } from "./config/lifecycle";
import * as Cookies from "./cookies";
import { authPromise, initFirebase } from "./firebase";
import { initConnection } from "./states/connection";
import { setAppReady, setVersion } from "./states/core";
import { isDevEnvironment } from "./utils/env";
import { fetchLatestVersion } from "./utils/version";

/** App startup work that doesn't touch the DOM: starts the config load and
 * Firebase, then waits for both before the app is ready. Call once, right after
 * render. */
export async function boot(): Promise<void> {
  initConnection();
  initAdaptive();
  // LOCAL: no backend, so PSAs / server-status banners are disabled

  applyEngineSettings();
  const configLoaded = loadFromLocalStorage();
  void fetchLatestVersion().then((data) => {
    if (data === null) return;
    setVersion(data);
  });

  const accepted = Cookies.getAcceptedCookies();
  // LOCAL: no cookie popup; nothing is accepted, so analytics/sentry stay off
  void initFirebase().then(() => {
    if (accepted !== null) {
      Cookies.activateWhatsAccepted();
    }
  });

  await configLoaded;
  await authPromise;

  setAppReady(true);

  void ServerConfiguration.sync();

  registerServiceWorker();
}

function registerServiceWorker(): void {
  if (isDevEnvironment()) {
    void navigator.serviceWorker
      .getRegistrations()
      .then(function (registrations) {
        for (const registration of registrations) {
          void registration.unregister();
        }
      });
  } else {
    if ("serviceWorker" in navigator) {
      window.addEventListener("load", () => {
        navigator.serviceWorker
          .register("/sw.js", { scope: "/" })
          .then((registration) => {
            console.log(
              "ServiceWorker registration successful with scope: ",
              registration.scope,
            );
          })
          .catch((error: unknown) => {
            console.error("ServiceWorker registration failed: ", error);
          });
      });
    }
  }
}

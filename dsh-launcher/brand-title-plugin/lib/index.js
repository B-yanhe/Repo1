/**
 * Host half of dsh-brand-title.
 *
 * The browser title is pinned by the client half; this row exists only so
 * dsh-client-modules sees a Loader entry for the package and serves its
 * `./client` bundle. It deliberately has no host-side behaviour, no injected
 * services, and no imports, so it can never fail the profile boot.
 */

export const name = 'dsh-brand-title';

export function apply() {
  // Intentionally empty.
}

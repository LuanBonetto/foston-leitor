package br.com.luan.leitor;

/**
 * Decides whether the reader should open by itself.
 *
 * Times come from SystemClock.elapsedRealtime(), which restarts at zero on
 * every boot. If the stored launch time is later than "now", the tablet has
 * rebooted since, so the reader opens once more.
 */
final class AutoLaunchPolicy {
    static final long NEVER = -1L;

    private AutoLaunchPolicy() {
    }

    static boolean shouldAutoLaunch(long nowElapsedMs, long lastLaunchElapsedMs) {
        return lastLaunchElapsedMs == NEVER || nowElapsedMs < lastLaunchElapsedMs;
    }
}

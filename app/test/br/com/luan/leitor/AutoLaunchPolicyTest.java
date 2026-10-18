package br.com.luan.leitor;

/** Plain-Java test runner; no JUnit so it runs with javac/java only. */
public final class AutoLaunchPolicyTest {
    private static int failures = 0;

    private static void check(String name, boolean actual, boolean expected) {
        if (actual == expected) {
            System.out.println("ok   " + name);
        } else {
            failures++;
            System.out.println("FAIL " + name + ": esperado " + expected + ", veio " + actual);
        }
    }

    public static void main(String[] args) {
        check("primeira vez desde a instalação abre",
                AutoLaunchPolicy.shouldAutoLaunch(30_000L, AutoLaunchPolicy.NEVER), true);
        check("mesmo boot, depois de abrir, não abre de novo",
                AutoLaunchPolicy.shouldAutoLaunch(90_000L, 30_000L), false);
        check("mesmo boot, mesmo instante, não abre de novo",
                AutoLaunchPolicy.shouldAutoLaunch(30_000L, 30_000L), false);
        check("novo boot (relógio desde o boot voltou) abre",
                AutoLaunchPolicy.shouldAutoLaunch(20_000L, 3_600_000L), true);
        if (failures > 0) {
            System.exit(1);
        }
    }
}

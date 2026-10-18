package br.com.luan.leitor;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;
import android.widget.TextView;

/** Home screen: opens KOReader once per boot, then offers "Ler" and "Configurações". */
public class MainActivity extends Activity {
    static final String KOREADER_PACKAGE = "org.koreader.launcher";
    private static final String PREFS = "leitor";
    private static final String KEY_LAST_LAUNCH = "last_launch_elapsed_ms";

    private TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.main);
        status = (TextView) findViewById(R.id.status);

        findViewById(R.id.read).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                openReader();
            }
        });
        findViewById(R.id.settings).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(Settings.ACTION_SETTINGS));
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        long now = SystemClock.elapsedRealtime();
        long last = prefs.getLong(KEY_LAST_LAUNCH, AutoLaunchPolicy.NEVER);
        if (AutoLaunchPolicy.shouldAutoLaunch(now, last)) {
            prefs.edit().putLong(KEY_LAST_LAUNCH, now).commit();
            openReader();
        }
    }

    @Override
    public void onBackPressed() {
        // Home screen: Back has nowhere to go.
    }

    private void openReader() {
        Intent intent = getPackageManager().getLaunchIntentForPackage(KOREADER_PACKAGE);
        if (intent == null) {
            status.setText(R.string.koreader_missing);
            status.setVisibility(View.VISIBLE);
            return;
        }
        status.setVisibility(View.GONE);
        startActivity(intent);
    }
}

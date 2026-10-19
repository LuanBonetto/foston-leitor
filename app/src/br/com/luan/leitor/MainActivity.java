package br.com.luan.leitor;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.provider.Settings;
import android.view.View;
import android.widget.TextView;

/** Home screen: offers "Ler" (opens KOReader) and "Configurações". */
public class MainActivity extends Activity {
    static final String KOREADER_PACKAGE = "org.koreader.launcher";

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

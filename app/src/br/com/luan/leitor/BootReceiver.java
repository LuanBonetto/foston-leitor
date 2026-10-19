package br.com.luan.leitor;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Opens KOReader once per boot, right after the framework finishes starting up. */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Intent launch = context.getPackageManager()
                .getLaunchIntentForPackage(MainActivity.KOREADER_PACKAGE);
        if (launch == null) {
            return;
        }
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(launch);
    }
}

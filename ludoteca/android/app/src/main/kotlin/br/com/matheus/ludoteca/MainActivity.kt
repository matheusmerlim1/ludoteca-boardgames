package br.com.matheus.ludoteca

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // Canal usado pelo UpdateService: versão instalada e instalação do APK
    // baixado da página de releases.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ludoteca/atualizacao")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "versao" -> result.success(
                        packageManager.getPackageInfo(packageName, 0).versionName
                    )
                    "instalar" -> {
                        val caminho = call.argument<String>("caminho")
                        if (caminho == null) {
                            result.error("sem_arquivo", "Caminho do APK não informado", null)
                            return@setMethodCallHandler
                        }
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.atualizacao", File(caminho)
                        )
                        val intent = Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_ACTIVITY_NEW_TASK
                            )
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

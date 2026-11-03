package com.multilocal.control;

import android.content.Context;
import android.content.SharedPreferences;

/** Dónde está el servidor. Cambia según quién lo lance (la IP de ZeroTier del host). */
final class Ajustes {
    String host;
    int puertoMc, puertoSsh;
    String carpeta;
    private final SharedPreferences p;

    Ajustes(Context c) {
        p = c.getSharedPreferences("ajustes", Context.MODE_PRIVATE);
        host = p.getString("host", "172.25.96.6");
        puertoMc = p.getInt("puertoMc", 60068);
        puertoSsh = p.getInt("puertoSsh", 8022);
        carpeta = p.getString("carpeta", "~/Multilocal-craft");
    }

    void guardar() {
        p.edit().putString("host", host).putInt("puertoMc", puertoMc).putInt("puertoSsh", puertoSsh)
                .putString("carpeta", carpeta).apply();
    }

    /** Comando de shell que ejecuta scripts/panel.py en la carpeta del repo del host. */
    String panel(String args) {
        String dir = carpeta.startsWith("~/") ? "$HOME/" + carpeta.substring(2) : carpeta;
        return "cd \"" + dir.replace("\"", "") + "\" && P=$(command -v python3 || command -v python) && \"$P\" scripts/panel.py " + args;
    }
}

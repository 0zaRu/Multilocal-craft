package com.multilocal.control;

import android.content.Context;
import android.content.SharedPreferences;

/** Dónde está el servidor. Cambia según quién lo lance (la IP de ZeroTier del host). */
final class Ajustes {
    // Host por defecto: el servidor "central" (Debian, Docker) en la red ZeroTier de Minecraft
    static final String HOST_CENTRAL = "192.0.2.1";
    static final int SSH_CENTRAL = 22;
    static final String USUARIO_CENTRAL = "alberto";
    static final String CARPETA_CENTRAL = "~/minecraft/Multilocal-craft";
    // Host anterior (móvil con Termux): si la app lo tiene guardado, se pasa a central una sola vez
    private static final String HOST_MOVIL_ANTIGUO = "192.0.2.1";

    String host;
    int puertoMc, puertoSsh;
    String usuario;
    String carpeta;
    private final SharedPreferences p;

    Ajustes(Context c) {
        p = c.getSharedPreferences("ajustes", Context.MODE_PRIVATE);
        if (!p.getBoolean("migrado_central", false)) {
            SharedPreferences.Editor e = p.edit().putBoolean("migrado_central", true);
            if (HOST_MOVIL_ANTIGUO.equals(p.getString("host", HOST_MOVIL_ANTIGUO))) {
                e.remove("host").remove("puertoSsh").remove("usuario").remove("carpeta");
            }
            e.apply();
        }
        host = p.getString("host", HOST_CENTRAL);
        puertoMc = p.getInt("puertoMc", 60068);
        puertoSsh = p.getInt("puertoSsh", SSH_CENTRAL);
        // En Termux el usuario da igual; en un Linux normal tiene que ser el dueño del repo
        usuario = p.getString("usuario", USUARIO_CENTRAL);
        carpeta = p.getString("carpeta", CARPETA_CENTRAL);
    }

    void guardar() {
        p.edit().putString("host", host).putInt("puertoMc", puertoMc).putInt("puertoSsh", puertoSsh)
                .putString("usuario", usuario).putString("carpeta", carpeta).apply();
    }

    /** Comando de shell que ejecuta scripts/panel.py en la carpeta del repo del host. */
    String panel(String args) {
        String dir = carpeta.startsWith("~/") ? "$HOME/" + carpeta.substring(2) : carpeta;
        return "cd \"" + dir.replace("\"", "") + "\" && P=$(command -v python3 || command -v python) && \"$P\" scripts/panel.py " + args;
    }
}

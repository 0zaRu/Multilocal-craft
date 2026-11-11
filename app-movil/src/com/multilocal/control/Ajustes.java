package com.multilocal.control;

import android.content.Context;
import android.content.SharedPreferences;

/** Dónde está el servidor. Cambia según quién lo lance (la IP de ZeroTier del host). */
final class Ajustes {
    // Host: la IP de ZeroTier del anfitrión. No va en el repo: se pone en Ajustes (⚙) la primera vez.
    static final String HOST_CENTRAL = "";
    static final int SSH_CENTRAL = 22;
    static final String USUARIO_CENTRAL = "alberto";
    static final String CARPETA_CENTRAL = "~/minecraft/Multilocal-craft";

    String host;
    int puertoMc, puertoSsh;
    String usuario;
    String carpeta;
    private final SharedPreferences p;

    Ajustes(Context c) {
        p = c.getSharedPreferences("ajustes", Context.MODE_PRIVATE);
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

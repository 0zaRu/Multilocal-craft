package com.multilocal.control;

import android.content.Context;

import com.jcraft.jsch.ChannelExec;
import com.jcraft.jsch.JSch;
import com.jcraft.jsch.JSchException;
import com.jcraft.jsch.KeyPair;
import com.jcraft.jsch.Session;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/**
 * SSH al dispositivo que hace de servidor (sshd de Termux, puerto 8022). La sesión solo
 * existe mientras la app está abierta; cada petición es un comando corto (scripts/panel.py).
 */
final class Conexion {
    private final File privada, publica, conocidos;
    private Session sesion;
    private String destino = "";

    Conexion(Context c) {
        privada = new File(c.getFilesDir(), "clave");
        publica = new File(c.getFilesDir(), "clave.pub");
        conocidos = new File(c.getFilesDir(), "known_hosts");
    }

    /** Clave pública de esta app (se crea la primera vez). */
    synchronized String clavePublica() throws Exception {
        if (!privada.exists() || !publica.exists()) {
            KeyPair kp = KeyPair.genKeyPair(new JSch(), KeyPair.RSA, 3072);
            try (FileOutputStream a = new FileOutputStream(privada); FileOutputStream b = new FileOutputStream(publica)) {
                kp.writePrivateKey(a);
                kp.writePublicKey(b, "multilocal-app");
            }
            kp.dispose();
        }
        return new String(Files.readAllBytes(publica.toPath()), StandardCharsets.UTF_8).trim();
    }

    private synchronized Session sesion(Ajustes a) throws Exception {
        String d = a.host + ":" + a.puertoSsh;
        if (sesion != null && sesion.isConnected() && d.equals(destino)) return sesion;
        cerrar();
        clavePublica();
        JSch j = new JSch();
        if (!conocidos.exists()) conocidos.createNewFile();
        j.setKnownHosts(conocidos.getPath());
        j.addIdentity(privada.getPath());
        Session s = j.getSession("termux", a.host, a.puertoSsh);
        // La primera vez se guarda la clave del host (la red ZeroTier ya va cifrada y es privada)
        s.setConfig("StrictHostKeyChecking", "no");
        s.setConfig("PreferredAuthentications", "publickey");
        s.setServerAliveInterval(15000);
        s.setTimeout(20000);
        s.connect(8000);
        sesion = s;
        destino = d;
        return s;
    }

    /** Ejecuta un comando en el host y devuelve su salida; lanza excepción si falla. */
    String ejecutar(Ajustes a, String comando, String entrada, int timeoutMs) throws Exception {
        ChannelExec ch = (ChannelExec) sesion(a).openChannel("exec");
        try {
            ch.setCommand(comando);
            ch.setInputStream(entrada == null ? null : new ByteArrayInputStream(entrada.getBytes(StandardCharsets.UTF_8)));
            ByteArrayOutputStream err = new ByteArrayOutputStream();
            ch.setErrStream(err);
            InputStream in = ch.getInputStream();
            ch.connect(8000);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[16384];
            long fin = System.currentTimeMillis() + timeoutMs;
            while (true) {
                while (in.available() > 0) {
                    int n = in.read(buf);
                    if (n < 0) break;
                    out.write(buf, 0, n);
                }
                if (ch.isClosed() && in.available() == 0) break;
                if (System.currentTimeMillis() > fin) throw new IOException("el host tarda demasiado en responder");
                Thread.sleep(40);
            }
            String s = out.toString("UTF-8");            if (ch.getExitStatus() != 0 && s.trim().isEmpty())
                throw new IOException(err.toString("UTF-8").trim().isEmpty() ? "error " + ch.getExitStatus() : err.toString("UTF-8").trim());
            return s;
        } finally {
            ch.disconnect();
        }
    }

    synchronized void cerrar() {
        if (sesion != null) sesion.disconnect();
        sesion = null;
    }

    /** Explica en castellano los fallos típicos de conexión. */
    static String explicar(Throwable e) {
        String m = e.getMessage() == null ? e.toString() : e.getMessage();
        if (e instanceof JSchException && m.contains("Auth fail"))
            return "Este móvil aún no está autorizado en el host. Ve a Ajustes → «Copiar comando» y pégalo en Termux del host.";
        if (m.contains("ECONNREFUSED") || m.contains("Connection refused"))
            return "El host no acepta SSH: el servidor está apagado o se lanzó sin openssh.";
        if (m.contains("timeout") || m.contains("timed out") || m.contains("EHOSTUNREACH") || m.contains("ENETUNREACH"))
            return "No se llega al host. ¿ZeroTier encendido en los dos móviles y la IP correcta?";
        return m;
    }
}

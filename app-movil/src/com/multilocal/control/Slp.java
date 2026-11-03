package com.multilocal.control;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/** "Server List Ping" de Minecraft: lo mismo que ve la lista de servidores del juego (sin SSH). */
final class Slp {
    static final class Resultado {
        boolean ok;
        String version = "", motd = "", error = "";
        int online, max;
        long ms;
        final List<String> muestra = new ArrayList<>();
    }

    private Slp() {}

    static Resultado ping(String host, int puerto) {
        Resultado r = new Resultado();
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress(host, puerto), 4000);
            s.setSoTimeout(5000);
            OutputStream out = s.getOutputStream();
            DataInputStream in = new DataInputStream(s.getInputStream());

            ByteArrayOutputStream hs = new ByteArrayOutputStream();
            varint(hs, 0x00);                 // paquete Handshake
            varint(hs, -1);                   // versión de protocolo: la que sea
            cadena(hs, host);
            hs.write((puerto >> 8) & 0xFF);
            hs.write(puerto & 0xFF);
            varint(hs, 1);                    // siguiente estado: status
            paquete(out, hs.toByteArray());
            long t0 = System.nanoTime();
            paquete(out, new byte[]{0x00});   // Status Request

            leerVarint(in);                   // longitud
            int id = leerVarint(in);
            if (id != 0x00) throw new IOException("respuesta inesperada");
            byte[] json = new byte[leerVarint(in)];
            in.readFully(json);
            r.ms = (System.nanoTime() - t0) / 1_000_000;

            JSONObject o = new JSONObject(new String(json, StandardCharsets.UTF_8));
            r.version = limpiar(o.optJSONObject("version") != null ? o.optJSONObject("version").optString("name") : "");
            JSONObject p = o.optJSONObject("players");
            if (p != null) {
                r.online = p.optInt("online");
                r.max = p.optInt("max");
                JSONArray m = p.optJSONArray("sample");
                if (m != null)
                    for (int i = 0; i < m.length(); i++) r.muestra.add(m.getJSONObject(i).optString("name"));
            }
            r.motd = limpiar(texto(o.opt("description"))).trim();
            r.ok = true;
        } catch (Exception e) {
            r.error = e.getMessage() == null ? e.toString() : e.getMessage();
        }
        return r;
    }

    /** El MOTD puede venir como texto o como componente JSON con "extra". */
    private static String texto(Object d) {
        if (d == null) return "";
        if (d instanceof String) return (String) d;
        StringBuilder sb = new StringBuilder();
        if (d instanceof JSONObject) {
            JSONObject o = (JSONObject) d;
            sb.append(o.optString("text"));
            JSONArray extra = o.optJSONArray("extra");
            if (extra != null) for (int i = 0; i < extra.length(); i++) sb.append(texto(extra.opt(i)));
        } else if (d instanceof JSONArray) {
            JSONArray a = (JSONArray) d;
            for (int i = 0; i < a.length(); i++) sb.append(texto(a.opt(i)));
        }
        return sb.toString();
    }

    static String limpiar(String s) { return s.replaceAll("§.", ""); }

    private static void paquete(OutputStream out, byte[] datos) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        varint(b, datos.length);
        b.write(datos);
        out.write(b.toByteArray());
        out.flush();
    }

    private static void varint(ByteArrayOutputStream b, int v) {
        do {
            int x = v & 0x7F;
            v >>>= 7;
            b.write(v != 0 ? x | 0x80 : x);
        } while (v != 0);
    }

    private static void cadena(ByteArrayOutputStream b, String s) throws IOException {
        byte[] d = s.getBytes(StandardCharsets.UTF_8);
        varint(b, d.length);
        b.write(d);
    }

    private static int leerVarint(DataInputStream in) throws IOException {
        int v = 0, n = 0, x;
        do {
            x = in.readUnsignedByte();
            v |= (x & 0x7F) << (7 * n++);
            if (n > 5) throw new IOException("VarInt demasiado largo");
        } while ((x & 0x80) != 0);
        return v;
    }
}

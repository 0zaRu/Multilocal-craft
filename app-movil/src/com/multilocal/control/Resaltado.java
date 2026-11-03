package com.multilocal.control;

import android.text.SpannableString;
import android.text.SpannableStringBuilder;
import android.text.Spanned;
import android.text.style.ForegroundColorSpan;
import android.text.style.StyleSpan;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Colores para las líneas del log del servidor, como un editor resalta el código. */
final class Resaltado {
    private static final int HORA = 0xFF6E6E6E, TEXTO = 0xFFC8C8C8, PLUGIN = 0xFF55CDFC, NUMERO = 0xFFD7A6FF,
            CADENA = 0xFF9BE89B, JUGADOR = 0xFF7CFC7C, COMANDO = Estilo.AQUA;
    private static final Pattern LINEA = Pattern.compile("^\\[(\\d\\d:\\d\\d:\\d\\d)\\] \\[[^\\]]*/(\\w+)\\]: ?(.*)$");
    private static final Pattern ETIQUETA = Pattern.compile("^\\[[^\\]]{1,40}\\]");
    private static final Pattern CHAT = Pattern.compile("^(?:\\[Not Secure\\] )?<([^>]+)> ");
    private static final Pattern ORDEN = Pattern.compile("^(\\S+) issued server command: (/.*)$");
    private static final Pattern ENTRA_SALE = Pattern.compile("^(\\S+) (joined|left) the game");
    private static final Pattern CADENAS = Pattern.compile("'[^']*'|\"[^\"]*\"");
    private static final Pattern NUMEROS = Pattern.compile("(?<![\\w.])-?\\d+(?:[.,]\\d+)*(?:%|ms|s)?(?![\\w])");
    // Lo que deja en el log la propia app al pedir el estado por RCON (tps, mspt, list): no se muestra
    private static final Pattern RUIDO_RCON = Pattern.compile("Thread RCON Client|Rcon issued server command: /(list|tps|mspt)\\b");

    private Resaltado() {}

    /** Línea del log resaltada, o null si es ruido de la propia app. */
    static CharSequence linea(String l) {
        Matcher m = LINEA.matcher(l);
        if (!m.matches()) return pintar(l, 0xFFBBBBBB);   // continuación (trazas de error...)
        String nivel = m.group(2), msg = m.group(3);
        if (RUIDO_RCON.matcher(msg).find()) return null;
        SpannableStringBuilder sb = new SpannableStringBuilder();
        sb.append(pintar(m.group(1) + " ", HORA));
        if ("WARN".equals(nivel)) sb.append(pintar("⚠ " + msg, Estilo.ORO));
        else if ("ERROR".equals(nivel) || "FATAL".equals(nivel)) sb.append(negrita(pintar("✖ " + msg, Estilo.ROJO)));
        else sb.append(mensaje(msg));
        return sb;
    }

    private static CharSequence mensaje(String msg) {
        SpannableStringBuilder sb = new SpannableStringBuilder(msg);
        color(sb, 0, msg.length(), TEXTO);
        Matcher m;
        if ((m = ENTRA_SALE.matcher(msg)).find()) {
            color(sb, 0, msg.length(), Estilo.AMARILLO);
            return sb;
        }
        if ((m = CHAT.matcher(msg)).find()) {
            color(sb, m.start(1), m.end(1), JUGADOR);
            color(sb, m.end(), msg.length(), Estilo.BLANCO);
            return sb;
        }
        if (msg.startsWith("[Not Secure] [Rcon]") || msg.startsWith("[Rcon]") || msg.startsWith("[Server]")) {
            color(sb, 0, msg.length(), Estilo.BLANCO);
            return sb;
        }
        if (msg.startsWith("Done (")) {
            color(sb, 0, msg.length(), Estilo.VERDE);
            return sb;
        }
        for (m = NUMEROS.matcher(msg); m.find(); ) color(sb, m.start(), m.end(), NUMERO);
        for (m = CADENAS.matcher(msg); m.find(); ) color(sb, m.start(), m.end(), CADENA);
        if ((m = ETIQUETA.matcher(msg)).find()) color(sb, 0, m.end(), PLUGIN);
        if ((m = ORDEN.matcher(msg)).find()) {
            color(sb, m.start(1), m.end(1), JUGADOR);
            color(sb, m.start(2), m.end(2), COMANDO);
        }
        return sb;
    }

    static CharSequence pintar(String s, int col) {
        SpannableString sp = new SpannableString(s);
        sp.setSpan(new ForegroundColorSpan(col), 0, s.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        return sp;
    }

    private static CharSequence negrita(CharSequence s) {
        SpannableString sp = new SpannableString(s);
        sp.setSpan(new StyleSpan(android.graphics.Typeface.BOLD), 0, s.length(), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        return sp;
    }

    private static void color(SpannableStringBuilder sb, int a, int b, int col) {
        sb.setSpan(new ForegroundColorSpan(col), a, b, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
    }
}

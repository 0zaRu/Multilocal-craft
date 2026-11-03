package com.multilocal.control;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.text.SpannableStringBuilder;
import android.view.Gravity;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final int ESTADO_MS = 10000, LOG_MS = 2000, MAX_LINEAS = 1500;
    private static final int P_ESTADO = 0, P_JUGADORES = 1, P_CONSOLA = 2, P_VERSIONES = 3;

    private Ajustes aj;
    private Conexion con;
    private final Handler ui = new Handler(Looper.getMainLooper());
    private final ExecutorService hiloEstado = Executors.newSingleThreadExecutor();
    private final ExecutorService hiloLog = Executors.newSingleThreadExecutor();
    private final ExecutorService hiloVersiones = Executors.newSingleThreadExecutor();
    private boolean activa, pidiendoEstado, pidiendoLog, pidiendoVersiones;
    private String esperandoOp;          // operación lanzada desde aquí cuyo resultado falta por enseñar
    private long horaPulsadoOp;
    private volatile long posLog = -1;
    private int pestana;

    private TextView lineaEstado, consola;
    private Button[] pestanas;
    private View[] vistas;
    private LinearLayout cajaEstado, cajaJugadores, cajaVersiones;
    private ScrollView scrollConsola;
    private EditText entrada;
    private Button botonCopia, botonReiniciar;
    private final ArrayDeque<CharSequence> lineas = new ArrayDeque<>();

    private JSONObject estado, versiones;
    private Slp.Resultado slp;
    private String errorSsh, errorLog;

    // ------------------------------------------------------------------ interfaz

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        aj = new Ajustes(this);
        con = new Conexion(this);
        getWindow().setStatusBarColor(0xFF140E0A);
        getWindow().setNavigationBarColor(0xFF140E0A);

        LinearLayout raiz = new LinearLayout(this);
        raiz.setOrientation(LinearLayout.VERTICAL);
        raiz.setBackground(Estilo.tierra(this));
        int m = px(12);
        raiz.setPadding(m, m, m, m);

        // Título y ajustes
        LinearLayout cabecera = new LinearLayout(this);
        cabecera.setGravity(Gravity.CENTER_VERTICAL);
        LinearLayout titulos = columna();
        titulos.addView(Estilo.texto(this, "MULTILOCAL-CRAFT", 22, Estilo.AMARILLO));
        lineaEstado = Estilo.texto(this, "Conectando…", 13, Estilo.GRIS);
        titulos.addView(lineaEstado);
        cabecera.addView(titulos, new LinearLayout.LayoutParams(0, -2, 1));
        Button engranaje = Estilo.boton(this, "⚙");
        engranaje.setTextSize(20);
        engranaje.setOnClickListener(v -> abrirAjustes());
        cabecera.addView(engranaje, new LinearLayout.LayoutParams(px(52), px(48)));
        raiz.addView(cabecera);

        // Pestañas
        LinearLayout barra = new LinearLayout(this);
        String[] nombres = {"Estado", "Jugadores", "Consola", "Versiones"};
        pestanas = new Button[nombres.length];
        for (int i = 0; i < nombres.length; i++) {
            final int n = i;
            pestanas[i] = Estilo.boton(this, nombres[i]);
            pestanas[i].setTextSize(12);
            pestanas[i].setPadding(px(2), px(6), px(2), px(8));
            pestanas[i].setOnClickListener(v -> elegir(n));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, px(44), 1);
            lp.setMargins(i == 0 ? 0 : px(3), px(10), 0, px(8));
            barra.addView(pestanas[i], lp);
        }
        raiz.addView(barra);

        // Contenido
        FrameLayout contenido = new FrameLayout(this);
        contenido.setBackground(Estilo.panel(this));
        contenido.setPadding(px(12), px(10), px(12), px(10));
        cajaEstado = columna();
        cajaJugadores = columna();
        cajaVersiones = columna();
        vistas = new View[]{desplazable(cajaEstado), desplazable(cajaJugadores), crearConsola(), desplazable(cajaVersiones)};
        for (View v : vistas) contenido.addView(v, new FrameLayout.LayoutParams(-1, -1));
        raiz.addView(contenido, new LinearLayout.LayoutParams(-1, 0, 1));

        // Copia de seguridad y reinicio
        LinearLayout acciones = new LinearLayout(this);
        botonCopia = Estilo.boton(this, "Copia de seguridad");
        botonCopia.setOnClickListener(v -> confirmar("copia", "Copia de seguridad",
                "Se guarda el mundo sin apagar el servidor y se sube a GitHub (rama " + rama() + ").", "Hacer copia"));
        botonReiniciar = Estilo.boton(this, "Reiniciar");
        botonReiniciar.setOnClickListener(v -> confirmar("reiniciar", "Reiniciar el servidor",
                "Se guarda el mundo, se apaga y se vuelve a lanzar. Los jugadores conectados se desconectan durante un minuto más o menos.",
                "Reiniciar"));
        LinearLayout.LayoutParams lc = new LinearLayout.LayoutParams(0, px(56), 3);
        LinearLayout.LayoutParams lr = new LinearLayout.LayoutParams(0, px(56), 2);
        lr.leftMargin = px(6);
        acciones.addView(botonCopia, lc);
        acciones.addView(botonReiniciar, lr);
        LinearLayout.LayoutParams la = new LinearLayout.LayoutParams(-1, -2);
        la.topMargin = px(10);
        raiz.addView(acciones, la);

        setContentView(raiz);
        elegir(P_ESTADO);
        pintar();
    }

    @Override protected void onResume() {
        super.onResume();
        activa = true;
        ui.post(tickEstado);
        ui.post(tickLog);
    }

    @Override protected void onPause() {
        super.onPause();
        // Nada queda en marcha en el host: se corta la sesión SSH al salir de la app
        activa = false;
        ui.removeCallbacks(tickEstado);
        ui.removeCallbacks(tickLog);
        hiloLog.execute(con::cerrar);
    }

    @Override protected void onDestroy() {
        super.onDestroy();
        hiloEstado.shutdownNow();
        hiloLog.shutdownNow();
        hiloVersiones.shutdownNow();
    }

    private void elegir(int n) {
        pestana = n;
        for (int i = 0; i < vistas.length; i++) {
            vistas[i].setVisibility(i == n ? View.VISIBLE : View.GONE);
            pestanas[i].setSelected(i == n);
        }
        if (n == P_CONSOLA) { ui.removeCallbacks(tickLog); ui.post(tickLog); }
        if (n == P_VERSIONES && versiones == null) comprobarVersiones();
    }

    private View crearConsola() {
        LinearLayout c = columna();
        consola = new TextView(this);
        consola.setTypeface(Typeface.MONOSPACE);
        consola.setTextSize(11);
        consola.setTextColor(0xFFDDDDDD);
        consola.setTextIsSelectable(true);
        scrollConsola = new ScrollView(this);
        scrollConsola.addView(consola);
        c.addView(scrollConsola, new LinearLayout.LayoutParams(-1, 0, 1));

        LinearLayout fila = new LinearLayout(this);
        fila.setGravity(Gravity.CENTER_VERTICAL);
        entrada = new EditText(this);
        entrada.setHint("comando (sin /)");
        entrada.setHintTextColor(Estilo.GRIS_OSCURO);
        entrada.setTextColor(Estilo.BLANCO);
        entrada.setTypeface(Estilo.FUENTE);
        entrada.setTextSize(14);
        entrada.setSingleLine(true);
        entrada.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        entrada.setImeOptions(EditorInfo.IME_ACTION_SEND);
        GradientDrawable caja = new GradientDrawable();
        caja.setColor(0xFF000000);
        caja.setStroke(px(2), 0xFFA0A0A0);
        entrada.setBackground(caja);
        entrada.setPadding(px(8), px(8), px(8), px(8));
        entrada.setOnEditorActionListener((v, accion, ev) -> { enviarComando(); return true; });
        fila.addView(entrada, new LinearLayout.LayoutParams(0, px(46), 1));
        Button enviar = Estilo.boton(this, "Enviar");
        enviar.setOnClickListener(v -> enviarComando());
        LinearLayout.LayoutParams le = new LinearLayout.LayoutParams(-2, px(46));
        le.leftMargin = px(6);
        fila.addView(enviar, le);
        LinearLayout.LayoutParams lf = new LinearLayout.LayoutParams(-1, -2);
        lf.topMargin = px(8);
        c.addView(fila, lf);
        return c;
    }

    // ------------------------------------------------------------------ peticiones

    private final Runnable tickEstado = new Runnable() {
        @Override public void run() {
            if (!activa) return;
            if (!pidiendoEstado) {
                pidiendoEstado = true;
                hiloEstado.execute(() -> {
                    Slp.Resultado r = Slp.ping(aj.host, aj.puertoMc);
                    JSONObject e = null;
                    String err = null;
                    try {
                        e = new JSONObject(con.ejecutar(aj, aj.panel("estado"), null, 30000));
                    } catch (Throwable ex) {
                        err = Conexion.explicar(ex);
                        con.cerrar();
                    }
                    final JSONObject fe = e;
                    final String ferr = err;
                    ui.post(() -> {
                        pidiendoEstado = false;
                        slp = r;
                        estado = fe;
                        errorSsh = ferr;
                        pintar();
                    });
                });
            }
            ui.postDelayed(this, esperandoOp != null ? 3000 : ESTADO_MS);
        }
    };

    private final Runnable tickLog = new Runnable() {
        @Override public void run() {
            ui.removeCallbacks(this);
            if (!activa || pestana != P_CONSOLA) return;
            if (!pidiendoLog) {
                pidiendoLog = true;
                hiloLog.execute(() -> {
                    JSONObject o = null;
                    String err = null;
                    try {
                        o = new JSONObject(con.ejecutar(aj, aj.panel("log --desde " + posLog), null, 20000));
                    } catch (Throwable ex) {
                        err = Conexion.explicar(ex);
                    }
                    final JSONObject fo = o;
                    final String ferr = err;
                    ui.post(() -> {
                        pidiendoLog = false;
                        if (fo != null) {
                            if (fo.optBoolean("reinicio")) { lineas.clear(); consola.setText(""); }
                            posLog = fo.optLong("pos", -1);
                            for (String l : fo.optString("texto").split("\n")) {
                                if (l.trim().isEmpty()) continue;
                                CharSequence r = Resaltado.linea(l);
                                if (r != null) anadirLinea(r);
                            }
                            errorLog = null;
                        } else if (ferr != null && !ferr.equals(errorLog)) {
                            errorLog = ferr;
                            anadirLinea(Resaltado.pintar("(sin conexión) " + ferr, Estilo.ROJO));
                        }
                    });
                });
            }
            ui.postDelayed(this, LOG_MS);
        }
    };

    private void enviarComando() {
        final String c = entrada.getText().toString().trim();
        if (c.isEmpty()) return;
        entrada.setText("");
        anadirLinea(Resaltado.pintar("> " + c, Estilo.AQUA));
        hiloLog.execute(() -> {
            String r;
            try {
                r = con.ejecutar(aj, aj.panel("comando"), c, 20000).trim();
            } catch (Throwable ex) {
                r = "(error) " + Conexion.explicar(ex);
            }
            final String fr = r;
            ui.post(() -> {
                if (!fr.isEmpty()) for (String l : fr.split("\n")) anadirLinea(Resaltado.pintar(l, Estilo.BLANCO));
                ui.postDelayed(tickLog, 600);
            });
        });
    }

    private void comprobarVersiones() {
        if (pidiendoVersiones) return;
        pidiendoVersiones = true;
        pintarVersiones();
        hiloVersiones.execute(() -> {
            JSONObject v;
            try {
                v = new JSONObject(con.ejecutar(aj, aj.panel("versiones"), null, 240000));
            } catch (Throwable ex) {
                v = new JSONObject();
                try { v.put("error", Conexion.explicar(ex)); } catch (Exception ignorada) { }
            }
            final JSONObject fv = v;
            ui.post(() -> {
                pidiendoVersiones = false;
                versiones = fv;
                pintarVersiones();
            });
        });
    }

    // ------------------------------------------------------------------ operaciones (copia, reinicio, actualización)

    private void confirmar(String op, String titulo, String texto, String boton) {
        new AlertDialog.Builder(this)
                .setTitle(titulo)
                .setMessage(texto + "\n\n¿Seguir?")
                .setPositiveButton(boton, (d, w) -> lanzar(op))
                .setNegativeButton("Cancelar", null)
                .show();
    }

    private void lanzar(String op) {
        horaPulsadoOp = estado != null ? estado.optLong("hora") : 0;
        esperandoOp = op;
        pintar();
        hiloLog.execute(() -> {
            String r;
            boolean ok = true;
            try {
                r = con.ejecutar(aj, aj.panel("lanzar " + op), null, 20000).trim();
            } catch (Throwable ex) {
                r = Conexion.explicar(ex);
                ok = false;
            }
            final String fr = r;
            final boolean fok = ok;
            ui.post(() -> {
                Toast.makeText(this, fr, Toast.LENGTH_LONG).show();
                if (!fok) esperandoOp = null;
                pintar();
                ui.removeCallbacks(tickEstado);
                ui.postDelayed(tickEstado, 1500);
            });
        });
    }

    private void mostrarResultado(String op, JSONArray log) {
        StringBuilder sb = new StringBuilder();
        if (log != null) for (int i = 0; i < log.length(); i++) sb.append(log.optString(i)).append('\n');
        String t = sb.toString();
        boolean ok = "copia".equals(op) ? t.contains("COPIA SUBIDA")
                : !t.contains("NO SE PUDO") && !t.contains("NO HA ARRANCADO") && !t.contains("CANCELADA") && t.contains("EN MARCHA");
        String titulo = "copia".equals(op) ? (ok ? "Copia subida a GitHub" : "La copia no se pudo subir")
                : "reiniciar".equals(op) ? (ok ? "Servidor reiniciado" : "El reinicio ha fallado")
                : (ok ? "Actualización terminada" : "La actualización no se ha podido aplicar");
        TextView tv = new TextView(this);
        tv.setText(t.trim());
        tv.setTypeface(Typeface.MONOSPACE);
        tv.setTextSize(11);
        tv.setPadding(px(20), px(10), px(20), 0);
        ScrollView s = new ScrollView(this);
        s.addView(tv);
        new AlertDialog.Builder(this).setTitle(titulo).setView(s).setPositiveButton("Vale", null).show();
        if ("actualizar".equals(op)) { versiones = null; if (pestana == P_VERSIONES) comprobarVersiones(); }
    }

    // ------------------------------------------------------------------ pintar el estado

    private void pintar() {
        JSONObject srv = estado != null ? estado.optJSONObject("servidor") : null;
        JSONObject disp = estado != null ? estado.optJSONObject("dispositivo") : null;
        JSONObject git = estado != null ? estado.optJSONObject("git") : null;
        JSONObject op = estado != null ? estado.optJSONObject("operacion") : null;
        JSONObject proc = srv != null ? srv.optJSONObject("proceso") : null;
        boolean opEnCurso = op != null && op.optBoolean("en_curso");

        if (slp == null) {
            lineaEstado.setText("Conectando con " + aj.host + "…");
            lineaEstado.setTextColor(Estilo.GRIS);
        } else if (slp.ok) {
            lineaEstado.setText("● En línea · " + slp.version + " · " + slp.ms + " ms");
            lineaEstado.setTextColor(Estilo.VERDE);
        } else if (esperandoOp != null && !"copia".equals(esperandoOp)) {
            lineaEstado.setText("● Reiniciando…");
            lineaEstado.setTextColor(Estilo.ORO);
        } else {
            lineaEstado.setText("● Sin respuesta en " + aj.host);
            lineaEstado.setTextColor(Estilo.ROJO);
        }
        Estilo.sombra(lineaEstado, lineaEstado.getCurrentTextColor());

        LinearLayout c = cajaEstado;
        c.removeAllViews();

        // --- Operación en curso (o esperando a que el host vuelva tras un reinicio)
        if (opEnCurso || esperandoOp != null) {
            String tipo = opEnCurso ? op.optString("tipo") : esperandoOp;
            seccion(c, "copia".equals(tipo) ? "COPIA EN CURSO…" : "reiniciar".equals(tipo) ? "REINICIANDO…" : "ACTUALIZANDO…");
            JSONArray log = op != null ? op.optJSONArray("log") : null;
            if (opEnCurso && log != null)
                for (int i = Math.max(0, log.length() - 6); i < log.length(); i++)
                    c.addView(Estilo.texto(this, log.optString(i), 11, Estilo.AQUA));
            else if (errorSsh != null)
                c.addView(Estilo.texto(this, "El servidor se está relanzando; la conexión vuelve sola.", 12, Estilo.ORO));
        }

        seccion(c, "SERVIDOR");
        if (slp != null && slp.ok) {
            fila(c, "Estado", "En línea", Estilo.VERDE);
            fila(c, "Versión", slp.version, Estilo.BLANCO);
            if (!slp.motd.isEmpty()) fila(c, "MOTD", slp.motd, Estilo.BLANCO);
            fila(c, "Jugadores", slp.online + " / " + slp.max, slp.online > 0 ? Estilo.VERDE : Estilo.BLANCO);
        } else if (srv != null && srv.optBoolean("activo")) {
            fila(c, "Estado", "Arrancando…", Estilo.ORO);
        } else {
            fila(c, "Estado", slp == null ? "…" : "Apagado o sin respuesta", slp == null ? Estilo.GRIS : Estilo.ROJO);
        }
        if (srv != null) {
            JSONArray tps = srv.optJSONArray("tps");
            if (tps != null && tps.length() > 0) {
                // Leaf da 5s, 1m, 5m y 15m; el color va por el del último minuto
                JSONArray periodos = srv.optJSONArray("tps_periodos");
                StringBuilder et = new StringBuilder("TPS ");
                int iMin = 0;
                for (int i = 0; periodos != null && i < periodos.length(); i++) {
                    et.append(i > 0 ? "·" : "").append(periodos.optString(i));
                    if ("1m".equals(periodos.optString(i))) iMin = i;
                }
                double t = tps.optDouble(Math.min(iMin, tps.length() - 1));
                int col = t >= 19.5 ? Estilo.VERDE : t >= 15 ? Estilo.ORO : Estilo.ROJO;
                StringBuilder sb = new StringBuilder();
                for (int i = 0; i < tps.length(); i++) sb.append(i > 0 ? " · " : "").append(fmt1(tps.optDouble(i)));
                fila(c, et.toString(), sb.toString(), col);
                barra(c, (float) (t / 20), col);
            }
            JSONObject ms = srv.optJSONObject("mspt");
            if (ms != null) {
                double v = ms.optDouble("media");
                int col = v <= 40 ? Estilo.VERDE : v <= 50 ? Estilo.ORO : Estilo.ROJO;
                fila(c, "MSPT (5 s)", fmt1(v) + " ms · máx " + fmt1(ms.optDouble("max")), col);
                barra(c, (float) (v / 50), col);
            }
        }
        if (proc != null) {
            if (proc.has("cpu")) fila(c, "CPU del servidor", fmt1(proc.optDouble("cpu")) + " % de " + proc.optInt("nucleos") + " núcleos", Estilo.BLANCO);
            if (proc.has("ram_mb")) {
                int usada = proc.optInt("ram_mb"), max = proc.optInt("xmx_mb");
                // La RAM del proceso incluye más que el heap (-Xmx), así que puede pasar de él
                fila(c, "RAM del servidor", gb(usada) + (max > 0 ? " (heap máx. " + gb(max) + ")" : ""), Estilo.BLANCO);
            }
            if (proc.has("encendido_s")) fila(c, "Encendido hace", duracion(proc.optLong("encendido_s")), Estilo.BLANCO);
        }

        seccion(c, "MÓVIL HOST");
        fila(c, "IP", aj.host, Estilo.BLANCO);
        if (errorSsh != null && esperandoOp == null) {
            TextView t = Estilo.texto(this, errorSsh, 13, Estilo.ROJO);
            t.setPadding(0, px(4), 0, px(4));
            c.addView(t);
        }
        if (disp != null) {
            String modelo = disp.optString("modelo");
            if (disp.has("android")) modelo += " · Android " + disp.optString("android");
            else if (disp.has("sistema")) modelo += " · " + disp.optString("sistema");
            fila(c, "Dispositivo", modelo, Estilo.BLANCO);
            JSONObject bat = disp.optJSONObject("bateria");
            if (bat != null && bat.has("porcentaje")) {
                int p = bat.optInt("porcentaje");
                String est = bat.optString("estado");
                String txt = p + " %" + ("CHARGING".equals(est) ? " · cargando" : "FULL".equals(est) ? " · llena" : "")
                        + (bat.has("temperatura") ? " · " + fmt1(bat.optDouble("temperatura")) + " °C" : "");
                int col = p > 50 ? Estilo.VERDE : p > 20 ? Estilo.ORO : Estilo.ROJO;
                fila(c, "Batería", txt, col);
                barra(c, p / 100f, col);
            }
            if (disp.has("temp_cpu")) {
                double t = disp.optDouble("temp_cpu");
                fila(c, "Temperatura CPU", fmt1(t) + " °C", t < 45 ? Estilo.VERDE : t < 60 ? Estilo.ORO : Estilo.ROJO);
            }
            if (disp.has("ram_total_mb")) {
                int tot = disp.optInt("ram_total_mb"), libre = disp.optInt("ram_libre_mb");
                fila(c, "RAM libre", gb(libre) + " de " + gb(tot), libre > tot / 5 ? Estilo.BLANCO : Estilo.ORO);
                barra(c, 1 - libre / (float) Math.max(1, tot), Estilo.AQUA);
            }
            if (disp.has("disco_libre_gb"))
                fila(c, "Almacenamiento", fmt1(disp.optDouble("disco_libre_gb")) + " GB libres de " + fmt1(disp.optDouble("disco_total_gb")) + " GB", Estilo.BLANCO);
            JSONArray carga = disp.optJSONArray("carga");
            if (carga != null) fila(c, "Carga 1·5·15 min", fmt1(carga.optDouble(0)) + " · " + fmt1(carga.optDouble(1)) + " · " + fmt1(carga.optDouble(2)), Estilo.BLANCO);
        }

        if (git != null) {
            seccion(c, "COPIAS EN GITHUB");
            long ahora = estado.optLong("hora");
            fila(c, "Rama", git.optString("rama"), Estilo.BLANCO);
            JSONObject ult = git.optJSONObject("ultimo_commit");
            if (ult != null) {
                fila(c, "Último commit", "hace " + duracion(ahora - ult.optLong("fecha")), Estilo.BLANCO);
                TextView t = Estilo.texto(this, ult.optString("mensaje"), 12, Estilo.GRIS);
                t.setPadding(0, 0, 0, px(4));
                c.addView(t);
            }
            if (git.has("sin_subir")) {
                int n = git.optInt("sin_subir");
                fila(c, "Sin subir", n == 0 ? "nada" : n + (n == 1 ? " commit" : " commits"), n == 0 ? Estilo.VERDE : Estilo.ORO);
            }
            if (op != null && op.has("log") && !opEnCurso) {
                JSONArray log = op.optJSONArray("log");
                String ultima = log != null && log.length() > 0 ? log.optString(log.length() - 1) : "";
                String tipo = op.optString("tipo");
                String nombre = "copia".equals(tipo) ? "Última copia" : "reiniciar".equals(tipo) ? "Último reinicio" : "Última actualización";
                boolean mal = ultima.contains("NO SE PUDO") || ultima.contains("NO HA") || ultima.contains("CANCELADA");
                fila(c, nombre, "hace " + duracion(ahora - op.optLong("fecha")), mal ? Estilo.ROJO : Estilo.BLANCO);
                if (!ultima.isEmpty()) c.addView(Estilo.texto(this, ultima, 12, mal ? Estilo.ROJO : Estilo.VERDE));
            }
        }

        // --- Botones y aviso al acabar una operación
        boolean libre = estado != null && !opEnCurso && esperandoOp == null;
        Estilo.activar(botonCopia, libre);
        Estilo.activar(botonReiniciar, libre);
        if (esperandoOp != null && op != null && !opEnCurso && esperandoOp.equals(op.optString("tipo"))
                && op.optLong("fecha") >= horaPulsadoOp) {
            String hecha = esperandoOp;
            esperandoOp = null;
            mostrarResultado(hecha, op.optJSONArray("log"));
            Estilo.activar(botonCopia, true);
            Estilo.activar(botonReiniciar, true);
        }

        pintarJugadores(srv);
        pintarVersiones();
    }

    private void pintarJugadores(JSONObject srv) {
        LinearLayout c = cajaJugadores;
        c.removeAllViews();
        List<String> nombres = new ArrayList<>();
        JSONArray js = srv != null ? srv.optJSONArray("jugadores") : null;
        if (js != null) for (int i = 0; i < js.length(); i++) nombres.add(js.optString(i));
        else if (slp != null && slp.ok) nombres.addAll(slp.muestra);
        int online = slp != null && slp.ok ? slp.online : srv != null ? srv.optInt("online") : 0;
        int max = slp != null && slp.ok ? slp.max : srv != null ? srv.optInt("max") : 0;
        seccion(c, "CONECTADOS: " + online + " / " + max);
        if (nombres.isEmpty()) {
            c.addView(Estilo.texto(this, slp != null && slp.ok ? "No hay nadie conectado." : "El servidor no responde.", 14, Estilo.GRIS));
            return;
        }
        for (String n : nombres) {
            LinearLayout f = new LinearLayout(this);
            f.setGravity(Gravity.CENTER_VERTICAL);
            f.setPadding(0, px(5), 0, px(5));
            ImageView cara = new ImageView(this);
            cara.setImageDrawable(Estilo.cara(this, n));
            f.addView(cara, new LinearLayout.LayoutParams(px(32), px(32)));
            boolean bedrock = n.startsWith(".");   // prefijo de Floodgate (plugins/floodgate/config.yml)
            TextView t = Estilo.texto(this, bedrock ? n.substring(1) : n, 16, Estilo.BLANCO);
            t.setPadding(px(12), 0, 0, 0);
            f.addView(t, new LinearLayout.LayoutParams(0, -2, 1));
            f.addView(Estilo.texto(this, bedrock ? "Bedrock" : "Java", 12, bedrock ? Estilo.AQUA : Estilo.GRIS));
            c.addView(f);
        }
    }

    /** Lo mismo que scripts/actualizar --check, en pantalla, con el botón para actualizar. */
    private void pintarVersiones() {
        LinearLayout c = cajaVersiones;
        c.removeAllViews();
        JSONObject v = versiones;
        if (v == null || pidiendoVersiones) {
            seccion(c, "VERSIONES");
            c.addView(Estilo.texto(this, pidiendoVersiones ? "Comprobando versiones en el host…\n(tarda unos segundos)" : "Sin comprobar.", 13, Estilo.GRIS));
            if (!pidiendoVersiones) botonVersiones(c, "Comprobar", true, x -> comprobarVersiones());
            return;
        }
        if (v.has("error") && !v.has("instalado")) {
            seccion(c, "VERSIONES");
            c.addView(Estilo.texto(this, v.optString("error"), 13, Estilo.ROJO));
            botonVersiones(c, "Volver a comprobar", true, x -> comprobarVersiones());
            return;
        }
        String srvNombre = v.optString("servidor", "Servidor");
        JSONObject inst = v.optJSONObject("instalado"), ult = v.optJSONObject("ultima"), obj = v.optJSONObject("objetivo");
        JSONArray bloq = v.optJSONArray("bloqueadas");

        seccion(c, "VERSIONES");
        if (inst != null) fila(c, "Instalada", srvNombre + " " + inst.optString("version") + " · build " + inst.optInt("build"), Estilo.BLANCO);
        if (ult != null) {
            boolean nueva = inst != null && !ult.optString("version").equals(inst.optString("version"));
            fila(c, "Última publicada", ult.optString("version") + " · build " + ult.optInt("build"), nueva ? Estilo.ORO : Estilo.VERDE);
        }
        if (obj != null) {
            boolean igual = inst != null && obj.optString("version").equals(inst.optString("version"));
            fila(c, "Máxima con todos los plugins", obj.optString("version") + " · build " + obj.optInt("build"), igual ? Estilo.BLANCO : Estilo.VERDE);
        } else {
            fila(c, "Máxima con todos los plugins", "ninguna más nueva", Estilo.ROJO);
        }
        if (v.has("error")) c.addView(Estilo.texto(this, v.optString("error"), 12, Estilo.ROJO));

        if (bloq != null && bloq.length() > 0) {
            seccion(c, "MÁS NUEVAS, TODAVÍA NO");
            for (int i = 0; i < bloq.length(); i++) {
                JSONObject b = bloq.optJSONObject(i);
                c.addView(Estilo.texto(this, "Minecraft " + b.optString("version") + " (build " + b.optInt("build") + ")", 14, Estilo.ORO));
                JSONArray ps = b.optJSONArray("plugins");
                for (int j = 0; ps != null && j < ps.length(); j++) {
                    JSONObject p = ps.optJSONObject(j);
                    TextView t = Estilo.texto(this, "  ✖ " + p.optString("nombre") + " — " + p.optString("nota"), 12, Estilo.ROJO);
                    c.addView(t);
                }
            }
        }

        JSONArray plugins = v.optJSONArray("plugins");
        if (plugins != null && plugins.length() > 0) {
            seccion(c, "PLUGINS" + (obj != null ? " PARA " + obj.optString("version") : ""));
            if (v.optBoolean("servidor_cambia")) fila(c, srvNombre, "build " + (inst != null ? inst.optInt("build") : 0) + " → " + (obj != null ? obj.optInt("build") : 0), Estilo.ORO);
            for (int i = 0; i < plugins.length(); i++) {
                JSONObject p = plugins.optJSONObject(i);
                String est = p.optString("estado");
                boolean igual = est.startsWith("igual");
                fila(c, p.optString("nombre"), igual ? p.optString("instalado") : p.optString("instalado") + " → " + p.optString("nuevo"),
                        igual ? Estilo.VERDE : est.contains("dev") ? Estilo.AQUA : Estilo.ORO);
            }
        }

        int cambios = v.optInt("cambios");
        c.addView(Estilo.texto(this, cambios == 0 ? "\nTodo está al día." : "\n" + cambios + (cambios == 1 ? " cambio" : " cambios") + " por aplicar.",
                13, cambios == 0 ? Estilo.VERDE : Estilo.AMARILLO));
        boolean libre = estado != null && esperandoOp == null && !(estado.optJSONObject("operacion") != null && estado.optJSONObject("operacion").optBoolean("en_curso"));
        botonVersiones(c, "Actualizar servidor", cambios > 0 && libre, x -> {
            boolean mundo = obj != null && inst != null && !obj.optString("version").equals(inst.optString("version"));
            confirmar("actualizar", "Actualizar el servidor",
                    "1. Copia de seguridad del mundo (y subida a GitHub).\n2. Se apaga el servidor.\n3. Se instala " + srvNombre + " "
                            + (obj != null ? obj.optString("version") + " build " + obj.optInt("build") : "") + " y los plugins nuevos.\n4. Se vuelve a lanzar."
                            + (mundo ? "\n\nOJO: cambia la versión de Minecraft. El mundo se convierte (tarda) y no vuelve a abrirse con la versión anterior; todos tenéis que actualizar el juego." : ""),
                    "Actualizar");
        });
        botonVersiones(c, "Volver a comprobar", true, x -> comprobarVersiones());
    }

    private void botonVersiones(LinearLayout c, String texto, boolean activo, View.OnClickListener al) {
        Button b = Estilo.boton(this, texto);
        Estilo.activar(b, activo);
        b.setOnClickListener(al);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, px(50));
        lp.topMargin = px(10);
        c.addView(b, lp);
    }

    // ------------------------------------------------------------------ consola

    private void anadirLinea(CharSequence linea) {
        boolean abajo = scrollConsola.getScrollY() + scrollConsola.getHeight() >= consola.getHeight() - px(40);
        lineas.add(linea);
        if (lineas.size() > MAX_LINEAS) {
            while (lineas.size() > MAX_LINEAS * 2 / 3) lineas.removeFirst();
            SpannableStringBuilder todo = new SpannableStringBuilder();
            for (CharSequence l : lineas) todo.append(l).append('\n');
            consola.setText(todo);
        } else {
            consola.append(linea);
            consola.append("\n");
        }
        if (abajo) scrollConsola.post(() -> scrollConsola.scrollTo(0, consola.getHeight()));
    }

    // ------------------------------------------------------------------ ajustes

    private void abrirAjustes() {
        LinearLayout c = columna();
        c.setPadding(px(20), px(10), px(20), 0);
        EditText host = campo(c, "IP del host (ZeroTier)", aj.host, false);
        EditText pmc = campo(c, "Puerto de Minecraft", String.valueOf(aj.puertoMc), true);
        EditText pssh = campo(c, "Puerto SSH (Termux)", String.valueOf(aj.puertoSsh), true);
        EditText dir = campo(c, "Carpeta del repo en el host", aj.carpeta, false);
        TextView ayuda = new TextView(this);
        ayuda.setText("Para autorizar este móvil, pega el comando en Termux del host (una sola vez):");
        ayuda.setPadding(0, px(14), 0, px(4));
        c.addView(ayuda);
        TextView clave = new TextView(this);
        clave.setTypeface(Typeface.MONOSPACE);
        clave.setTextSize(10);
        clave.setText("Generando clave…");
        clave.setMaxLines(4);
        c.addView(clave);
        Button copiar = new Button(this);
        copiar.setText("Copiar comando");
        copiar.setEnabled(false);
        c.addView(copiar);
        ScrollView s = new ScrollView(this);
        s.addView(c);

        hiloVersiones.execute(() -> {
            String k;
            try { k = con.clavePublica(); } catch (Throwable e) { k = null; }
            final String fk = k;
            ui.post(() -> {
                if (fk == null) { clave.setText("No se pudo generar la clave."); return; }
                clave.setText(fk);
                copiar.setEnabled(true);
                copiar.setOnClickListener(v -> {
                    String cmd = "mkdir -p ~/.ssh && echo '" + fk + "' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys";
                    ((ClipboardManager) getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("Multilocal", cmd));
                    Toast.makeText(this, "Copiado. Pégalo en Termux del host.", Toast.LENGTH_LONG).show();
                });
            });
        });

        new AlertDialog.Builder(this)
                .setTitle("Ajustes")
                .setView(s)
                .setPositiveButton("Guardar", (d, w) -> {
                    aj.host = host.getText().toString().trim();
                    aj.puertoMc = entero(pmc, 60068);
                    aj.puertoSsh = entero(pssh, 8022);
                    aj.carpeta = dir.getText().toString().trim();
                    aj.guardar();
                    hiloLog.execute(con::cerrar);
                    posLog = -1;
                    slp = null;
                    estado = null;
                    versiones = null;
                    pintar();
                    ui.removeCallbacks(tickEstado);
                    ui.post(tickEstado);
                })
                .setNegativeButton("Cancelar", null)
                .show();
    }

    private EditText campo(LinearLayout c, String etiqueta, String valor, boolean numero) {
        TextView t = new TextView(this);
        t.setText(etiqueta);
        t.setPadding(0, px(8), 0, 0);
        c.addView(t);
        EditText e = new EditText(this);
        e.setText(valor);
        e.setSingleLine(true);
        e.setInputType(numero ? InputType.TYPE_CLASS_NUMBER : InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        c.addView(e);
        return e;
    }

    private static int entero(EditText e, int def) {
        try { return Integer.parseInt(e.getText().toString().trim()); } catch (NumberFormatException x) { return def; }
    }

    // ------------------------------------------------------------------ utilidades

    private String rama() {
        JSONObject git = estado != null ? estado.optJSONObject("git") : null;
        return git != null ? git.optString("rama", "?") : "?";
    }

    private LinearLayout columna() {
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        return l;
    }

    private ScrollView desplazable(View v) {
        ScrollView s = new ScrollView(this);
        s.addView(v);
        return s;
    }

    private void seccion(LinearLayout c, String titulo) {
        TextView t = Estilo.texto(this, titulo, 15, Estilo.AMARILLO);
        t.setPadding(0, c.getChildCount() == 0 ? 0 : px(14), 0, px(4));
        c.addView(t);
    }

    private void fila(LinearLayout c, String k, String v, int color) {
        LinearLayout f = new LinearLayout(this);
        f.setPadding(0, px(2), 0, px(2));
        f.addView(Estilo.texto(this, k, 13, Estilo.GRIS), new LinearLayout.LayoutParams(-2, -2));
        TextView tv = Estilo.texto(this, v, 13, color);
        tv.setGravity(Gravity.END);
        tv.setPadding(px(10), 0, 0, 0);
        f.addView(tv, new LinearLayout.LayoutParams(0, -2, 1));
        c.addView(f);
    }

    private void barra(LinearLayout c, float v, int color) {
        Estilo.Barra b = new Estilo.Barra(this);
        b.poner(v, color);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-1, -2);
        lp.setMargins(0, px(1), 0, px(5));
        c.addView(b, lp);
    }

    private int px(float dp) { return Estilo.px(this, dp); }

    private static String fmt1(double d) { return String.format(Locale.ROOT, "%.1f", d); }

    private static String gb(int mb) { return mb >= 1024 ? fmt1(mb / 1024.0) + " GB" : mb + " MB"; }

    private static String duracion(long s) {
        if (s < 0) s = 0;
        if (s < 60) return s + " s";
        if (s < 3600) return s / 60 + " min";
        if (s < 86400) return s / 3600 + " h " + (s % 3600) / 60 + " min";
        return s / 86400 + " d " + (s % 86400) / 3600 + " h";
    }
}

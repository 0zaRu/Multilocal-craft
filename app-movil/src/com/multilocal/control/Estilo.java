package com.multilocal.control;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.Rect;
import android.graphics.Shader;
import android.graphics.Typeface;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.StateListDrawable;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;

import java.util.Random;

/** Aspecto "Minecraft" dibujado por código: tierra de fondo, botones de piedra, texto con sombra. */
final class Estilo {
    static final int BLANCO = 0xFFFFFFFF, GRIS = 0xFFAAAAAA, GRIS_OSCURO = 0xFF555555;
    static final int VERDE = 0xFF55FF55, AMARILLO = 0xFFFFFF55, ORO = 0xFFFFAA00, ROJO = 0xFFFF5555, AQUA = 0xFF55FFFF;
    static final Typeface FUENTE = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD);

    private Estilo() {}

    static int px(Context c, float dp) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, dp, c.getResources().getDisplayMetrics()));
    }

    /** Sombra como la del juego: el mismo color a un cuarto de brillo, desplazada un "píxel". */
    static void sombra(TextView t, int color) {
        int s = (color & 0xFF000000) | ((color & 0xFCFCFC) >> 2);
        float d = Math.max(2f, t.getTextSize() / 9f);
        t.setShadowLayer(0.01f, d, d, s);
    }

    static TextView texto(Context c, CharSequence s, float sp, int color) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(color);
        t.setTypeface(FUENTE);
        sombra(t, color);
        return t;
    }

    static Button boton(Context c, String s) {
        Button b = new Button(c);
        b.setText(s);
        b.setAllCaps(false);
        b.setTextSize(15);
        b.setTypeface(FUENTE);
        b.setTextColor(BLANCO);
        sombra(b, 0xFFE0E0E0);
        b.setStateListAnimator(null);
        int u = px(c, 2);
        StateListDrawable fondo = new StateListDrawable();
        fondo.addState(new int[]{android.R.attr.state_pressed}, new Piedra(u, 1));
        fondo.addState(new int[]{android.R.attr.state_selected}, new Piedra(u, 1));
        fondo.addState(new int[]{-android.R.attr.state_enabled}, new Piedra(u, 2));
        fondo.addState(new int[]{}, new Piedra(u, 0));
        b.setBackground(fondo);
        b.setPadding(px(c, 10), px(c, 8), px(c, 10), px(c, 10));
        b.setGravity(Gravity.CENTER);
        b.setMinHeight(px(c, 44));
        return b;
    }

    /** Activa o desactiva un botón; desactivado se ve oscuro y medio transparente. */
    static void activar(Button b, boolean si) {
        b.setEnabled(si);
        b.setAlpha(si ? 1f : 0.45f);
        b.getBackground().invalidateSelf();
    }

    /** Botón de piedra: borde negro, bisel claro arriba-izquierda y oscuro abajo-derecha. */
    static final class Piedra extends Drawable {
        private final int u, modo;   // modo: 0 normal, 1 resaltado, 2 desactivado
        private final Paint p = new Paint();

        Piedra(int u, int modo) { this.u = u; this.modo = modo; }

        @Override public void draw(Canvas c) {
            Rect r = getBounds();
            int relleno = modo == 1 ? 0xFF7E8ACF : modo == 2 ? 0xFF2C2C2C : 0xFF6F6F6F;
            int claro = modo == 1 ? 0xFFAEB8F0 : modo == 2 ? 0xFF3A3A3A : 0xFFA9A9A9;
            int oscuro = modo == 1 ? 0xFF4C5899 : modo == 2 ? 0xFF1E1E1E : 0xFF4A4A4A;
            p.setColor(modo == 1 ? BLANCO : 0xFF000000);
            c.drawRect(r, p);
            p.setColor(oscuro);
            c.drawRect(r.left + u, r.top + u, r.right - u, r.bottom - u, p);
            p.setColor(claro);
            c.drawRect(r.left + u, r.top + u, r.right - 2 * u, r.bottom - 3 * u, p);
            p.setColor(relleno);
            c.drawRect(r.left + 2 * u, r.top + 2 * u, r.right - 2 * u, r.bottom - 3 * u, p);
        }
        @Override public void setAlpha(int a) {}
        @Override public void setColorFilter(ColorFilter f) {}
        @Override public int getOpacity() { return PixelFormat.OPAQUE; }
    }

    /** Fondo de tierra oscurecida, como el de los menús del juego (textura propia generada). */
    static Drawable tierra(Context c) {
        int[] tonos = {0xFF866043, 0xFF79553A, 0xFF966C4A, 0xFF593D29, 0xFF6C4A32, 0xFF8B6545};
        Random r = new Random(1337);
        Bitmap b = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888);
        for (int y = 0; y < 16; y++)
            for (int x = 0; x < 16; x++) {
                int t = tonos[r.nextInt(tonos.length)];
                // oscurecer al 30 %, como el fondo de opciones
                int rr = ((t >> 16) & 0xFF) * 3 / 10, gg = ((t >> 8) & 0xFF) * 3 / 10, bb = (t & 0xFF) * 3 / 10;
                b.setPixel(x, y, 0xFF000000 | (rr << 16) | (gg << 8) | bb);
            }
        int lado = px(c, 48);
        BitmapDrawable d = new BitmapDrawable(c.getResources(), Bitmap.createScaledBitmap(b, lado, lado, false));
        d.setTileModeXY(Shader.TileMode.REPEAT, Shader.TileMode.REPEAT);
        d.setFilterBitmap(false);
        return d;
    }

    /** Recuadro tipo "tooltip" del juego: fondo casi negro y borde morado. */
    static Drawable panel(Context c) {
        final int u = px(c, 2);
        return new Drawable() {
            final Paint p = new Paint();
            @Override public void draw(Canvas cv) {
                Rect r = getBounds();
                p.setColor(0xE6100010);
                cv.drawRect(r, p);
                p.setColor(0xFF3B0E7A);
                cv.drawRect(r.left, r.top, r.right, r.top + u, p);
                cv.drawRect(r.left, r.top, r.left + u, r.bottom, p);
                p.setColor(0xFF1F074A);
                cv.drawRect(r.left, r.bottom - u, r.right, r.bottom, p);
                cv.drawRect(r.right - u, r.top, r.right, r.bottom, p);
            }
            @Override public void setAlpha(int a) {}
            @Override public void setColorFilter(ColorFilter f) {}
            @Override public int getOpacity() { return PixelFormat.TRANSLUCENT; }
        };
    }

    /** Barra pixelada (como la de experiencia) con un valor de 0 a 1. */
    static final class Barra extends View {
        private float valor;
        private int color = VERDE;
        private final Paint p = new Paint();

        Barra(Context c) { super(c); }

        void poner(float v, int color) { valor = Math.max(0, Math.min(1, v)); this.color = color; invalidate(); }

        @Override protected void onMeasure(int w, int h) {
            setMeasuredDimension(MeasureSpec.getSize(w), px(getContext(), 10));
        }

        @Override protected void onDraw(Canvas c) {
            int u = px(getContext(), 2), w = getWidth(), h = getHeight();
            p.setColor(0xFF000000);
            c.drawRect(0, 0, w, h, p);
            p.setColor(0xFF2A2A2A);
            c.drawRect(u, u, w - u, h - u, p);
            int lleno = Math.round((w - 2 * u) * valor);
            p.setColor(color);
            c.drawRect(u, u, u + lleno, h - u, p);
            p.setColor(0x55FFFFFF);
            c.drawRect(u, u, u + lleno, u + u, p);
            // separaciones de "píxel" cada 10 %
            p.setColor(0x66000000);
            for (int i = 1; i < 10; i++) {
                int x = u + (w - 2 * u) * i / 10;
                c.drawRect(x, u, x + Math.max(1, u / 2), h - u, p);
            }
        }
    }

    /** Cara de 8x8 generada a partir del nombre (no usa skins: el servidor va sin cuentas oficiales). */
    static Drawable cara(Context c, String nombre) {
        Random r = new Random(nombre.toLowerCase().hashCode());
        int[] pieles = {0xFFF2C6A0, 0xFFD9A066, 0xFFB5764A, 0xFF8D5524, 0xFFFFDBAC};
        int[] pelos = {0xFF3B2213, 0xFF6B4423, 0xFF1C1C1C, 0xFFE6C35C, 0xFFB5482B, 0xFF7A7A7A};
        int[] ojos = {0xFF3A6FD8, 0xFF2E8B57, 0xFF6B4423, 0xFF444444};
        int piel = pieles[r.nextInt(pieles.length)], pelo = pelos[r.nextInt(pelos.length)], ojo = ojos[r.nextInt(ojos.length)];
        Bitmap b = Bitmap.createBitmap(8, 8, Bitmap.Config.ARGB_8888);
        int flequillo = 1 + r.nextInt(2);
        for (int y = 0; y < 8; y++)
            for (int x = 0; x < 8; x++) {
                int col = piel;
                if (y < flequillo || (y == flequillo && (x == 0 || x == 7))) col = pelo;
                if ((x == 0 || x == 7) && y < 4 && r.nextBoolean()) col = pelo;
                if (y == 4 && (x == 1 || x == 6)) col = BLANCO;
                if (y == 4 && (x == 2 || x == 5)) col = ojo;
                if (y == 6 && x >= 3 && x <= 4) col = 0xFF7A3B2E;
                int v = r.nextInt(14) - 7;   // un poco de ruido para que parezca pixel art
                col = 0xFF000000 | (lim(((col >> 16) & 0xFF) + v) << 16) | (lim(((col >> 8) & 0xFF) + v) << 8) | lim((col & 0xFF) + v);
                b.setPixel(x, y, col);
            }
        int lado = px(c, 32);
        BitmapDrawable d = new BitmapDrawable(c.getResources(), Bitmap.createScaledBitmap(b, lado, lado, false));
        d.setFilterBitmap(false);
        return d;
    }

    private static int lim(int v) { return Math.max(0, Math.min(255, v)); }
}

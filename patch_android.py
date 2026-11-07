# Ajusta el AndroidManifest generado: internet + mostrar la app sobre la pantalla de bloqueo.
p = "android/app/src/main/AndroidManifest.xml"
t = open(p, encoding="utf-8").read()
if "android.permission.INTERNET" not in t:
    t = t.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
if "showWhenLocked" not in t:
    t = t.replace('android:name=".MainActivity"',
                  'android:name=".MainActivity"\n            android:showWhenLocked="true"\n            android:turnScreenOn="true"', 1)
t = t.replace('android:label="tu_y_yo"', 'android:label="Tú y yo"')
open(p, "w", encoding="utf-8").write(t)
print("Manifest listo")

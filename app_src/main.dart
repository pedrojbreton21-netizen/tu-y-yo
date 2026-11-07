import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

const palette = [0xFFFFD6E0, 0xFFFF6B9A, 0xFFFFB347, 0xFF9AD6FF, 0xFFFFFFFF];
const brushes = {'pen': 'Lápiz', 'marker': 'Marcador', 'neon': 'Neón', 'eraser': 'Borrador'};

void main() => runApp(const TuYYoApp());

class TuYYoApp extends StatelessWidget {
  const TuYYoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Tú y yo',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF8FB1), brightness: Brightness.dark),
        ),
        home: const JoinScreen(),
      );
}

const bgGradient = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3B1646), Color(0xFF7A2A5C), Color(0xFFD1625F)],
  ),
);

class Stroke {
  final String id, u, b;
  final int t, c;
  final double w;
  List<Offset> p;
  Stroke(this.id, this.u, this.t, this.c, this.w, this.b, this.p);

  Map<String, dynamic> toJson() {
    final flat = <double>[];
    for (final o in p) {
      flat.add(double.parse(o.dx.toStringAsFixed(4)));
      flat.add(double.parse(o.dy.toStringAsFixed(4)));
    }
    return {'u': u, 't': t, 'c': c, 'w': w, 'b': b, 'p': flat};
  }

  static Stroke? fromJson(String id, dynamic j) {
    if (j is! Map) return null;
    final f = (j['p'] is List) ? j['p'] as List : const [];
    final pts = <Offset>[];
    for (var i = 0; i + 1 < f.length; i += 2) {
      if (f[i] is num && f[i + 1] is num) {
        pts.add(Offset((f[i] as num).toDouble(), (f[i + 1] as num).toDouble()));
      }
    }
    return Stroke(
      id,
      j['u'].toString(),
      (j['t'] is num) ? (j['t'] as num).toInt() : 0,
      (j['c'] is num) ? (j['c'] as num).toInt() : 0xFFFFFFFF,
      (j['w'] is num) ? (j['w'] as num).toDouble() : 6,
      brushes.containsKey(j['b']) ? j['b'] as String : 'pen',
      pts,
    );
  }
}

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});
  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  String _me = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    var me = p.getString('me');
    if (me == null) {
      me = 'u${Random().nextInt(1 << 30).toRadixString(36)}';
      await p.setString('me', me);
    }
    _me = me;
    _name.text = p.getString('name') ?? '';
    _code.text = p.getString('code') ?? '';
    if (mounted) setState(() {});
  }

  void _newCode() {
    const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    _code.text = List.generate(5, (_) => a[r.nextInt(a.length)]).join();
  }

  Future<void> _go() async {
    final n = _name.text.trim();
    final c = _code.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (n.isEmpty || c.length < 4 || _me.isEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('name', n);
    await p.setString('code', c);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => DrawScreen(name: n, code: c, me: _me)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: bgGradient,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Tú y yo', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Dibujen juntos en la pantalla de bloqueo de los dos.'),
                const SizedBox(height: 20),
                TextField(
                  controller: _name,
                  maxLength: 20,
                  decoration: const InputDecoration(labelText: 'Tu nombre', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _code,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Código de pareja', border: OutlineInputBorder()),
                ),
                OutlinedButton(onPressed: () => setState(_newCode), child: const Text('Crear código nuevo')),
                const SizedBox(height: 10),
                FilledButton(onPressed: _go, child: const Text('Entrar')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DrawScreen extends StatefulWidget {
  final String name, code, me;
  const DrawScreen({super.key, required this.name, required this.code, required this.me});
  @override
  State<DrawScreen> createState() => _DrawScreenState();
}

class _HeartInfo {
  final int id;
  final double x;
  final int color;
  _HeartInfo(this.id, this.x, this.color);
}

class _DrawScreenState extends State<DrawScreen> {
  final List<Stroke> strokes = [];
  final List<_HeartInfo> hearts = [];
  Stroke? cur;
  Size _size = const Size(1, 1);
  int color = palette[1];
  String brush = 'pen';
  double width = 6;
  bool menuOpen = true;
  bool online = false;
  String partner = '';
  String clock = '';
  bool dirty = false, busy = false;
  int? lastHeart;
  int heartSeq = 0;
  DateTime lastPresence = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? pollT, pushT, clockT;

  String get base => '$kDbUrl/rooms/${widget.code}';

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _tick();
    clockT = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
    pollT = Timer.periodic(const Duration(milliseconds: 700), (_) => _poll());
    pushT = Timer.periodic(const Duration(milliseconds: 350), (_) {
      if (cur != null && dirty) {
        dirty = false;
        _put(cur!);
      }
    });
  }

  @override
  void dispose() {
    pollT?.cancel();
    pushT?.cancel();
    clockT?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _tick() {
    final n = DateTime.now();
    final s = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    if (mounted) setState(() => clock = s);
  }

  Future<void> _put(Stroke s) async {
    try {
      await http.put(Uri.parse('$base/strokes/${s.id}.json'), body: jsonEncode(s.toJson()));
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (busy) return;
    busy = true;
    try {
      final now = DateTime.now();
      if (now.difference(lastPresence).inSeconds >= 8) {
        lastPresence = now;
        http
            .put(Uri.parse('$base/users/${widget.me}.json'),
                body: jsonEncode({'name': widget.name, 't': now.millisecondsSinceEpoch}))
            .catchError((_) => http.Response('', 500));
      }
      final r = await http.get(Uri.parse('$base.json')).timeout(const Duration(seconds: 5));
      if (r.statusCode != 200) {
        if (mounted) setState(() => online = false);
        return;
      }
      final d = jsonDecode(r.body);
      final map = d is Map ? d : <String, dynamic>{};
      final remote = map['strokes'] is Map ? Map<String, dynamic>.from(map['strokes'] as Map) : <String, dynamic>{};
      final ids = <String>{};
      for (final e in remote.entries) {
        final s = Stroke.fromJson(e.key, e.value);
        if (s == null || s.u == widget.me) continue;
        ids.add(e.key);
        final i = strokes.indexWhere((x) => x.id == e.key);
        if (i >= 0) {
          strokes[i] = s;
        } else {
          strokes.add(s);
        }
      }
      strokes.removeWhere((s) => s.u != widget.me && !ids.contains(s.id));
      strokes.sort((a, b) => a.t.compareTo(b.t));

      final h = map['heart'];
      if (h is Map && h['t'] is num) {
        final t = (h['t'] as num).toInt();
        if (lastHeart == null) {
          lastHeart = t;
        } else if (t > lastHeart! && h['u'].toString() != widget.me) {
          lastHeart = t;
          _spawnHeart();
        }
      } else {
        lastHeart ??= 0;
      }

      String p = '';
      final us = map['users'];
      if (us is Map) {
        for (final e in us.entries) {
          if (e.key == widget.me || e.value is! Map) continue;
          final t = e.value['t'];
          if (t is num && now.millisecondsSinceEpoch - t.toInt() < 30000) {
            p = e.value['name'].toString();
          }
        }
      }
      if (mounted) {
        setState(() {
          online = true;
          partner = p;
        });
      }
    } catch (_) {
      if (mounted) setState(() => online = false);
    } finally {
      busy = false;
    }
  }

  void _spawnHeart() {
    final r = Random();
    final hh = _HeartInfo(heartSeq++, r.nextDouble() * 1.6 - 0.8, palette[1 + r.nextInt(3)]);
    setState(() => hearts.add(hh));
    Timer(const Duration(milliseconds: 2300), () {
      if (mounted) setState(() => hearts.removeWhere((x) => x.id == hh.id));
    });
  }

  void _sendHeart() {
    _spawnHeart();
    http
        .put(Uri.parse('$base/heart.json'),
            body: jsonEncode({'u': widget.me, 't': DateTime.now().millisecondsSinceEpoch}))
        .catchError((_) => http.Response('', 500));
  }

  Offset _norm(Offset o) => Offset(o.dx / _size.width, o.dy / _size.height);

  void _down(PointerDownEvent e) {
    final s = Stroke('${widget.me}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(999)}',
        widget.me, DateTime.now().millisecondsSinceEpoch, color, width, brush, [_norm(e.localPosition)]);
    cur = s;
    strokes.add(s);
    dirty = true;
    setState(() {});
  }

  void _move(PointerMoveEvent e) {
    final s = cur;
    if (s == null || s.p.length > 6000) return;
    s.p.add(_norm(e.localPosition));
    dirty = true;
    setState(() {});
  }

  void _up(PointerEvent e) {
    final s = cur;
    if (s == null) return;
    cur = null;
    dirty = false;
    _put(s);
  }

  void _undo() {
    for (var i = strokes.length - 1; i >= 0; i--) {
      if (strokes[i].u == widget.me) {
        final id = strokes[i].id;
        strokes.removeAt(i);
        http.delete(Uri.parse('$base/strokes/$id.json')).catchError((_) => http.Response('', 500));
        break;
      }
    }
    setState(() {});
  }

  void _clear() {
    final mine = strokes.where((s) => s.u == widget.me).toList();
    for (final s in mine) {
      http.delete(Uri.parse('$base/strokes/${s.id}.json')).catchError((_) => http.Response('', 500));
    }
    strokes.removeWhere((s) => s.u == widget.me);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final status = !online
        ? 'Sin conexión · código ${widget.code}'
        : (partner.isEmpty ? 'Esperando a tu pareja · código ${widget.code}' : 'Con $partner');
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: bgGradient,
        child: Stack(
          children: [
            Positioned(
              top: pad.top + 56,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Text(clock,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 92, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
            ),
            Positioned.fill(
              child: LayoutBuilder(builder: (ctx, c) {
                _size = Size(max(1, c.maxWidth), max(1, c.maxHeight));
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _down,
                  onPointerMove: _move,
                  onPointerUp: _up,
                  onPointerCancel: _up,
                  child: CustomPaint(painter: Board(strokes), size: Size.infinite),
                );
              }),
            ),
            Positioned(
              top: pad.top + 8,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(99)),
                    child: Text(status, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ),
            for (final h in hearts)
              IgnorePointer(
                key: ValueKey(h.id),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 2200),
                  builder: (_, t, __) => Align(
                    alignment: Alignment(h.x, 0.6 - t * 1.3),
                    child: Opacity(
                      opacity: 1 - t,
                      child: Text('♥', style: TextStyle(fontSize: 34 + t * 14, color: Color(h.color))),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: pad.bottom + 12,
              child: Center(child: _menu()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menu() {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => setState(() => menuOpen = !menuOpen),
                child: Text(menuOpen ? 'Ocultar menú' : 'Menú'),
              ),
              if (menuOpen) ...[
                Wrap(
                  spacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final c in palette)
                      GestureDetector(
                        onTap: () => setState(() {
                          color = c;
                          if (brush == 'eraser') brush = 'pen';
                        }),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(color: (color == c && brush != 'eraser') ? Colors.white : Colors.transparent, width: 3),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final e in brushes.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: brush == e.key,
                        onSelected: (_) => setState(() => brush = e.key),
                      ),
                  ],
                ),
                Slider(value: width, min: 2, max: 40, onChanged: (v) => setState(() => width = v)),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(onPressed: _undo, child: const Text('Deshacer')),
                    OutlinedButton(onPressed: _clear, child: const Text('Borrar mío')),
                    FilledButton(onPressed: _sendHeart, child: const Text('♥ Corazón')),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class Board extends CustomPainter {
  final List<Stroke> strokes;
  Board(this.strokes);

  Offset _pt(Offset o, Size s) => Offset(o.dx * s.width, o.dy * s.height);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    for (final s in strokes) {
      if (s.p.isEmpty) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color(s.c)
        ..strokeWidth = s.w;
      if (s.b == 'marker') {
        paint.color = Color(s.c).withOpacity(0.45);
        paint.strokeWidth = s.w * 2.4;
      } else if (s.b == 'neon') {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.w * 1.2);
      } else if (s.b == 'eraser') {
        paint.blendMode = BlendMode.clear;
        paint.strokeWidth = s.w * 3;
      }
      if (s.p.length == 1) {
        final dot = Paint()
          ..color = paint.color
          ..blendMode = paint.blendMode
          ..maskFilter = paint.maskFilter;
        canvas.drawCircle(_pt(s.p[0], size), paint.strokeWidth / 2, dot);
        continue;
      }
      final path = Path()..moveTo(_pt(s.p[0], size).dx, _pt(s.p[0], size).dy);
      for (var i = 1; i < s.p.length; i++) {
        final q = _pt(s.p[i], size);
        path.lineTo(q.dx, q.dy);
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant Board old) => true;
}

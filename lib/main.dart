import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const StackTowerApp());
}

class StackTowerApp extends StatelessWidget {
  const StackTowerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Torre de Blocos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09111F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
      ),
      home: const StackTowerPage(),
    );
  }
}

class BlockData {
  final double x;
  final double width;
  final Color color;

  const BlockData({required this.x, required this.width, required this.color});
}

class StackTowerPage extends StatefulWidget {
  const StackTowerPage({super.key});

  @override
  State<StackTowerPage> createState() => _StackTowerPageState();
}

class _StackTowerPageState extends State<StackTowerPage>
    with SingleTickerProviderStateMixin {
  static const double _blockHeight = 34;
  static const String _bestScoreKey = 'tower_best_score';

  late final Ticker _ticker;
  Duration? _lastElapsed;

  double _boardWidth = 0;

  final List<BlockData> _placedBlocks = [];

  double _movingX = 0;
  double _movingWidth = 0;
  Color _movingColor = Colors.cyanAccent;

  bool _movingRight = true;
  bool _nextStartsFromLeft = true;

  double _speed = 210;
  int _score = 0;
  int _bestScore = 0;

  bool _ready = false;
  bool _gameOver = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadBestScore();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _bestScore = prefs.getInt(_bestScoreKey) ?? 0;
    });
  }

  Future<void> _saveBestScore(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestScoreKey, value);
  }

  void _onBoardReady(double width) {
    if (width <= 0) return;

    final shouldReset = !_ready || (_boardWidth - width).abs() > 1;
    if (!shouldReset) return;

    _boardWidth = width;
    _resetGame();
  }

  void _resetGame() {
    if (_boardWidth <= 0) return;

    final baseWidth = _boardWidth * 0.72;
    final baseX = (_boardWidth - baseWidth) / 2;

    _placedBlocks
      ..clear()
      ..add(BlockData(x: baseX, width: baseWidth, color: _colorForLevel(0)));

    _movingWidth = baseWidth;
    _movingX = 0;
    _movingColor = _colorForLevel(1);

    _movingRight = true;
    _nextStartsFromLeft = true;

    _speed = 210;
    _score = 0;
    _gameOver = false;
    _ready = true;
    _lastElapsed = null;

    if (_ticker.isActive) {
      _ticker.stop();
    }
    _ticker.start();

    if (mounted) {
      setState(() {});
    }
  }

  void _onTick(Duration elapsed) {
    if (!_ready || _gameOver || _boardWidth <= 0) return;

    final previous = _lastElapsed;
    _lastElapsed = elapsed;

    if (previous == null) return;

    final dt = (elapsed - previous).inMicroseconds / 1000000.0;
    if (dt <= 0) return;

    final maxX = math.max(0.0, _boardWidth - _movingWidth);

    double newX = _movingX + (_movingRight ? 1 : -1) * _speed * dt;
    bool newDirection = _movingRight;

    if (newX <= 0) {
      newX = 0;
      newDirection = true;
    } else if (newX >= maxX) {
      newX = maxX;
      newDirection = false;
    }

    if (!mounted) return;

    setState(() {
      _movingX = newX;
      _movingRight = newDirection;
    });
  }

  void _dropBlock() {
    if (!_ready || _gameOver || _placedBlocks.isEmpty) return;

    final last = _placedBlocks.last;

    final overlapLeft = math.max(_movingX, last.x);
    final overlapRight = math.min(_movingX + _movingWidth, last.x + last.width);
    final overlapWidth = overlapRight - overlapLeft;

    if (overlapWidth <= 0) {
      _endGame();
      return;
    }

    final newScore = _score + 1;

    if (newScore > _bestScore) {
      _bestScore = newScore;
      _saveBestScore(_bestScore);
    }

    _placedBlocks.add(
      BlockData(x: overlapLeft, width: overlapWidth, color: _movingColor),
    );

    _score = newScore;
    _movingWidth = overlapWidth;
    _movingColor = _colorForLevel(_placedBlocks.length);
    _speed = math.min(_speed + 18, 560);

    _nextStartsFromLeft = !_nextStartsFromLeft;
    _movingX = _nextStartsFromLeft ? 0 : (_boardWidth - _movingWidth);
    _movingRight = _nextStartsFromLeft;

    if (mounted) {
      setState(() {});
    }
  }

  void _endGame() {
    if (_ticker.isActive) {
      _ticker.stop();
    }

    setState(() {
      _gameOver = true;
    });
  }

  Color _colorForLevel(int level) {
    final hue = (level * 29) % 360;
    return HSVColor.fromAHSV(1, hue.toDouble(), 0.62, 0.95).toColor();
  }

  double _cameraOffset(double boardHeight) {
    final totalHeight = (_placedBlocks.length + 1) * _blockHeight;
    return math.max(0.0, totalHeight - boardHeight + 22);
  }

  double _yForLevel(int level, double boardHeight) {
    return boardHeight -
        ((level + 1) * _blockHeight) -
        _cameraOffset(boardHeight);
  }

  Widget _buildBlock({
    required double width,
    required Color color,
    bool glowing = false,
  }) {
    return Container(
      width: width,
      height: _blockHeight - 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.95),
            Color.lerp(color, Colors.black, 0.18)!,
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.16),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: glowing ? 0.45 : 0.22),
            blurRadius: glowing ? 20 : 10,
            spreadRadius: glowing ? 1 : 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final boardHeight = math.min(screen.height * 0.58, 560.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E1830), Color(0xFF09111F), Color(0xFF050A14)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                const SizedBox(height: 6),
                const Text(
                  'Torre de Blocos',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Toque na área do jogo para soltar o bloco no momento certo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    _statCard(
                      icon: Icons.stacked_bar_chart_rounded,
                      label: 'Pontuação',
                      value: '$_score',
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      icon: Icons.workspace_premium_rounded,
                      label: 'Recorde',
                      value: '$_bestScore',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Center(
                    child: Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                        maxWidth: math.min(460, screen.width),
                      ),
                      height: boardHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1.2,
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.07),
                            Colors.white.withValues(alpha: 0.02),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 30,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _dropBlock,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _onBoardReady(constraints.maxWidth);
                              });

                              return Stack(
                                children: [
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            const Color(
                                              0xFF14213D,
                                            ).withValues(alpha: 0.48),
                                            const Color(
                                              0xFF0A1222,
                                            ).withValues(alpha: 0.75),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CustomPaint(painter: _GridPainter()),
                                  ),

                                  for (int i = 0; i < _placedBlocks.length; i++)
                                    Positioned(
                                      left: _placedBlocks[i].x,
                                      top: _yForLevel(i, boardHeight),
                                      child: _buildBlock(
                                        width: _placedBlocks[i].width,
                                        color: _placedBlocks[i].color,
                                      ),
                                    ),

                                  if (_ready && !_gameOver)
                                    Positioned(
                                      left: _movingX,
                                      top: _yForLevel(
                                        _placedBlocks.length,
                                        boardHeight,
                                      ),
                                      child: _buildBlock(
                                        width: _movingWidth,
                                        color: _movingColor,
                                        glowing: true,
                                      ),
                                    ),

                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      height: 8,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withValues(
                                              alpha: 0.16,
                                            ),
                                            Colors.white.withValues(
                                              alpha: 0.02,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  if (_gameOver)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.black.withValues(
                                          alpha: 0.45,
                                        ),
                                        child: Center(
                                          child: Container(
                                            margin: const EdgeInsets.all(24),
                                            padding: const EdgeInsets.all(22),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF101A31),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.08,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.close_rounded,
                                                  size: 44,
                                                ),
                                                const SizedBox(height: 12),
                                                const Text(
                                                  'Fim de jogo',
                                                  style: TextStyle(
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  'Você fez $_score ponto${_score == 1 ? '' : 's'}',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.78,
                                                        ),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'Melhor: $_bestScore',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 18),
                                                FilledButton.icon(
                                                  onPressed: _resetGame,
                                                  icon: const Icon(
                                                    Icons.replay,
                                                  ),
                                                  label: const Text(
                                                    'Jogar novamente',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _resetGame,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Reiniciar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 1;

    const gap = 32.0;

    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

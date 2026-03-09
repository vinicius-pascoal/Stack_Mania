import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const StackTowerV3App());
}

class StackTowerV3App extends StatelessWidget {
  const StackTowerV3App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Torre de Blocos V3',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF07101D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C4DFF),
          brightness: Brightness.dark,
        ),
      ),
      home: const StackTowerHomePage(),
    );
  }
}

enum ViewMode { menu, game }

class BlockData {
  final double x;
  final double width;
  final Color color;

  const BlockData({required this.x, required this.width, required this.color});
}

class FallingPiece {
  double x;
  double width;
  double worldTop;
  double velocity;
  double rotation;
  double rotationSpeed;
  double driftX;
  final Color color;

  FallingPiece({
    required this.x,
    required this.width,
    required this.worldTop,
    required this.velocity,
    required this.rotation,
    required this.rotationSpeed,
    required this.driftX,
    required this.color,
  });
}

class StackTowerHomePage extends StatefulWidget {
  const StackTowerHomePage({super.key});

  @override
  State<StackTowerHomePage> createState() => _StackTowerHomePageState();
}

class _StackTowerHomePageState extends State<StackTowerHomePage>
    with SingleTickerProviderStateMixin {
  static const double _blockHeight = 34;
  static const double _spawnGap = 92;
  static const double _perfectTolerance = 8;
  static const double _topSafeSpace = 88;

  static const String _bestScoreKey = 'tower_v3_best_score';
  static const String _historyKey = 'tower_v3_recent_scores';

  late final Ticker _ticker;
  Duration? _lastElapsed;

  ViewMode _viewMode = ViewMode.menu;

  double _boardWidth = 0;
  double _boardHeight = 0;
  bool _boardReady = false;

  final List<BlockData> _placedBlocks = [];
  final List<FallingPiece> _fallingPieces = [];

  double _movingX = 0;
  double _movingWidth = 0;
  Color _movingColor = Colors.cyanAccent;
  bool _movingRight = true;
  bool _nextStartsFromLeft = true;

  double _speed = 220;
  int _score = 0;
  int _bestScore = 0;
  int _combo = 0;
  List<int> _recentScores = [];

  bool _gameOver = false;

  bool _isDropping = false;
  double _dropWorldTop = 0;
  double _dropStartWorldTop = 0;
  double _dropEndWorldTop = 0;
  double _dropElapsed = 0;
  double _dropDuration = 0.15;
  double _lockedDropX = 0;

  double _cameraOffset = 0;
  String _perfectText = '';
  double _perfectTimer = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _loadLocalData();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    final historyRaw = prefs.getStringList(_historyKey) ?? [];

    if (!mounted) return;

    setState(() {
      _bestScore = prefs.getInt(_bestScoreKey) ?? 0;
      _recentScores = historyRaw
          .map((e) => int.tryParse(e) ?? 0)
          .where((e) => e >= 0)
          .toList();
    });
  }

  Future<void> _saveBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_bestScoreKey, _bestScore);
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _historyKey,
      _recentScores.map((e) => e.toString()).toList(),
    );
  }

  void _registerScore() {
    if (_score <= 0) return;

    _recentScores.insert(0, _score);
    if (_recentScores.length > 5) {
      _recentScores = _recentScores.take(5).toList();
    }
    _saveHistory();
  }

  void _startGame() {
    setState(() {
      _viewMode = ViewMode.game;
    });

    if (_boardReady) {
      _resetGame();
    }
  }

  void _goToMenu() {
    if (_ticker.isActive) {
      _ticker.stop();
    }

    setState(() {
      _viewMode = ViewMode.menu;
      _gameOver = false;
      _isDropping = false;
      _perfectText = '';
      _perfectTimer = 0;
      _fallingPieces.clear();
    });
  }

  void _onBoardReady(double width, double height) {
    if (width <= 0 || height <= 0) return;

    final changed =
        !_boardReady ||
        (_boardWidth - width).abs() > 1 ||
        (_boardHeight - height).abs() > 1;

    if (!changed) return;

    _boardReady = true;
    _boardWidth = width;
    _boardHeight = height;

    if (_viewMode == ViewMode.game) {
      _resetGame();
    }
  }

  void _resetGame() {
    if (!_boardReady) return;

    final baseWidth = _boardWidth * 0.72;
    final baseX = (_boardWidth - baseWidth) / 2;

    _placedBlocks
      ..clear()
      ..add(BlockData(x: baseX, width: baseWidth, color: _colorForLevel(0)));

    _fallingPieces.clear();

    _movingWidth = baseWidth;
    _movingColor = _colorForLevel(1);
    _score = 0;
    _combo = 0;
    _speed = 220;
    _cameraOffset = 0;
    _gameOver = false;
    _isDropping = false;
    _perfectText = '';
    _perfectTimer = 0;
    _nextStartsFromLeft = true;

    _spawnNextBlock();

    _lastElapsed = null;

    if (_ticker.isActive) {
      _ticker.stop();
    }
    _ticker.start();

    if (mounted) {
      setState(() {});
    }
  }

  void _spawnNextBlock() {
    _movingColor = _colorForLevel(_placedBlocks.length);
    _movingX = _nextStartsFromLeft ? 0 : (_boardWidth - _movingWidth);
    _movingRight = _nextStartsFromLeft;
    _nextStartsFromLeft = !_nextStartsFromLeft;
    _isDropping = false;
  }

  double _worldTopForLevel(int level) {
    return (level + 1) * _blockHeight;
  }

  double _spawnWorldTopForLevel(int level) {
    return _worldTopForLevel(level) + _spawnGap;
  }

  double _screenYForWorldTop(double worldTop) {
    return _boardHeight - worldTop + _cameraOffset;
  }

  double _computeCameraTarget() {
    if (!_boardReady) return 0;

    double activeTopWorld;

    if (_viewMode != ViewMode.game) {
      activeTopWorld = _worldTopForLevel(math.max(_placedBlocks.length - 1, 0));
    } else if (_gameOver) {
      activeTopWorld = _worldTopForLevel(math.max(_placedBlocks.length - 1, 0));
    } else if (_isDropping) {
      activeTopWorld = _dropWorldTop;
    } else {
      activeTopWorld = _spawnWorldTopForLevel(_placedBlocks.length);
    }

    final target = activeTopWorld - (_boardHeight - _topSafeSpace);

    return math.max(0, target);
  }

  void _updateCamera(double dt) {
    final target = _computeCameraTarget();
    final followSpeed = _isDropping ? 10.0 : 7.0;
    final t = math.min(1.0, dt * followSpeed);
    _cameraOffset += (target - _cameraOffset) * t;
  }

  void _updateFallingPieces(double dt) {
    const gravity = 1200.0;

    for (final piece in _fallingPieces) {
      piece.velocity += gravity * dt;
      piece.worldTop -= piece.velocity * dt;
      piece.x += piece.driftX * dt;
      piece.rotation += piece.rotationSpeed * dt;
    }

    _fallingPieces.removeWhere((piece) {
      final screenY = _screenYForWorldTop(piece.worldTop);
      return screenY > _boardHeight + 160 ||
          piece.x + piece.width < -120 ||
          piece.x > _boardWidth + 120;
    });
  }

  void _onTick(Duration elapsed) {
    if (_viewMode != ViewMode.game || !_boardReady) return;

    final previous = _lastElapsed;
    _lastElapsed = elapsed;

    if (previous == null) return;

    final dt = (elapsed - previous).inMicroseconds / 1000000.0;
    if (dt <= 0) return;

    bool needsRebuild = false;

    if (_perfectTimer > 0) {
      _perfectTimer = math.max(0, _perfectTimer - dt);
      needsRebuild = true;
      if (_perfectTimer == 0) {
        _perfectText = '';
      }
    }

    _updateCamera(dt);
    _updateFallingPieces(dt);
    needsRebuild = true;

    if (_gameOver) {
      if (mounted && needsRebuild) {
        setState(() {});
      }
      return;
    }

    if (_isDropping) {
      _dropElapsed += dt;
      final t = (_dropElapsed / _dropDuration).clamp(0.0, 1.0);
      final eased = Curves.easeIn.transform(t);
      _dropWorldTop =
          _dropStartWorldTop + (_dropEndWorldTop - _dropStartWorldTop) * eased;

      if (t >= 1.0) {
        _resolveDroppedBlock();
      }
    } else {
      final maxX = math.max(0.0, _boardWidth - _movingWidth);
      double nextX = _movingX + (_movingRight ? 1 : -1) * _speed * dt;
      bool nextDirection = _movingRight;

      if (nextX <= 0) {
        nextX = 0;
        nextDirection = true;
      } else if (nextX >= maxX) {
        nextX = maxX;
        nextDirection = false;
      }

      _movingX = nextX;
      _movingRight = nextDirection;
    }

    if (mounted && needsRebuild) {
      setState(() {});
    }
  }

  void _handleTap() {
    if (_viewMode != ViewMode.game) return;
    if (_gameOver || _isDropping) return;
    if (_placedBlocks.isEmpty) return;

    _lockedDropX = _movingX;
    _dropEndWorldTop = _worldTopForLevel(_placedBlocks.length);
    _dropStartWorldTop = _spawnWorldTopForLevel(_placedBlocks.length);
    _dropWorldTop = _dropStartWorldTop;
    _dropElapsed = 0;
    _dropDuration = 0.15;
    _isDropping = true;

    HapticFeedback.selectionClick();
  }

  void _spawnCutPiece({
    required double x,
    required double width,
    required double worldTop,
    required Color color,
    required bool leftSide,
  }) {
    if (width <= 0) return;

    _fallingPieces.add(
      FallingPiece(
        x: x,
        width: width,
        worldTop: worldTop,
        velocity: 90,
        rotation: 0,
        rotationSpeed: leftSide ? -2.8 : 2.8,
        driftX: leftSide ? -42 : 42,
        color: color,
      ),
    );
  }

  void _resolveDroppedBlock() {
    final last = _placedBlocks.last;
    final placedWorldTop = _worldTopForLevel(_placedBlocks.length);

    double overlapLeft = math.max(_lockedDropX, last.x);
    double overlapRight = math.min(
      _lockedDropX + _movingWidth,
      last.x + last.width,
    );
    double overlapWidth = overlapRight - overlapLeft;

    if (overlapWidth <= 0) {
      _finishGame();
      return;
    }

    final isPerfect = (_lockedDropX - last.x).abs() <= _perfectTolerance;

    if (isPerfect) {
      overlapLeft = last.x;
      overlapWidth = last.width;
      _combo += 1;

      final extraBonus = math.min(math.max(_combo - 1, 0), 4);
      final gained = 1 + extraBonus;
      _score += gained;

      _perfectText = _combo > 1
          ? 'PERFECT x$_combo  +$gained'
          : 'PERFECT  +$gained';
      _perfectTimer = 0.85;

      HapticFeedback.mediumImpact();
    } else {
      final cutLeftWidth = math.max(0.0, last.x - _lockedDropX);
      final cutRightWidth = math.max(
        0.0,
        (_lockedDropX + _movingWidth) - (last.x + last.width),
      );

      if (cutLeftWidth > 0) {
        _spawnCutPiece(
          x: _lockedDropX,
          width: cutLeftWidth,
          worldTop: placedWorldTop,
          color: _movingColor,
          leftSide: true,
        );
      }

      if (cutRightWidth > 0) {
        _spawnCutPiece(
          x: overlapRight,
          width: cutRightWidth,
          worldTop: placedWorldTop,
          color: _movingColor,
          leftSide: false,
        );
      }

      _combo = 0;
      _score += 1;
      HapticFeedback.lightImpact();
    }

    _placedBlocks.add(
      BlockData(x: overlapLeft, width: overlapWidth, color: _movingColor),
    );

    if (_score > _bestScore) {
      _bestScore = _score;
      _saveBestScore();
    }

    _movingWidth = overlapWidth;
    _speed = math.min(_speed + 18, 620);

    _spawnNextBlock();
  }

  void _finishGame() {
    _gameOver = true;
    _isDropping = false;
    _combo = 0;

    if (_ticker.isActive) {
      _ticker.stop();
    }

    if (_score > _bestScore) {
      _bestScore = _score;
      _saveBestScore();
    }

    _registerScore();
    HapticFeedback.heavyImpact();
  }

  Color _colorForLevel(int level) {
    final hue = (level * 31) % 360;
    return HSVColor.fromAHSV(1, hue.toDouble(), 0.62, 0.96).toColor();
  }

  Widget _buildBlock({
    required double width,
    required Color color,
    bool glow = false,
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
            color.withOpacity(0.98),
            Color.lerp(color, Colors.black, 0.18)!,
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.14), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(glow ? 0.42 : 0.20),
            blurRadius: glow ? 22 : 10,
            spreadRadius: glow ? 1 : 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }

  Widget _buildFallingPiece(FallingPiece piece) {
    return Transform.rotate(
      angle: piece.rotation,
      child: _buildBlock(width: piece.width, color: piece.color),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    Color? accent,
  }) {
    final baseColor = accent ?? Colors.white;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, color: baseColor),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.68),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: baseColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildMenu() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF101A31), Color(0xFF09111F), Color(0xFF050A14)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.08),
                            Colors.white.withOpacity(0.03),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 28,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 82,
                            height: 82,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7C4DFF), Color(0xFF00D4FF)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF7C4DFF,
                                  ).withOpacity(0.30),
                                  blurRadius: 28,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.stacked_bar_chart_rounded,
                              size: 42,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Torre de Blocos V3',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Agora com corte caindo animado e câmera acompanhando a torre até o topo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withOpacity(0.72),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _menuTag('Menu inicial'),
                              _menuTag('Queda animada'),
                              _menuTag('Perfect combo'),
                              _menuTag('Peça cortada caindo'),
                              _menuTag('Câmera dinâmica'),
                            ],
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _startGame,
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text(
                                  'Jogar',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        _statCard(
                          icon: Icons.workspace_premium_rounded,
                          label: 'Melhor pontuação',
                          value: '$_bestScore',
                          accent: const Color(0xFFFFD166),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: Colors.white.withOpacity(0.05),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Últimas partidas',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_recentScores.isEmpty)
                            Text(
                              'Nenhuma partida registrada ainda.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.68),
                              ),
                            )
                          else
                            Column(
                              children: List.generate(_recentScores.length, (
                                i,
                              ) {
                                return Container(
                                  margin: EdgeInsets.only(
                                    bottom: i == _recentScores.length - 1
                                        ? 0
                                        : 10,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    color: Colors.black.withOpacity(0.18),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: Colors.white
                                            .withOpacity(0.08),
                                        child: Text(
                                          '${i + 1}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Pontuação',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${_recentScores[i]}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGame() {
    final screenSize = MediaQuery.sizeOf(context);
    final boardHeight = math.min(screenSize.height * 0.58, 560.0);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF101A31), Color(0xFF09111F), Color(0xFF050A14)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _goToMenu,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Expanded(
                      child: Text(
                        'Torre de Blocos',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _resetGame,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _statCard(
                      icon: Icons.stacked_bar_chart_rounded,
                      label: 'Pontuação',
                      value: '$_score',
                      accent: const Color(0xFF00E5FF),
                    ),
                    const SizedBox(width: 12),
                    _statCard(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Combo',
                      value: '$_combo',
                      accent: const Color(0xFFFF8A3D),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statCard(
                      icon: Icons.workspace_premium_rounded,
                      label: 'Recorde',
                      value: '$_bestScore',
                      accent: const Color(0xFFFFD166),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: Center(
                    child: Container(
                      width: double.infinity,
                      constraints: BoxConstraints(
                        maxWidth: math.min(460, screenSize.width),
                      ),
                      height: boardHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.07),
                            Colors.white.withOpacity(0.02),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.26),
                            blurRadius: 28,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _handleTap,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _onBoardReady(
                                  constraints.maxWidth,
                                  constraints.maxHeight,
                                );
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
                                              0xFF13203C,
                                            ).withOpacity(0.52),
                                            const Color(
                                              0xFF0A1222,
                                            ).withOpacity(0.78),
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
                                      top: _screenYForWorldTop(
                                        _worldTopForLevel(i),
                                      ),
                                      child: _buildBlock(
                                        width: _placedBlocks[i].width,
                                        color: _placedBlocks[i].color,
                                      ),
                                    ),

                                  for (final piece in _fallingPieces)
                                    Positioned(
                                      left: piece.x,
                                      top: _screenYForWorldTop(piece.worldTop),
                                      child: _buildFallingPiece(piece),
                                    ),

                                  if (_boardReady && !_gameOver)
                                    Positioned(
                                      left: _isDropping
                                          ? _lockedDropX
                                          : _movingX,
                                      top: _isDropping
                                          ? _screenYForWorldTop(_dropWorldTop)
                                          : _screenYForWorldTop(
                                              _spawnWorldTopForLevel(
                                                _placedBlocks.length,
                                              ),
                                            ),
                                      child: _buildBlock(
                                        width: _movingWidth,
                                        color: _movingColor,
                                        glow: true,
                                      ),
                                    ),

                                  if (_perfectText.isNotEmpty &&
                                      _perfectTimer > 0)
                                    Positioned(
                                      top: 22,
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: Opacity(
                                          opacity: _perfectTimer.clamp(
                                            0.0,
                                            1.0,
                                          ),
                                          child: Transform.translate(
                                            offset: Offset(
                                              0,
                                              (1 - _perfectTimer) * -12,
                                            ),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 10,
                                                  ),
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(99),
                                                color: const Color(
                                                  0xFFFF8A3D,
                                                ).withOpacity(0.18),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFFFB36B,
                                                  ).withOpacity(0.55),
                                                ),
                                              ),
                                              child: Text(
                                                _perfectText,
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 0.4,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
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
                                            Colors.white.withOpacity(0.14),
                                            Colors.white.withOpacity(0.02),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),

                                  if (_gameOver)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.black.withOpacity(0.48),
                                        child: Center(
                                          child: Container(
                                            margin: const EdgeInsets.all(22),
                                            padding: const EdgeInsets.all(22),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF101A31),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              border: Border.all(
                                                color: Colors.white.withOpacity(
                                                  0.08,
                                                ),
                                              ),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.flag_rounded,
                                                  size: 44,
                                                ),
                                                const SizedBox(height: 12),
                                                const Text(
                                                  'Fim de jogo',
                                                  style: TextStyle(
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                Text(
                                                  'Pontuação: $_score',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  'Recorde: $_bestScore',
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    color: Colors.white
                                                        .withOpacity(0.76),
                                                  ),
                                                ),
                                                const SizedBox(height: 18),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: FilledButton.icon(
                                                    onPressed: _resetGame,
                                                    icon: const Icon(
                                                      Icons.replay,
                                                    ),
                                                    label: const Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 12,
                                                          ),
                                                      child: Text(
                                                        'Jogar novamente',
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: OutlinedButton.icon(
                                                    onPressed: _goToMenu,
                                                    icon: const Icon(
                                                      Icons.home_rounded,
                                                    ),
                                                    label: const Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            vertical: 12,
                                                          ),
                                                      child: Text(
                                                        'Voltar ao menu',
                                                      ),
                                                    ),
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
                Text(
                  'Toque na área do jogo para soltar o bloco.',
                  style: TextStyle(color: Colors.white.withOpacity(0.70)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _viewMode == ViewMode.menu ? _buildMenu() : _buildGame();
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..strokeWidth = 1;

    const gap = 32.0;

    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

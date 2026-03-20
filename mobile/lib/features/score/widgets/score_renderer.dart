import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 乐谱渲染器
///
/// 使用 WebView + OpenSheetMusicDisplay 渲染 MusicXML 五线谱
class ScoreRenderer extends StatefulWidget {
  /// MusicXML 内容
  final String musicXml;

  /// 当前高亮的小节号 (1-based)
  final int? highlightMeasure;

  /// 缩放比例 (默认 1.0)
  final double zoom;

  /// 循环区间起始小节 (1-based)
  final int? loopStartMeasure;

  /// 循环区间结束小节 (1-based)
  final int? loopEndMeasure;

  /// 渲染完成回调
  final void Function(ScoreRenderInfo info)? onRendered;

  /// 错误回调
  final void Function(String error)? onError;

  const ScoreRenderer({
    super.key,
    required this.musicXml,
    this.highlightMeasure,
    this.zoom = 1.0,
    this.onRendered,
    this.onError,
  });

  @override
  State<ScoreRenderer> createState() => _ScoreRendererState();
}

class _ScoreRendererState extends State<ScoreRenderer> {
  late WebViewController _controller;
  bool _isLoaded = false;
  bool _isRendered = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void didUpdateWidget(ScoreRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 乐谱内容变化 → 重新渲染
    if (widget.musicXml != oldWidget.musicXml && _isLoaded) {
      _renderScore();
    }

    // 高亮小节变化 → 更新高亮
    if (widget.highlightMeasure != oldWidget.highlightMeasure &&
        widget.highlightMeasure != null &&
        _isRendered) {
      _highlightMeasure(widget.highlightMeasure!);
    }

    // 缩放变化 → 更新缩放
    if (widget.zoom != oldWidget.zoom && _isRendered) {
      _setZoom(widget.zoom);
    }

    // 循环区间变化 → 更新高亮
    if ((widget.loopStartMeasure != oldWidget.loopStartMeasure ||
         widget.loopEndMeasure != oldWidget.loopEndMeasure) &&
        _isRendered) {
      if (widget.loopStartMeasure != null && widget.loopEndMeasure != null) {
        _highlightLoopRange(widget.loopStartMeasure!, widget.loopEndMeasure!);
      } else {
        _clearLoopHighlight();
      }
    }
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _isLoaded = true;
            // 页面加载完成后自动渲染乐谱
            if (widget.musicXml.isNotEmpty) {
              _renderScore();
            }
          },
          onWebResourceError: (error) {
            widget.onError?.call('WebView error: ${error.description}');
          },
        ),
      );

    // 加载本地 HTML
    _loadHtmlAsset();
  }

  Future<void> _loadHtmlAsset() async {
    final html = await rootBundle.loadString('assets/osmd/index.html');
    // 替换 CDN 引用为本地路径 (如果有本地文件的话)
    await _controller.loadHtmlString(html);
  }

  // ── JS → Flutter 通信 ──

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'initialized':
          // OSMD 初始化完成
          if (widget.musicXml.isNotEmpty) {
            _renderScore();
          }
          break;

        case 'rendered':
          _isRendered = true;
          final info = ScoreRenderInfo(
            measureCount: data['measureCount'] ?? 0,
            width: (data['width'] ?? 0).toDouble(),
            height: (data['height'] ?? 0).toDouble(),
          );
          widget.onRendered?.call(info);

          // 渲染完成后自动高亮
          if (widget.highlightMeasure != null) {
            _highlightMeasure(widget.highlightMeasure!);
          }
          break;

        case 'error':
          widget.onError?.call(data['message'] ?? 'Unknown error');
          break;

        case 'positions':
          // 小节位置信息
          break;
      }
    } catch (e) {
      debugPrint('JS message parse error: $e');
    }
  }

  // ── Flutter → JS 通信 ──

  void _sendMessage(Map<String, dynamic> message) {
    final json = jsonEncode(message);
    _controller.runJavaScript("window.osmdBridge.handleMessage('$json');");
  }

  void _renderScore() {
    // XML 内容需要转义
    final escapedXml = widget.musicXml
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '');

    _controller.runJavaScript(
      "window.osmdBridge.handleMessage('{\"action\":\"render\",\"xml\":\"$escapedXml\"}');",
    );
  }

  void _highlightMeasure(int measureIndex) {
    // measureIndex 是 1-based，转换为 0-based
    final zeroBased = measureIndex - 1;
    if (zeroBased < 0) return;
    _sendMessage({'action': 'highlight', 'measure': zeroBased});
  }

  void _setZoom(double zoom) {
    _sendMessage({'action': 'zoom', 'zoom': zoom});
  }

  void _highlightLoopRange(int startMeasure, int endMeasure) {
    _sendMessage({'action': 'highlightLoop', 'startMeasure': startMeasure, 'endMeasure': endMeasure});
  }

  void _clearLoopHighlight() {
    _sendMessage({'action': 'clearLoop'});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),

        // 加载指示器
        if (!_isRendered)
          const Positioned.fill(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 2),
                  SizedBox(height: 12),
                  Text('加载乐谱中...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 渲染信息
class ScoreRenderInfo {
  final int measureCount;
  final double width;
  final double height;

  ScoreRenderInfo({
    required this.measureCount,
    required this.width,
    required this.height,
  });

  @override
  String toString() =>
      'ScoreRenderInfo(measures=$measureCount, ${width}x$height)';
}

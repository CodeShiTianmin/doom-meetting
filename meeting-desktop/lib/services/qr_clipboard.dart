import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 二维码图片渲染 + 复制到系统剪贴板。
///
/// Windows 下通过 Win32 剪贴板 API 同时写入 CF_DIB 位图与 PNG 两种格式,
/// 可直接粘贴到微信/QQ/Word/浏览器等; 其它平台不支持图片复制(返回 false)。
class QrClipboard {
  QrClipboard._();

  static bool get imageSupported => Platform.isWindows;

  /// 渲染白底二维码图片, [caption] 显示在二维码下方(如「客户码1 · 3 号房间」)
  static Future<ui.Image> render(String data,
      {int size = 480, String? caption}) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
    );
    const margin = 32.0;
    const captionHeight = 36.0;
    final width = size.toDouble();
    final height = size + (caption == null ? 0.0 : captionHeight);
    final qrSize = width - margin * 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);
    canvas.save();
    canvas.translate(margin, margin);
    painter.paint(canvas, Size(qrSize, qrSize));
    canvas.restore();
    if (caption != null) {
      final text = TextPainter(
        text: TextSpan(
          text: caption,
          style: const TextStyle(
              color: Colors.black87,
              fontSize: 22,
              fontWeight: FontWeight.w600),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: qrSize);
      text.paint(canvas, Offset((width - text.width) / 2, width - margin / 2));
    }
    return recorder.endRecording().toImage(size, height.round());
  }

  /// 图片写入剪贴板; 不支持的平台或写入失败返回 false
  static Future<bool> copy(ui.Image image) async {
    if (!imageSupported) return false;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return false;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final dib = _buildDib(
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        image.width,
        image.height);
    return _writeToClipboard(
        dib, png?.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes));
  }
}

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final int Function(int) _openClipboard = _user32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('OpenClipboard');

final int Function() _emptyClipboard = _user32
    .lookupFunction<Int32 Function(), int Function()>('EmptyClipboard');

final int Function() _closeClipboard = _user32
    .lookupFunction<Int32 Function(), int Function()>('CloseClipboard');

final int Function(int, int) _setClipboardData = _user32.lookupFunction<
    IntPtr Function(Uint32, IntPtr), int Function(int, int)>('SetClipboardData');

final int Function(Pointer<Utf16>) _registerClipboardFormat =
    _user32.lookupFunction<Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)>('RegisterClipboardFormatW');

final int Function(int, int) _globalAlloc = _kernel32.lookupFunction<
    IntPtr Function(Uint32, IntPtr), int Function(int, int)>('GlobalAlloc');

final Pointer<Uint8> Function(int) _globalLock = _kernel32.lookupFunction<
    Pointer<Uint8> Function(IntPtr),
    Pointer<Uint8> Function(int)>('GlobalLock');

final int Function(int) _globalUnlock = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('GlobalUnlock');

final int Function(int) _globalFree = _kernel32
    .lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GlobalFree');

const int _cfDib = 8;
const int _gmemMoveable = 0x0002;
const int _bitmapInfoHeaderSize = 40;

/// RGBA 像素 -> 32 位 BI_RGB 设备无关位图(BITMAPINFOHEADER + BGRA, 自下而上)
Uint8List _buildDib(Uint8List rgba, int width, int height) {
  final stride = width * 4;
  final out = Uint8List(_bitmapInfoHeaderSize + stride * height);
  final header = ByteData.view(out.buffer);
  header.setUint32(0, _bitmapInfoHeaderSize, Endian.little);
  header.setInt32(4, width, Endian.little);
  header.setInt32(8, height, Endian.little);
  header.setUint16(12, 1, Endian.little);
  header.setUint16(14, 32, Endian.little);
  header.setUint32(16, 0, Endian.little);
  header.setUint32(20, stride * height, Endian.little);
  for (var y = 0; y < height; y++) {
    final src = y * stride;
    final dst = _bitmapInfoHeaderSize + (height - 1 - y) * stride;
    for (var x = 0; x < stride; x += 4) {
      // 透明像素按白底处理, 避免在忽略 alpha 的应用中显示为黑底
      if (rgba[src + x + 3] == 0) {
        out[dst + x] = 0xFF;
        out[dst + x + 1] = 0xFF;
        out[dst + x + 2] = 0xFF;
      } else {
        out[dst + x] = rgba[src + x + 2];
        out[dst + x + 1] = rgba[src + x + 1];
        out[dst + x + 2] = rgba[src + x];
      }
      out[dst + x + 3] = 0xFF;
    }
  }
  return out;
}

/// 拷贝到可移动全局内存, 返回 HGLOBAL(失败返回 0)
int _toGlobal(Uint8List bytes) {
  final handle = _globalAlloc(_gmemMoveable, bytes.length);
  if (handle == 0) return 0;
  final ptr = _globalLock(handle);
  if (ptr == nullptr) {
    _globalFree(handle);
    return 0;
  }
  ptr.asTypedList(bytes.length).setAll(0, bytes);
  _globalUnlock(handle);
  return handle;
}

bool _writeToClipboard(Uint8List dib, Uint8List? png) {
  // 其它程序可能短暂占用剪贴板, 打开失败时稍候重试
  var opened = false;
  for (var attempt = 0; attempt < 5 && !opened; attempt++) {
    opened = _openClipboard(0) != 0;
    if (!opened) sleep(const Duration(milliseconds: 20));
  }
  if (!opened) return false;
  try {
    if (_emptyClipboard() == 0) return false;
    final dibHandle = _toGlobal(dib);
    if (dibHandle == 0) return false;
    // 成功后内存所有权归系统, 失败时自行释放
    if (_setClipboardData(_cfDib, dibHandle) == 0) {
      _globalFree(dibHandle);
      return false;
    }
    if (png != null) {
      final name = 'PNG'.toNativeUtf16();
      final format = _registerClipboardFormat(name);
      calloc.free(name);
      if (format != 0) {
        final pngHandle = _toGlobal(png);
        if (pngHandle != 0 && _setClipboardData(format, pngHandle) == 0) {
          _globalFree(pngHandle);
        }
      }
    }
    return true;
  } finally {
    _closeClipboard();
  }
}

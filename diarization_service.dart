import 'dart:io';
import 'dart:typed_data';
import '../models/transcription_model.dart';

/// خدمة فصل متحدثين محلية مبسّطة تعتمد على تغيّرات مستوى الطاقة الصوتية
/// (RMS) في ملف WAV أحادي القناة بمعدل 16kHz لتقدير حدود تبديل المتحدث.
///
/// ملاحظة صريحة: هذا ليس فصل متحدثين دلالي (embedding-based) حقيقياً —
/// دقة عالية تتطلب نموذج ML مخصص (مثل pyannote) وهو غير متاح محلياً على
/// الجوال دون بنية تحتية إضافية. هذه الخدمة توفر تقريباً عملياً أولياً
/// يمكن تحسينه لاحقاً في مرحلة منفصلة عند إضافة نموذج diarization فعلي.
class DiarizationService {
  static const int _sampleRate = 16000;
  static const double _windowSeconds = 0.5;
  static const double _silenceThreshold = 0.02;
  static const double _speakerChangeSensitivity = 1.8;

  /// تحليل ملف WAV وإرجاع نسخة من المقاطع بعد وسم كل مقطع بمتحدث تقديري
  Future<List<TranscriptionSegment>> assignSpeakers(
    String wavFilePath,
    List<TranscriptionSegment> segments,
  ) async {
    final file = File(wavFilePath);
    if (!await file.exists() || segments.isEmpty) return segments;

    final bytes = await file.readAsBytes();
    final samples = _decodePcm16(bytes);
    if (samples.isEmpty) return segments;

    final energyProfile = _computeEnergyProfile(samples);
    final changePoints = _detectSpeakerChanges(energyProfile);

    var speakerIndex = 1;
    final result = <TranscriptionSegment>[];
    for (final seg in segments) {
      final segStartSec = seg.start.inMilliseconds / 1000.0;
      final crossesChange = changePoints.any(
        (t) => (t - segStartSec).abs() < _windowSeconds,
      );
      if (crossesChange && result.isNotEmpty) {
        speakerIndex = speakerIndex == 1 ? 2 : 1;
      }
      result.add(TranscriptionSegment(
        text: seg.text,
        start: seg.start,
        end: seg.end,
        language: seg.language,
        speaker: 'Speaker $speakerIndex',
      ));
    }
    return result;
  }

  /// فك ترميز PCM 16-bit little-endian من محتوى ملف WAV (يتجاوز الترويسة 44 بايت)
  List<double> _decodePcm16(Uint8List bytes) {
    if (bytes.length <= 44) return [];
    final data = ByteData.sublistView(bytes, 44);
    final sampleCount = data.lengthInBytes ~/ 2;
    final samples = List<double>.filled(sampleCount, 0);
    for (var i = 0; i < sampleCount; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  /// حساب مستوى الطاقة (RMS) لكل نافذة زمنية على طول التسجيل
  List<double> _computeEnergyProfile(List<double> samples) {
    final windowSize = (_sampleRate * _windowSeconds).round();
    final profile = <double>[];
    for (var i = 0; i < samples.length; i += windowSize) {
      final end = (i + windowSize < samples.length) ? i + windowSize : samples.length;
      var sumSquares = 0.0;
      for (var j = i; j < end; j++) {
        sumSquares += samples[j] * samples[j];
      }
      final rms = (sumSquares / (end - i)).abs();
      profile.add(rms > 0 ? rms : 0);
    }
    return profile;
  }

  /// تحديد نقاط زمنية (بالثواني) يُحتمل عندها تبدّل المتحدث بناءً على قفزات الطاقة
  List<double> _detectSpeakerChanges(List<double> energyProfile) {
    final changePoints = <double>[];
    for (var i = 1; i < energyProfile.length; i++) {
      final prev = energyProfile[i - 1];
      final curr = energyProfile[i];
      if (prev < _silenceThreshold && curr < _silenceThreshold) continue;
      final ratio = curr > prev
          ? curr / (prev == 0 ? 0.0001 : prev)
          : prev / (curr == 0 ? 0.0001 : curr);
      if (ratio > _speakerChangeSensitivity) {
        changePoints.add(i * _windowSeconds);
      }
    }
    return changePoints;
  }
}

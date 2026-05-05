import 'package:flutter_midi_pro/flutter_midi_pro.dart';

class AudioPlaybackService {
  final MidiPro _midi = MidiPro();

  bool _isInitialized = false;
  int _soundFontId = 1;

  static const int _guitarBank = 0;
  static const int _guitarProgram = 25; // Steel guitar / working preset

  Future<void> init() async {
    if (_isInitialized) {
      print('AUDIO: already initialized sfId=$_soundFontId');
      return;
    }

    print('AUDIO: loading soundfont...');

    _soundFontId = await _midi.loadSoundfontAsset(
      assetPath: 'assets/soundfonts/acoustic_guitar.sf2',
      bank: _guitarBank,
      program: _guitarProgram,
    );

    print('AUDIO: soundfont loaded sfId=$_soundFontId');

    await _midi.selectInstrument(
      sfId: _soundFontId,
      channel: 0,
      bank: _guitarBank,
      program: _guitarProgram,
    );

    print('AUDIO: selected instrument program 24');

    _isInitialized = true;
  }

  Future<void> playNote(int midiNote, {int velocity = 120}) async {
    await init();

    print('AUDIO: playNote key=$midiNote sfId=$_soundFontId velocity=$velocity');

    await _midi.playNote(
      sfId: _soundFontId,
      channel: 0,
      key: midiNote,
      velocity: velocity,
    );
  }

  Future<void> stopNote(int midiNote) async {
    if (!_isInitialized) return;

    await _midi.stopNote(
      sfId: _soundFontId,
      channel: 0,
      key: midiNote,
    );
  }

  Future<void> playChord(List<int> notes, {int velocity = 95}) async {
    await init();

    for (final note in notes) {
      await playNote(note, velocity: velocity);
    }
  }

  Future<void> stopChord(List<int> notes) async {
    if (!_isInitialized) return;

    for (final note in notes) {
      await stopNote(note);
    }

    await stopAll();
  }

  Future<void> stopAll() async {
    if (!_isInitialized) return;

    await _midi.stopAllNotes(sfId: _soundFontId);
  }

  Future<void> testSound() async {
    await init();

    await _midi.playNote(
      sfId: _soundFontId,
      channel: 0,
      key: 64,
      velocity: 120,
    );

    await Future.delayed(const Duration(milliseconds: 1200));

    await _midi.stopNote(
      sfId: _soundFontId,
      channel: 0,
      key: 64,
    );
  }

  /// For debugging sound
  /*
  Future<void> scanPrograms() async {
    await init();

    print('--- SCANNING PROGRAMS ---');

    for (int program = 0; program < 128; program++) {
      print('Trying program $program');

      await _midi.selectInstrument(
        sfId: _soundFontId,
        channel: 0,
        bank: 0,
        program: program,
      );

      await _midi.playNote(
        sfId: _soundFontId,
        channel: 0,
        key: 64,
        velocity: 120,
      );

      await Future.delayed(const Duration(milliseconds: 500));
    }

    print('--- SCAN DONE ---');
  }
  */

  Future<void> dispose() async {
    await stopAll();
    _midi.dispose();
  }
}